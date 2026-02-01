#!/bin/bash
# Author: Slotheve - Modified for v3/v4 Coexistence by Linux Server Expert

RED="\033[31m"
GREEN="\033[32m"
YELLOW="\033[33m"
BLUE="\033[36m"
PLAIN='\033[0m'

IP4=`curl -sL -4 ip.sb`
IP6=`curl -sL -6 ip.sb`
CPU=`uname -m`

versions=(v3 v5)

colorEcho() {
    echo -e "${1}${@:2}${PLAIN}"
}

archAffix(){
    if [[ "$CPU" = "x86_64" ]] || [[ "$CPU" = "amd64" ]]; then
        CPU="amd64"
        ARCH="x86_64"
    elif [[ "$CPU" = "armv8" ]] || [[ "$CPU" = "aarch64" ]]; then
        CPU="arm64"
        ARCH="aarch64"
    else
        colorEcho $RED "不支持的 CPU 架构！"
        exit 1
    fi
}

checkSystem() {
    if [[ $EUID -ne 0 ]]; then
        colorEcho $RED "请以 root 身份运行该脚本！"
        exit 1
    fi
}

Install_dependency(){
    if command -v yum >/dev/null 2>&1; then
        yum install unzip wget curl -y >/dev/null 2>&1
    elif command -v apt >/dev/null 2>&1; then
        apt update && apt install unzip wget curl -y >/dev/null 2>&1
    else
        colorEcho $RED "不支持的 Linux 系统！"
        exit 1
    fi
}

selectversion() {
    echo -e "${BLUE}请选择 Snell 版本：${PLAIN}"
    for ((i=1;i<=${#versions[@]};i++)); do
        echo -e "${GREEN}${i}${PLAIN}) ${versions[$i-1]}"
    done
    read -p "请选择版本[1-${#versions[@]}] (默认: 2): " pick
    [[ -z "$pick" ]] && pick=2
    if [[ "$pick" -lt 1 || "$pick" -gt ${#versions[@]} ]]; then
        colorEcho $RED "选择错误，请重新运行脚本。"
        exit 1
    fi

    vers=${versions[$pick-1]}
    if [[ "$vers" == "v3" ]]; then
        VER="v3.0.1"
        CONFIG_VER="v3"
    elif [[ "$vers" == "v5" ]]; then
        VER="v5.0.1"
        CONFIG_VER="v5"
    fi

}

set_paths() {
    snell_conf="/etc/snell/snell-${CONFIG_VER}.conf"
    snell_bin="/etc/snell/snell-${CONFIG_VER}"
    service_file="/etc/systemd/system/snell-${CONFIG_VER}.service"
}

Set_port() {
    read -p "请输入 Snell 端口 [1-65535] (默认 6666): " PORT
    [[ -z "$PORT" ]] && PORT="6666"
    if ! [[ "$PORT" =~ ^[0-9]+$ ]] || [[ "$PORT" -lt 1 ]] || [[ "$PORT" -gt 65535 ]]; then
        colorEcho $RED "端口无效，请输入 1-65535 的数字"
        Set_port
    fi
}

Set_psk() {
    read -p "请输入 PSK 密钥 (默认随机生成): " PSK
    [[ -z "$PSK" ]] && PSK=`tr -dc A-Za-z0-9 </dev/urandom | head -c 31`
}

Set_obfs() {
    if [[ "$CONFIG_VER" == "v3" ]]; then
        OBFS="none"
    else
        OBFS="off"
    fi
}


Write_config() {
    mkdir -p /etc/snell
    cat > ${snell_conf} <<EOF
[snell-server]
listen = 0.0.0.0:${PORT}
psk = ${PSK}
ipv6 = false
obfs = ${OBFS}
tfo = true
# ${vers}
EOF
}

Download_snell() {
    mkdir -p /tmp/snell
    archAffix
    DOWNLOAD_LINK="https://github.com/BeliefJourney/Snell/releases/download/${VER}/snell-server-${VER}-linux-${CPU}.zip"
    colorEcho $YELLOW "下载 Snell ${VER}..."
    curl -L -o /tmp/snell/snell.zip ${DOWNLOAD_LINK}
    unzip /tmp/snell/snell.zip -d /tmp/snell/
    mv /tmp/snell/snell-server ${snell_bin}
    chmod +x ${snell_bin}
}

Deploy_snell() {
    cat > ${service_file} <<EOF
[Unit]
Description=Snell Server ${CONFIG_VER}
After=network.target

[Service]
ExecStart=${snell_bin} -c ${snell_conf}
Restart=on-failure
RestartSec=1s

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reexec
    systemctl daemon-reload
    systemctl enable snell-${CONFIG_VER}
    systemctl restart snell-${CONFIG_VER}
}

ShowInfo() {
    IP=${IP4}
    echo ""
    echo -e "${BLUE}Snell ${vers} 安装成功！配置如下：${PLAIN}"
    echo -e "${GREEN}配置文件: ${PLAIN} ${snell_conf}"
    echo -e "${GREEN}运行端口: ${PLAIN} ${PORT}"
    echo -e "${GREEN}PSK密钥 : ${PLAIN} ${PSK}"
    echo -e "${GREEN}混淆类型: ${PLAIN} ${OBFS}"
    echo -e "${GREEN}服务名称: ${PLAIN} snell-${CONFIG_VER}.service"
    echo -e "${GREEN}本地IP  : ${PLAIN} ${IP}"
    echo ""
    echo -e "👉 启动命令: ${GREEN}systemctl start snell-${CONFIG_VER}${PLAIN}"
    echo -e "👉 停止命令: ${GREEN}systemctl stop snell-${CONFIG_VER}${PLAIN}"
    echo -e "👉 查看状态: ${GREEN}systemctl status snell-${CONFIG_VER}${PLAIN}"
}

main() {
    checkSystem
    Install_dependency
    selectversion
    set_paths
    Set_port
    Set_psk
    Set_obfs
    Write_config
    Download_snell
    Deploy_snell
    ShowInfo
}

main

