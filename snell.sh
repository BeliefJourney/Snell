#!/bin/bash
# Enhanced Snell Installer Script - 支持多版本并存、状态查看、删除指定实例
# 作者: BeliefJourney + Linux Server Expert

RED="\033[31m"
GREEN="\033[32m"
YELLOW="\033[33m"
BLUE="\033[36m"
PLAIN='\033[0m'

snell_dir="/etc/snell"
IP4=$(curl -s4 --max-time 3 ip.sb || true)
IP6=$(curl -s6 --max-time 3 ip.sb || true)
CPU=$(uname -m)

SELF_URL_RAW="https://raw.githubusercontent.com/BeliefJourney/Snell/main/snell.sh"
INSTALL_PATH="/root/snell.sh"
LINK_PATH="/usr/local/bin/snell"
SCRIPT_PATH=$(readlink -f "$0" 2>/dev/null || echo "$0")

colorEcho() {
    echo -e "${1}${@:2}${PLAIN}"
}

ensure_link() {
    [[ $EUID -ne 0 ]] && return
    local target="$INSTALL_PATH"
    if [[ ! -f "$target" && -f "$SCRIPT_PATH" ]]; then
        target="$SCRIPT_PATH"
    fi
    mkdir -p "$(dirname "$LINK_PATH")"
    ln -sf "$target" "$LINK_PATH"
}

ensure_installed() {
    if [[ "$1" == "--install" ]] || [[ "$0" == "bash" || "$0" == "sh" || "${BASH_SOURCE[0]}" == "bash" || "${BASH_SOURCE[0]}" == "sh" ]]; then
        [[ $EUID -ne 0 ]] && echo -e "${RED}请使用 root 用户运行脚本${PLAIN}" && exit 1
        mkdir -p "$(dirname "$INSTALL_PATH")"
        if ! curl -fsSL "$SELF_URL_RAW" -o "$INSTALL_PATH"; then
            echo -e "${RED}❌ 下载失败：$SELF_URL_RAW${PLAIN}"
            exit 1
        fi
        chmod +x "$INSTALL_PATH"
        ensure_link
        exec "$INSTALL_PATH"
    fi
}

archAffix(){
    if [[ "$CPU" == "x86_64" || "$CPU" == "amd64" ]]; then
        CPU="amd64"
    elif [[ "$CPU" == "aarch64" || "$CPU" == "arm64" ]]; then
        CPU="arm64"
    else
        colorEcho $RED "不支持的CPU架构: $CPU"
        exit 1
    fi
}

format_host() {
    local ip="$1"
    if [[ "$ip" == *:* ]]; then
        echo "[${ip}]"
    else
        echo "${ip}"
    fi
}

statusText() {
    echo -e "\n${BLUE}当前状态：${PLAIN}"
    for svc in /etc/systemd/system/snell-*.service; do
        [[ -e "$svc" ]] || continue
        name=$(basename "$svc" .service)
        config="/etc/snell/${name}.conf"
        port="未知"
        [[ -f "$config" ]] && port=$(grep -E '^\s*listen' "$config" | awk -F ':' '{print $NF}' | xargs)
        if systemctl is-active --quiet "$name"; then
            echo -e " - ${GREEN}${name}${PLAIN}     ✅ 运行中（端口: ${port}）"
        else
            echo -e " - ${YELLOW}${name}${PLAIN}     ❌ 未运行"
        fi
    done
}

delete_snell() {
    echo -e "\n${BLUE}请选择要删除的 Snell 实例：${PLAIN}"
    local services=()
    local count=0
    for svc in /etc/systemd/system/snell-*.service; do
        [[ -e "$svc" ]] || continue
        name=$(basename "$svc" .service)
        count=$((count+1))
        services+=("$name")
        echo -e " ${GREEN}${count})${PLAIN} ${name}"
    done
    if [[ $count -eq 0 ]]; then
        echo -e "${YELLOW}未找到可删除的 Snell 实例${PLAIN}"
        return
    fi
    echo -e " ${GREEN}0)${PLAIN} 取消"
    read -p $'\n请输入编号: ' pick
    [[ "$pick" == "0" || -z "$pick" ]] && echo -e "${YELLOW}已取消${PLAIN}" && return
    selected=${services[$((pick-1))]}
    [[ -z "$selected" ]] && { echo -e "${RED}编号无效${PLAIN}"; return; }
    read -p "⚠️ 确认删除 ${selected}？[y/N]: " confirm
    if [[ "$confirm" == "y" || "$confirm" == "Y" ]]; then
        systemctl stop "$selected"
        systemctl disable "$selected"
        rm -f "/etc/systemd/system/${selected}.service"
        rm -f "/etc/snell/${selected}.conf"
        rm -f "/etc/snell/${selected}"
        rm -f "/etc/snell/${selected}.txt"
        systemctl daemon-reload
        echo -e "${GREEN}✅ 已删除 ${selected}${PLAIN}"
    else
        echo -e "${YELLOW}已取消${PLAIN}"
    fi
}

