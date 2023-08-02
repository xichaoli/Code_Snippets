#!/bin/bash
# 一但有任何一个语句返回非真的值，则退出bash
set -e

# 必须使用有root权限的用户
[[ $(id -u) -ne 0 ]] && echo -e "\e[1;31mYou must be root!\e[m" && exit 1

# 调试开关, export DEBUG=true 打开
DEBUG() {
    if [ "$DEBUG" = "true" ]; then
        "$@"
    fi
}

# 脚本使用说明
usage() {
    echo -e "\e[0;32mUsage:\e[m"
    echo -e "\e[0;32m  $0 -d DEST_DISK -o[OS_RELEASE] -b[BOARD_TYPE] -g GIT_VERSION\e[m"
    echo -e "\e[5;33m      Attention: No space between -o and OS_RELEASE, -b and BOARD_TYPE\e[m"
    echo -e "\e[0;32m  $0 --device DEST_DISK --OS [OS_RELEASE] --board [BOARD_TYPE] --git-version GIT_VERSION\e[m"
    echo -e "\e[0;32mOptions:\e[m"
    echo -e "\e[0;32m  -d|--device DEST_DISK           DEST_DISK is a value similar to sda, sdb\e[m"
    echo -e "\e[0;32m  -o|--OS OS_RELEASE              OS_RELEASE can be deepin and neokylin. Default is deepin.\e[m"
    echo -e "\e[0;32m  -b|--board BOARD_TYPE           BOARD_TYPE can be aere and wutip. Default is wutip.\e[m"
    echo -e "\e[0;32m  -g|--git-version GIT_VERSION    GIT_VERSION is start with g, then add the first 7 bits of the latest commit id.\e[m"
    echo -e "\e[5;33mAttention: This script currently does not support the installation of UOS, and will not be updated in the future.\e[m"
    echo -e "\e[5;33m           Recommend to use run_dialog.sh. \e[m"
    exit 0
}

# 运行时需要加参数
[[ "$#" -eq 0 ]] && usage

# 获取当前目录
PROJECT_TOP=${PWD}
DEBUG echo "${PROJECT_TOP}"

# 使用 getopt 获取参数
OPTS_OBTAINED=$(getopt -o d:o::b::g: --long device:,OS::,board::,git-version: -- "$@")
eval set -- "${OPTS_OBTAINED}"
DEBUG echo "${OPTS_OBTAINED}"
while true; do
    case "$1" in
    -d | --device)
        DEST_DISK="$2"
        shift 2
        ;;
    -o | --OS)
        case "$2" in
        "")
            OS_RELEASE="deepin"
            ;;
        *)
            OS_RELEASE="$2"
            ;;
        esac
        shift 2
        ;;
    -b | --board)
        case "$2" in
        "")
            BOARD_TYPE="wutip"
            ;;
        *)
            BOARD_TYPE="$2"
            ;;
        esac
        shift 2
        ;;
    -g | --git-version)
        GIT_VERSION="$2"
        shift 2
        ;;
    --)
        shift
        break
        ;;
    *)
        echo -e "\e[1;31mIncorrect option!\e[m"
        exit 1
        ;;
    esac
done

# 判断所输入的磁盘是否存在
if [ ! -b /dev/"${DEST_DISK}" ]; then
    echo -e "\e[1;31mDisk does not exist!\e[m"
    usage
fi
DEBUG echo DEST_DISK="${DEST_DISK}"

# 判断所输入的操作系统版本是否支持
if [ "deepin" != "${OS_RELEASE}" ] && [ "neokylin" != "${OS_RELEASE}" ]; then
    echo -e "\e[1;31mThe OS_RELEASE can only be deepin and neokylin !\e[m"
    usage
fi
DEBUG echo OS_RELEASE="${OS_RELEASE}"

# 获取dump文件中的磁盘标识符
Old_Disk_Identifier=$(grep label-id partition/"${OS_RELEASE}".partition.dump | awk '{print $2}')
DEBUG echo Old_Disk_Identifier="${Old_Disk_Identifier}"

