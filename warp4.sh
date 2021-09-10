##### 为 IPv6 only VPS 添加 WGCF，IPv4走 warp #####
##### KVM 属于完整虚拟化的 VPS 主机，网络性能方面：内核模块＞wireguard-go。#####

# 判断系统，安装差异部分依赖包
echo -e "\033[32m (1/3) 安装系统依赖和 wireguard 内核模块 \033[0m"

# Debian 运行以下脚本
if grep -q -E -i "debian" /etc/issue; then
	
	# 更新源
	apt update

	# 添加 backports 源,之后才能安装 wireguard-tools 
	apt -y install lsb-release sudo
	echo "deb http://deb.debian.org/debian $(lsb_release -sc)-backports main" | tee /etc/apt/sources.list.d/backports.list

	# 再次更新源
	apt update

	# 安装一些必要的网络工具包和wireguard-tools (Wire-Guard 配置工具：wg、wg-quick)
	sudo apt -y --no-install-recommends install net-tools iproute2 openresolv dnsutils wireguard-tools linux-headers-$(uname -r)
	
	# 安装 wireguard 内核模块
	sudo apt -y --no-install-recommends install wireguard-dkms
	
# Ubuntu 运行以下脚本
     elif grep -q -E -i "ubuntu" /etc/issue; then

	# 更新源
	apt update

	# 安装一些必要的网络工具包和 wireguard-tools (Wire-Guard 配置工具：wg、wg-quick)
	apt -y --no-install-recommends install net-tools iproute2 openresolv dnsutils wireguard-tools sudo

# CentOS 运行以下脚本
     elif grep -q -E -i "kernel" /etc/issue; then

	# 安装一些必要的网络工具包和wireguard-tools (Wire-Guard 配置工具：wg、wg-quick)
	yum -y install epel-release sudo
	sudo yum -y install net-tools wireguard-tools

	# 安装 wireguard 内核模块
	sudo curl -Lo /etc/yum.repos.d/wireguard.repo https://copr.fedorainfracloud.org/coprs/jdoss/wireguard/repo/epel-7/jdoss-wireguard-epel-7.repo
	sudo yum -y install epel-release wireguard-dkms

	# 升级所有包同时也升级软件和系统内核
	sudo yum -y update
	
	# 添加执行文件环境变量
        if [[ $PATH =~ /usr/local/bin ]]; then export PATH=$PATH; else export PATH=$PATH:/usr/local/bin; fi

# 如都不符合，提示,删除临时文件并中止脚本
     else 
	# 提示找不到相应操作系统
	echo -e "\033[32m 抱歉，我不认识此系统！\033[0m"
	
	# 删除临时目录和文件，退出脚本
	rm -f warp4.sh menu.sh
	exit 0

fi

# 以下为3类系统公共部分
echo -e "\033[32m (2/3) 安装 WGCF \033[0m"

# 判断系统架构是 AMD 还是 ARM
if [[ $(hostnamectl) =~ .*arm.* ]]
        then architecture=arm64
        else architecture=amd64
fi

# 判断 wgcf 的最新版本
latest=$(wget -qO- -t1 -T2 "https://api.github.com/repos/ViRb3/wgcf/releases/latest" | grep "tag_name" | head -n 1 | awk -F ":" '{print $2}' | sed 's/\"//g;s/v//g;s/,//g;s/ //g')

# 安装 wgcf
sudo wget -N -6 -O /usr/local/bin/wgcf https://github.com/ViRb3/wgcf/releases/download/v$latest/wgcf_${latest}_linux_$architecture

# 添加执行权限
sudo chmod +x /usr/local/bin/wgcf

# 注册 WARP 账户 (将生成 wgcf-account.toml 文件保存账户信息，为避免文件已存在导致出错，先尝试删掉原文件)
rm -f wgcf-account.toml
echo -e "\033[32m wgcf 注册中。 \033[0m"
until [[ -a wgcf-account.toml ]]
  do
   echo | wgcf register >/dev/null 2>&1
done

# 生成 Wire-Guard 配置文件 (wgcf-profile.conf)
wgcf generate >/dev/null 2>&1

# 修改配置文件 wgcf-profile.conf 的内容,使得 IPv4 的流量均被 WireGuard 接管，让 IPv4 的流量通过 WARP IPv6 节点以 NAT 的方式访问外部 IPv4 网络
sudo sed -i '/\:\:\/0/d' wgcf-profile.conf | sudo sed -i 's/engage.cloudflareclient.com/[2606:4700:d0::a29f:c001]/g' wgcf-profile.conf

# 把 wgcf-profile.conf 复制到/etc/wireguard/ 并命名为 wgcf.conf
sudo cp wgcf-profile.conf /etc/wireguard/wgcf.conf

# 自动刷直至成功（ warp bug，有时候获取不了ip地址）
echo -e "\033[32m (3/3) 运行 WGCF \033[0m"
echo -e "\033[32m 后台获取 warp IP 中，有时候需10分钟，请耐心等待。 \033[0m"
wg-quick up wgcf >/dev/null 2>&1
until [[ -n $(wget -qO- -4 ip.gs) ]]
  do
   wg-quick down wgcf >/dev/null 2>&1
   wg-quick up wgcf >/dev/null 2>&1
done

# 设置开机启动
systemctl enable wg-quick@wgcf >/dev/null 2>&1

# 优先使用 IPv4 网络
if [[ -e /etc/gai.conf ]]; then grep -qE '^[ ]*precedence[ ]*::ffff:0:0/96[ ]*100' /etc/gai.conf || echo 'precedence ::ffff:0:0/96  100' | tee -a /etc/gai.conf >/dev/null 2>&1; fi

# 结果提示
echo -e "\033[32m 恭喜！为 IPv4 only VPS 添加 warp 已成功，IPv6地址为:$(wget -qO- -6 ip.gs) \033[0m"

# 删除临时文件
rm -f warp4.sh wgcf-account.toml wgcf-profile.conf menu.sh