Install_snell() {
    echo -e "\n请选择 Snell 版本："
    echo -e "${GREEN}1)${PLAIN} v3"
    echo -e "${GREEN}2)${PLAIN} v5"
    read -p "请选择版本[1-2] (默认: 2): " ver_pick
    [[ -z "$ver_pick" || "$ver_pick" == "2" ]] && SNELL_VER="v5.0.1" && SNELL_TAG="v5"
    [[ "$ver_pick" == "1" ]] && SNELL_VER="v3.0.1" && SNELL_TAG="v3"

    read -p $'\n请输入用户ID（英文+数字）：' USER_ID
    [[ ! "$USER_ID" =~ ^[a-zA-Z0-9_-]+$ ]] && { echo -e "${RED}❌ 无效用户ID${PLAIN}"; return; }

    read -p "请输入 Snell 端口 [1-65535] (默认: 6666): " SNELL_PORT
    [[ -z "$SNELL_PORT" ]] && SNELL_PORT=6666

    read -p "请输入 PSK 密钥 (默认随机生成): " SNELL_PSK
    [[ -z "$SNELL_PSK" ]] && SNELL_PSK=$(tr -dc A-Za-z0-9 </dev/urandom | head -c 31)

    mkdir -p /etc/snell
    archAffix
    BIN_NAME="/etc/snell/snell-${SNELL_TAG}"
    CONF_FILE="/etc/snell/snell-${SNELL_TAG}-${USER_ID}.conf"
    SERVICE_NAME="snell-${SNELL_TAG}-${USER_ID}"
    SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"

    if [[ ! -f "$BIN_NAME" ]]; then
        echo -e "${YELLOW}下载 Snell ${SNELL_VER}...${PLAIN}"
        mkdir -p /tmp/snell
        curl -L -o /tmp/snell/snell.zip "https://raw.githubusercontent.com/BeliefJourney/Snell/main/snell-server-${SNELL_VER}-linux-${CPU}.zip"
        unzip -o /tmp/snell/snell.zip -d /tmp/snell/ || {
            echo -e "${RED}❌ 解压失败${PLAIN}"
            return
        }
        mv /tmp/snell/snell-server "$BIN_NAME"
        chmod +x "$BIN_NAME"
    fi

    OBFS_MODE=$([[ "$SNELL_TAG" == "v3" ]] && echo "none" || echo "off")

    if [[ -n "$IP6" ]]; then
        LISTEN_ADDR="[::]:${SNELL_PORT}"
        IPV6_FLAG=true
        SERVER_IP="$IP6"
    else
        LISTEN_ADDR="0.0.0.0:${SNELL_PORT}"
        IPV6_FLAG=false
        SERVER_IP="$IP4"
    fi

    cat > "$CONF_FILE" <<EOF
[snell-server]
listen = ${LISTEN_ADDR}
psk = ${SNELL_PSK}
ipv6 = ${IPV6_FLAG}
obfs = ${OBFS_MODE}
tfo = false
# ${SNELL_TAG}-${USER_ID}
EOF

    cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=Snell ${SNELL_TAG} Server for ${USER_ID}
After=network.target

[Service]
ExecStart=${BIN_NAME} -c ${CONF_FILE}
Restart=on-failure
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable "$SERVICE_NAME"
    systemctl restart "$SERVICE_NAME"

    OUT_FILE="/etc/snell/snell-${SNELL_TAG}-${USER_ID}.txt"
    echo -e "[Proxy]" > "$OUT_FILE"

    HOST_FOR_CLIENT=$(format_host "$SERVER_IP")

    if [[ "$SNELL_TAG" == "v3" ]]; then
        SURGE="snell-${USER_ID} = snell, ${HOST_FOR_CLIENT}, ${SNELL_PORT}, psk=${SNELL_PSK}, obfs=none"
        CLASH="- name: snell-${USER_ID}
  type: snell
  server: ${SERVER_IP}
  port: ${SNELL_PORT}
  psk: \"${SNELL_PSK}\"
  obfs-opts:
    mode: none"
        echo "$SURGE" | tee -a "$OUT_FILE"
        echo -e "\n${GREEN}📄 Clash 配置：${PLAIN}\n$CLASH" | tee -a "$OUT_FILE"
    else
        SURGE="snell-${USER_ID} = snell, ${HOST_FOR_CLIENT}, ${SNELL_PORT}, psk=${SNELL_PSK}, version=5, tfo=false"
        echo "$SURGE" | tee -a "$OUT_FILE"
    fi

    echo -e "\n${YELLOW}配置已保存：${OUT_FILE}${PLAIN}"
}

update_script() {
    echo -e "\n${BLUE}正在更新脚本...${PLAIN}"
    if ! curl -fsSL "$SELF_URL_RAW" -o "$INSTALL_PATH"; then
        echo -e "${RED}❌ 更新失败：$SELF_URL_RAW${PLAIN}"
        return
    fi
    chmod +x "$INSTALL_PATH"
    ensure_link
    echo -e "${GREEN}✅ 已更新：${INSTALL_PATH}${PLAIN}"
    if [[ "$SCRIPT_PATH" != "$INSTALL_PATH" ]]; then
        echo -e "${YELLOW}当前运行的不是 ${INSTALL_PATH}，建议使用 ${INSTALL_PATH} 运行${PLAIN}"
    fi
}