# 生成新的磁盘标识符
New_Disk_Identifier="0x"$(uuidgen | awk -F '-' '{print$1}')
DEBUG echo New_Disk_Identifier="${New_Disk_Identifier}"

# 替换dump文件中的磁盘标识符
# 下面语句中的 '"${Old_Disk_Identifier}"' 部分,
#     双引号是为了去除警告 SC2086 (请使用双引号来避免 glob 和单词分割)
#     单引号是为了替换变量,不加单引号的话,变量会被替换成字符串 ${Old_Disk_Identifier}
sed -i '2s#'"${Old_Disk_Identifier}"'#'"${New_Disk_Identifier}"'#' partition/"${OS_RELEASE}".partition.dump
DEBUG echo Now_Disk_Identifier="$(grep label-id partition/"${OS_RELEASE}".partition.dump | awk '{print $2}')"

# 判断主板类型是否输入正确
if [ "aere" != "${BOARD_TYPE}" ] && [ "wutip" != "${BOARD_TYPE}" ]; then
    echo -e "\e[1;31mThe BOARD_TYPE can only be aere and wutip !\e[m"
    usage
fi
DEBUG echo BOARD_TYPE="${BOARD_TYPE}"

# 内核版本
KERNEL_VERSION=4.4.15

# 内核的git commit id
DEBUG echo GIT_VERSION="${GIT_VERSION}"

Prepare_the_disk() {
    # 使用替换后的dump文件生成硬盘${DEST_DISK}的分区表
    sfdisk /dev/"${DEST_DISK}" <partition/"${OS_RELEASE}".partition.dump

    # 格式化各分区
    mkfs.ext4 -F /dev/"${DEST_DISK}"1

    # 暂时都分为两个区
    mkfs.ext4 -F /dev/"${DEST_DISK}"2

    # 挂载需要拷贝数据的分区
    mkdir -p "${PROJECT_TOP}"/mountpoint/{1,2}
    mount /dev/"${DEST_DISK}"1 "${PROJECT_TOP}"/mountpoint/1
    mount /dev/"${DEST_DISK}"2 "${PROJECT_TOP}"/mountpoint/2
}

OS_Copy() {
    echo "Copy boot to partition 1 !"
    cp -a OS/"${OS_RELEASE}"/boot-"${BOARD_TYPE}"-"${GIT_VERSION}"/* "${PROJECT_TOP}"/mountpoint/1/
    echo "Copy rootfs to partition 2 !"
    cp -a OS/"${OS_RELEASE}"/rootfs/* "${PROJECT_TOP}"/mountpoint/2/
    echo "Copy kernel modules to rootfs !"
    cp -a OS/"${OS_RELEASE}"/${KERNEL_VERSION}-"${OS_RELEASE}"-"${BOARD_TYPE}"-"${GIT_VERSION}" "${PROJECT_TOP}"/mountpoint/2/lib/modules/
}

# 确认下输入的参数是否正确，特别 -o 和 -b 的参数
echo -e "\e[0;32mWhat you want to do:\e[m"
echo -e "\e[0;32m  DEST_DISK is ${DEST_DISK}\e[m"
echo -e "\e[0;32m  BOARD_TYPE is ${BOARD_TYPE}\e[m"
echo -e "\e[0;32m  OS_RELEASE is ${OS_RELEASE}\e[m"
echo -e "\e[0;32m  GIT_VERSION is ${GIT_VERSION}\e[m"
echo
read -r -p "If not what you want, check over usage. Are You Sure? [Y/n]" input
DEBUG echo input is "$input"

case $input in
[yY][es] | [yY])
    Prepare_the_disk
    DEBUG lsblk
    OS_Copy
    sync
    echo "umount ${PROJECT_TOP}/mountpoint/1"
    umount "${PROJECT_TOP}"/mountpoint/1
    echo "umount ${PROJECT_TOP}/mountpoint/2"
    umount "${PROJECT_TOP}"/mountpoint/2
    ;;
[nN][o] | [nN])
    exit 1
    ;;
esac
