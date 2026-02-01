#!/bin/bash
# Enhanced Snell Installer Script - 支持多版本并存、状态查看、删除指定实例
# 作者: BeliefJourney + Linux Server Expert

RED="\033[31m"
GREEN="\033[32m"
YELLOW="\033[33m"
BLUE="\033[36m"
PLAIN='\033[0m'

snell_dir="/etc/snell"
IP4=$(curl -s4 ip.sb)
IP6=$(curl -s6 ip.sb)
CPU=$(uname -m)

colorEcho() {
    echo -e "${1}${@:2}${PLAIN}"
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

statusText() {
    echo ""
    echo -e "${BLUE}当前状态：${PLAIN}"
    for svc in /etc/systemd/system/snell-*.service; do
        [[ -e "$svc" ]] || continue
        name=$(basename "$svc" .service)
        config="/etc/snell/${name}.conf"
        if [[ -f "$config" ]]; then
            port=$(grep listen "$config" | awk -F ':' '{print $2}' | xargs)
        else
            port="未知"
        fi
        if systemctl is-active --quiet "$name"; then
            echo -e " - ${GREEN}${name}${PLAIN}     ✅ 运行中（端口: ${port}）"
        else
            echo -e " - ${YELLOW}${name}${PLAIN}     ❌ 未运行"
        fi
    done

    # ShadowTLS 状态
    stls_conf="/etc/systemd/system/shadowtls.service"
    if [[ -f "$stls_conf" ]]; then
        sport=$(grep listen "$stls_conf" | grep -oE '[0-9]{2,5}' | head -1)
        if systemctl is-active --quiet shadowtls; then
            echo -e " - ${GREEN}ShadowTLS${PLAIN}  ✅ 运行中（端口: ${sport}）"
        else
            echo -e " - ${YELLOW}ShadowTLS${PLAIN}  ❌ 未运行"
        fi
    else
        echo -e " - ${YELLOW}ShadowTLS${PLAIN}  ❌ 未安装"
    fi
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
    if [[ -z "$selected" ]]; then
        echo -e "${RED}编号无效${PLAIN}"
        return
    fi

    read -p "⚠️ 确认删除 ${selected}？[y/N]: " confirm
    if [[ "$confirm" == "y" || "$confirm" == "Y" ]]; then
        systemctl stop "$selected"
        systemctl disable "$selected"
        rm -f "/etc/systemd/system/${selected}.service"
        rm -f "/etc/snell/${selected}.conf"
        rm -f "/etc/snell/${selected}"
        systemctl daemon-reload
        echo -e "${GREEN}✅ 已删除 ${selected}${PLAIN}"
    else
        echo -e "${YELLOW}已取消${PLAIN}"
    fi
}
select_version() {
    echo -e "\n请选择 Snell 版本："
    echo -e "${GREEN}1)${PLAIN} v3"
    echo -e "${GREEN}2)${PLAIN} v5"
    read -p "请选择版本[1-2] (默认: 2): " ver_pick
    [[ -z "$ver_pick" ]] && ver_pick=2
    case "$ver_pick" in
        1) SNELL_VER="v3.0.1"; SNELL_TAG="v3";;
        2) SNELL_VER="v5.0.1"; SNELL_TAG="v5";;
        *) SNELL_VER="v5.0.1"; SNELL_TAG="v5";;
    esac
}

prepare_config() {
    echo -e "\n请输入 Snell 端口 [1-65535] (默认 6666):"
    read -p "> " SNELL_PORT
    [[ -z "$SNELL_PORT" ]] && SNELL_PORT=6666

    echo -e "请输入 PSK 密钥 (默认随机生成):"
    read -p "> " SNELL_PSK
    [[ -z "$SNELL_PSK" ]] && SNELL_PSK=$(tr -dc A-Za-z0-9 </dev/urandom | head -c 31)

    SNELL_NAME="snell-${SNELL_TAG}"
    SNELL_CONF="${snell_dir}/${SNELL_NAME}.conf"
    SNELL_BIN="${snell_dir}/${SNELL_NAME}"
    SERVICE_FILE="/etc/systemd/system/${SNELL_NAME}.service"
}

download_snell() {
    archAffix
    echo -e "\n下载 Snell ${SNELL_VER}..."
    mkdir -p /tmp/snell /etc/snell
    URL="https://raw.githubusercontent.com/BeliefJourney/Snell/main/snell-server-${SNELL_VER}-linux-${CPU}.zip"
    curl -L "$URL" -o /tmp/snell/snell.zip
    unzip -o /tmp/snell/snell.zip -d /tmp/snell/ || {
        echo -e "${RED}❌ 解压失败，请检查下载链接${PLAIN}"
        exit 1
    }
    mv /tmp/snell/snell-server "$SNELL_BIN"
    chmod +x "$SNELL_BIN"
}

write_config() {
    cat > "$SNELL_CONF" <<EOF
[snell-server]
listen = 0.0.0.0:${SNELL_PORT}
psk = ${SNELL_PSK}
ipv6 = false
obfs = off
tfo = false
# ${SNELL_TAG}
EOF
    echo -e "\n${GREEN}配置写入：${SNELL_CONF}${PLAIN}"
}

write_service() {
    cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=Snell Server ${SNELL_TAG}
After=network.target

[Service]
ExecStart=${SNELL_BIN} -c ${SNELL_CONF}
Restart=on-failure
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    systemctl enable "${SNELL_NAME}"
    systemctl restart "${SNELL_NAME}"
    echo -e "${GREEN}Snell ${SNELL_TAG} 已安装并启动${PLAIN}"
}

