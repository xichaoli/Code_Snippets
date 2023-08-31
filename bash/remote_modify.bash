#!/usr/bin/env bash
# 定义DHCP服务器所使用的网口, 根据实际情况修改
interface="eno1"

# 获取本机网口IP地址
local_ip=$(ip -4 addr show dev "${interface}" | grep -oP '(?<=inet\s)\d+(\.\d+){3}')

# 定义要扫描的网段, 根据实际情况修改
# network="192.168.0.0/24"
network="192.168.0.10-100"

# 定义网关地址, 根据实际情况修改
gateway="192.168.0.1"

# 使用nmap进行arp扫描,提取输出中的IP地址, 正则表达式不太严谨, 但是当前情况可以满足需求
# 通过这种方式获取客户端的IP地址,请确保连接到此DHCP服务器的客户端只有要修改的云终端设备
ips=$(nmap -sn ${network} | grep -oE '[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}')

# 将IP地址写入数组
# shellcheck disable=SC2206
ip_array=(${ips})

# 遍历数组
for ip in "${ip_array[@]}"; do
  # 过滤掉本机IP地址和网关地址
  if [[ "${ip}" == "${local_ip}" ]] || [[ "${ip}" == "${gateway}" ]]; then
    continue
  fi

  echo "${ip}"

  # 单机测试,测试成功后去掉外层if
  if [[ "${ip}" == "192.168.0.163" ]]; then
    if sshpass -p u18 ssh -o PreferredAuthentications=password -o StrictHostKeyChecking=no -t u18@"${ip}" "echo u18 | sudo -S sed -i '3!b; /--no-block -o utf8/!s/--no-block/--no-block -o utf8/g' /lib/udev/rules.d/99-usbblock.rules"; then
      echo -e "\e[1;32mClient ${ip} modify success.\e[0m"
      sshpass -p u18 ssh -o PreferredAuthentications=password -t u18@"${ip}" "echo u18 | sudo -S poweroff"
    else
      echo -e "\e[1;31mClient ${ip} modify failed!\e[0m"
    fi
  fi
done