export_config() {
    echo -e "\n${BLUE}已存在的配置文件：${PLAIN}"
    configs=$(ls /etc/snell/snell-*.conf 2>/dev/null)
    if [[ -z "$configs" ]]; then
        echo -e "${YELLOW}未找到任何配置文件${PLAIN}"
        return
    fi

    for f in $configs; do
        base=$(basename "$f" .conf)
        echo " - $base"
    done

    read -p $'\n请输入要导出的配置ID（如 snell-v3-user123）: ' config_id
    CONF_FILE="/etc/snell/${config_id}.conf"
    [[ ! -f "$CONF_FILE" ]] && echo -e "${RED}配置文件不存在: ${config_id}${PLAIN}" && return

    TAG=$(echo "$config_id" | cut -d- -f2)
    USER_ID=$(echo "$config_id" | cut -d- -f3-)
    PORT=$(grep -E '^\s*listen' "$CONF_FILE" | awk -F ':' '{print $NF}' | xargs)
    PSK=$(grep psk "$CONF_FILE" | awk -F '=' '{print $2}' | xargs)
    IP4=$(curl -s4 --max-time 3 ip.sb || true)
    IP6=$(curl -s6 --max-time 3 ip.sb || true)

    if grep -qi '^\s*ipv6\s*=\s*true' "$CONF_FILE" || grep -q '^\s*listen\s*=\s*\[::\]' "$CONF_FILE"; then
        SERVER_IP="$IP6"
    else
        SERVER_IP="$IP4"
    fi
    [[ -z "$SERVER_IP" ]] && SERVER_IP="$IP4"

    HOST_FOR_CLIENT=$(format_host "$SERVER_IP")

    echo -e "\n${BLUE}请选择导出格式：${PLAIN}"
    echo -e " ${GREEN}1)${PLAIN} Surge"
    [[ "$TAG" == "v3" ]] && echo -e " ${GREEN}2)${PLAIN} Clash"
    read -p "请选择格式 (默认 1): " opt
    [[ -z "$opt" ]] && opt=1

    if [[ "$opt" == "1" ]]; then
        if [[ "$TAG" == "v3" ]]; then
            echo -e "\n${GREEN}📄 Surge 配置：${PLAIN}"
            echo "[Proxy]"
            echo "snell-${USER_ID} = snell, ${HOST_FOR_CLIENT}, ${PORT}, psk=${PSK}, obfs=none"
        else
            echo -e "\n${GREEN}📄 Surge 配置：${PLAIN}"
            echo "[Proxy]"
            echo "snell-${USER_ID} = snell, ${HOST_FOR_CLIENT}, ${PORT}, psk=${PSK}, version=5, tfo=false"
        fi
    elif [[ "$opt" == "2" && "$TAG" == "v3" ]]; then
        echo -e "\n${GREEN}📄 Clash 配置：${PLAIN}"
        echo "- name: snell-${USER_ID}"
        echo "  type: snell"
        echo "  server: ${SERVER_IP}"
        echo "  port: ${PORT}"
        echo "  psk: \"${PSK}\""
        echo "  obfs-opts:"
        echo "    mode: none"
    else
        echo -e "${RED}❌ 不支持的选项或版本${PLAIN}"
    fi
}

menu() {
    clear
    echo "################################"
    echo -e "#     ${GREEN}Snell 多版本安装脚本${PLAIN}      #"
    echo -e "#      Author: BeliefJourney     #"
    echo "################################"
    echo ""
    echo -e "  ${GREEN}1.${PLAIN} 安装 Snell"
    echo -e "  ${GREEN}2.${PLAIN} 删除指定 Snell 实例"
    echo -e "  ${GREEN}3.${PLAIN} 查看运行状态"
    echo -e "  ${GREEN}4.${PLAIN} 导出指定配置（Surge/Clash）"
    echo -e "  ${GREEN}5.${PLAIN} 更新脚本"
    echo -e "  ${GREEN}0.${PLAIN} 退出"
    echo ""
    statusText
    echo ""
    read -p "请选择操作 [0-5]: " sel
    case "$sel" in
        1) Install_snell ;;
        2) delete_snell ;;
        3) statusText; read -p "按回车返回菜单..." ;;
        4) export_config; read -p "按回车返回菜单..." ;;
        5) update_script; read -p "按回车返回菜单..." ;;
        0) exit 0 ;;
        *) colorEcho $RED "无效输入，请重新选择！"; sleep 1 ;;
    esac
    menu
}

ensure_installed "$1"

# 启动
[[ $EUID -ne 0 ]] && echo -e "${RED}请使用 root 用户运行脚本${PLAIN}" && exit 1
ensure_link
menu
