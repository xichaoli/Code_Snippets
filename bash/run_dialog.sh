#!/bin/bash
# 一但有任何一个语句返回非真的值，则退出bash
set -e

# 必须使用有root权限的用户
if [[ $(id -u) -ne 0 ]]; then
    whiptail --title "Error message" --msgbox "You must have root permission!" 10 60
    exit 1
fi

# 调试开关, export DEBUG=true 打开
DEBUG() {
    if [ "$DEBUG" = "true" ]; then
        "$@"
    fi
}

# 获取当前目录
PROJECT_TOP=${PWD}
DEBUG echo PROJECT_TOP is "${PROJECT_TOP}"

# 选择安装在哪个磁盘
DEST_DISK=$(
    whiptail --title "Disk selection" --inputbox \
        "\nWhich disk to install the operating system on?\n" 10 60 sdb 3>&1 1>&2 2>&3
)
# 判断所输入的磁盘是否存在
if [ ! -b /dev/"${DEST_DISK}" ]; then
    whiptail --title "Error message" --msgbox "\nDisk does not exist!\n" 8 60
    exit 1
fi
DEBUG echo DEST_DISK is "${DEST_DISK}"

# 选择要安装的操作系统版本
OS_RELEASE=$(
    whiptail --title "OS selection" --radiolist \
        "\nWhich operating system to install\n" 10 60 3 \
        "deepin" "server v15" ON \
        "neokylin" "server v7.0" OFF \
        "uos" "server v20" OFF \
        3>&1 1>&2 2>&3
)
DEBUG echo OS_RELEASE is "${OS_RELEASE}"

# 选择主板类型
if [ "uos" == "${OS_RELEASE}" ]; then
    BOARD_TYPE=$(whiptail --title "OS selection" --inputbox \
        "\nCurrently, UOS system only supports aere motherboard\n" 10 60 aere \
        3>&1 1>&2 2>&3)
else
    BOARD_TYPE=$(whiptail --title "OS selection" --radiolist \
        "\nWhich board to install\n" 10 60 2 \
        "wutip" "No ICH2" ON \
        "aere" "Have ICH2" OFF \
        3>&1 1>&2 2>&3)
fi
DEBUG echo BOARD_TYPE is "${BOARD_TYPE}"

# 内核版本,目前只支持 4.4.15
KERNEL_VERSION=4.4.15

# 获取内核的git commit id
if [ "deepin" == "${OS_RELEASE}" ]; then
    NOW_GIT_VERSION=g89bf0b23
elif [ "neokylin" == "${OS_RELEASE}" ]; then
    NOW_GIT_VERSION=g89bf0b2
else
    NOW_GIT_VERSION=
fi

if [ "uos" != "${OS_RELEASE}" ]; then
    GIT_VERSION=$(
        whiptail --title "Git version" --inputbox \
            "\nEnter the git version of kernel \n" 10 60 $NOW_GIT_VERSION 3>&1 1>&2 2>&3
    )
fi
DEBUG echo GIT_VERSION is "${GIT_VERSION}"

Prepare_the_disk() {
    echo XXX
    echo 1
    echo "Generating partition table ..."
    # 获取dump文件中的磁盘标识符
    local Old_Disk_Identifier
    Old_Disk_Identifier=$(grep label-id partition/"${OS_RELEASE}".partition.dump | awk '{print $2}')
    DEBUG echo Old_Disk_Identifier="${Old_Disk_Identifier}"

    # 生成新的磁盘标识符
    local New_Disk_Identifier
    New_Disk_Identifier="0x"$(uuidgen | awk -F '-' '{print$1}')
    DEBUG echo New_Disk_Identifier="${New_Disk_Identifier}"

    # 替换dump文件中的磁盘标识符
    sed -i '2s#'"${Old_Disk_Identifier}"'#'"${New_Disk_Identifier}"'#' partition/"${OS_RELEASE}".partition.dump
    DEBUG echo Now_Disk_Identifier="$(grep label-id partition/"${OS_RELEASE}".partition.dump | awk '{print $2}')"

    # 使用替换后的dump文件生成硬盘${DEST_DISK}的分区表
    sfdisk /dev/"${DEST_DISK}" <partition/"${OS_RELEASE}".partition.dump >/dev/null 2>&1
    echo XXX

    echo XXX
    echo 5
    echo "Formatting the first partition ..."
    # 格式化各分区
    mkfs.ext4 -q -F /dev/"${DEST_DISK}"1 >/dev/null 2>&1
    echo XXX
    echo XXX
    echo 10
    echo "Format the second partition ..."
    # 暂时都分为两个区
    mkfs.ext4 -q -F /dev/"${DEST_DISK}"2 >/dev/null 2>&1
    echo XXX
    echo XXX
    echo 20
    echo "Mounting partitions ..."
    # 挂载需要拷贝数据的分区
    mkdir -p "${PROJECT_TOP}"/mountpoint/{1,2}
    mount /dev/"${DEST_DISK}"1 "${PROJECT_TOP}"/mountpoint/1
    mount /dev/"${DEST_DISK}"2 "${PROJECT_TOP}"/mountpoint/2
    echo XXX
}

OS_Copy() {
    echo XXX
    echo 21
    echo "Copy boot to partition 1 !"
    if [[ "uos" == "${OS_RELEASE}" ]]; then
        cp -a OS/"${OS_RELEASE}"/boot-aere/* "${PROJECT_TOP}"/mountpoint/1/
    else
        cp -a OS/"${OS_RELEASE}"/boot-"${BOARD_TYPE}"-"${GIT_VERSION}"/* "${PROJECT_TOP}"/mountpoint/1/
    fi
    echo XXX
    echo XXX
    echo 25
    echo "Copy rootfs to partition 2 !"
    cp -a OS/"${OS_RELEASE}"/rootfs/* "${PROJECT_TOP}"/mountpoint/2/
    echo XXX
    echo XXX
    echo 80
    echo "Copy kernel modules to rootfs !"
    if [[ "uos" == "${OS_RELEASE}" ]]; then
        :
    else
        cp -a OS/"${OS_RELEASE}"/${KERNEL_VERSION}-"${OS_RELEASE}"-"${BOARD_TYPE}"-"${GIT_VERSION}" "${PROJECT_TOP}"/mountpoint/2/lib/modules/
    fi
    echo XXX
}

if (whiptail --title "Confirm your choice" \
    --yesno "The above selection.\n
	DEST_DISK   is ${DEST_DISK} \n
	OS_RELEASE  is ${OS_RELEASE} \n
	BOARD_TYPE  is ${BOARD_TYPE} \n
	GIT_VERSION is ${GIT_VERSION} \n
The data is priceless, please confirm it again and again before you do so!" 20 60 3>&1 1>&2 2>&3); then
    {
        Prepare_the_disk
        OS_Copy
        echo XXX
        echo 85
        echo "Synchronizing disk data ..."
        sync
        echo XXX
        echo XXX
        echo 95
        echo "Unmounting partitions ..."
        umount "${PROJECT_TOP}"/mountpoint/1
        umount "${PROJECT_TOP}"/mountpoint/2
        echo XXX
        echo 100
        sleep 1
    } | whiptail --gauge "Please wait while installing" 6 60 0
fi