Install_snell() {
    # 1. 选择版本
    echo -e "\n请选择 Snell 版本："
    echo -e "${GREEN}1)${PLAIN} v3"
    echo -e "${GREEN}2)${PLAIN} v5"
    read -p "请选择版本[1-2] (默认: 2): " ver_pick
    [[ -z "$ver_pick" || "$ver_pick" == "2" ]] && SNELL_VER="v5.0.1" && SNELL_TAG="v5"
    [[ "$ver_pick" == "1" ]] && SNELL_VER="v3.0.1" && SNELL_TAG="v3"

    # 2. 用户ID
    read -p $'\n请输入用户ID（英文+数字）：' USER_ID
    if [[ ! "$USER_ID" =~ ^[a-zA-Z0-9_-]+$ ]]; then
        echo -e "${RED}无效用户ID，必须是英文+数字组合${PLAIN}"
        return
    fi

    # 3. 端口
    read -p "请输入 Snell 端口 [1-65535] (默认: 6666): " SNELL_PORT
    [[ -z "$SNELL_PORT" ]] && SNELL_PORT=6666

    # 4. PSK 密钥
    read -p "请输入 PSK 密钥 (默认随机生成): " SNELL_PSK
    [[ -z "$SNELL_PSK" ]] && SNELL_PSK=$(tr -dc A-Za-z0-9 </dev/urandom | head -c 31)

    # 5. 设置路径
    mkdir -p /etc/snell
    archAffix
    BIN_NAME="/etc/snell/snell-${SNELL_TAG}"
    CONF_FILE="/etc/snell/snell-${SNELL_TAG}-${USER_ID}.conf"
    SERVICE_NAME="snell-${SNELL_TAG}-${USER_ID}"
    SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"

    # 6. 下载 Snell 二进制（按版本）
    if [[ ! -f "$BIN_NAME" ]]; then
        echo -e "${YELLOW}下载 Snell ${SNELL_VER}...${PLAIN}"
        mkdir -p /tmp/snell
        curl -L -o /tmp/snell/snell.zip "https://raw.githubusercontent.com/BeliefJourney/Snell/main/snell-server-${SNELL_VER}-linux-${CPU}.zip"
        unzip -o /tmp/snell/snell.zip -d /tmp/snell/ || {
            echo -e "${RED}❌ 解压失败，请检查下载链接${PLAIN}"
            return
        }
        mv /tmp/snell/snell-server "$BIN_NAME"
        chmod +x "$BIN_NAME"
    fi

    # 7. 写配置文件
    cat > "$CONF_FILE" <<EOF
[snell-server]
listen = 0.0.0.0:${SNELL_PORT}
psk = ${SNELL_PSK}
ipv6 = false
obfs = ${SNELL_TAG == "v3" ? "none" : "off"}
tfo = false
# ${SNELL_TAG}-${USER_ID}
EOF

    # 8. 写 systemd 服务
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

    # 9. 启动服务
    systemctl daemon-reload
    systemctl enable "$SERVICE_NAME"
    systemctl restart "$SERVICE_NAME"

    # 10. 获取 IP
    IP4=$(curl -sL -4 ip.sb)

    # 11. 输出配置信息
    echo -e "\n${GREEN}✅ 安装完成！${PLAIN}"
    echo -e "${BLUE}用户ID：${PLAIN} ${USER_ID}"
    echo -e "${BLUE}版本：${PLAIN} ${SNELL_TAG}"
    echo -e "${BLUE}端口：${PLAIN} ${SNELL_PORT}"
    echo -e "${BLUE}PSK：${PLAIN} ${SNELL_PSK}"
    echo -e "${BLUE}服务名：${PLAIN} ${SERVICE_NAME}"

    # 12. 输出 Surge 配置
    echo -e "\n${GREEN}📄 Surge 配置：${PLAIN}"
    echo "[Proxy]" > /etc/snell/snell-${SNELL_TAG}-${USER_ID}.txt
    if [[ "$SNELL_TAG" == "v3" ]]; then
        SURGE_LINE="snell-${USER_ID} = snell, ${IP4}, ${SNELL_PORT}, psk=${SNELL_PSK}, obfs=none"
        CLASH_LINE="- name: snell-${USER_ID}
  type: snell
  server: ${IP4}
  port: ${SNELL_PORT}
  psk: \"${SNELL_PSK}\"
  obfs-opts:
    mode: none"
        echo "$SURGE_LINE"
        echo "$SURGE_LINE" >> /etc/snell/snell-${SNELL_TAG}-${USER_ID}.txt
        echo -e "\n${GREEN}📄 Clash 配置：${PLAIN}"
        echo "$CLASH_LINE"
        echo -e "\n$CLASH_LINE" >> /etc/snell/snell-${SNELL_TAG}-${USER_ID}.txt
    else
        SURGE_LINE="snell-${USER_ID} = snell, ${IP4}, ${SNELL_PORT}, psk=${SNELL_PSK}, version=5, tfo=false"
        echo "$SURGE_LINE"
        echo "$SURGE_LINE" >> /etc/snell/snell-${SNELL_TAG}-${USER_ID}.txt
    fi

    echo -e "\n${YELLOW}配置已保存至：/etc/snell/snell-${SNELL_TAG}-${USER_ID}.txt${PLAIN}"
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
    echo -e "  ${GREEN}0.${PLAIN} 退出"
    echo ""
    statusText
    echo ""
    read -p "请选择操作 [0-3]: " sel
    case "$sel" in
        1) Install_snell ;;
        2) delete_snell ;;
        3) statusText; read -p "按回车返回菜单..." ;;
        0) exit 0 ;;
        *) colorEcho $RED "无效输入，请重新选择！"; sleep 1 ;;
    esac
    menu
}

# 检查 root 权限
[[ $EUID -ne 0 ]] && echo -e "${RED}请使用 root 用户运行脚本${PLAIN}" && exit 1

# 运行主菜单
menu
