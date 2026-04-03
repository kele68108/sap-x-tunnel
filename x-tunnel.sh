#!/bin/bash

# =========================================================
# X-Tunnel 管理脚本 (Linux)
# =========================================================

# --- 全局变量 ---
# 注意：这里默认保留了你脚本里的下载链接，如果需要换成你最新的 sap-x-tunnel 链接请自行替换
GITHUB_BIN_URL="https://github.com/kele68108/sap-x-tunnel/raw/refs/heads/main/x-tunnel-linux-amd64"
BIN_PATH="/usr/local/bin/x-tunnel"
CONF_BASE_DIR="/etc/x-tunnel"
SHORTCUT_CMD="/usr/local/bin/x" # 升级：符合 Linux 规范，并改为全局命令 x

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
SKYBLUE='\033[0;36m'
PLAIN='\033[0m'

# --- 基础工具函数 ---
check_root() {
    if [ "$EUID" -ne 0 ]; then
        echo -e "${RED}错误: 请使用 root 用户运行此脚本！${PLAIN}"
        exit 1
    fi
}

install_dependencies() {
    if ! command -v wget &> /dev/null; then
        echo -e "${YELLOW}正在安装 wget...${PLAIN}"
        if [ -x "$(command -v apt)" ]; then
            apt update && apt install -y wget
        elif [ -x "$(command -v yum)" ]; then
            yum install -y wget
        fi
    fi
    mkdir -p "$CONF_BASE_DIR"
}

download_bin() {
    # 智能校验：不仅看大小，还尝试执行一下看是否报错
    if [ -f "$BIN_PATH" ]; then
        if ! "$BIN_PATH" -h > /dev/null 2>&1; then
            echo -e "${YELLOW}检测到二进制文件损坏或不可执行，准备重新下载...${PLAIN}"
            rm -f "$BIN_PATH"
        fi
    fi

    if [ ! -f "$BIN_PATH" ]; then
        echo -e "${YELLOW}正在下载核心二进制文件...${PLAIN}"
        wget --no-check-certificate -O "$BIN_PATH" "$GITHUB_BIN_URL"
        if [ $? -ne 0 ]; then
            echo -e "${RED}下载失败，请检查网络连接或 GitHub 地址！${PLAIN}"
            rm -f "$BIN_PATH"
            exit 1
        fi
        chmod +x "$BIN_PATH"
        echo -e "${GREEN}下载并赋权成功！${PLAIN}"
    fi
    
    if [ ! -f "$SHORTCUT_CMD" ]; then
        cat > "$SHORTCUT_CMD" <<EOF
#!/bin/bash
bash $(realpath "$0")
EOF
        chmod +x "$SHORTCUT_CMD"
        echo -e "${GREEN}全局快捷命令 'x' 已创建！以后在终端输入 x 即可唤出本菜单。${PLAIN}"
    fi
}

# --- 实例配置加载 ---
load_instance_config() {
    local name=$1
    INSTANCE_NAME="$name"
    CONF_FILE="${CONF_BASE_DIR}/${INSTANCE_NAME}.conf"
    SERVICE_NAME="ech-tunnel-${INSTANCE_NAME}"

    CFG_IP="104.16.1.1" # 默认 Cloudflare 优选 IP
    CFG_SERVER=""
    CFG_LISTEN="proxy://0.0.0.0:30003"
    CFG_TOKEN=""

    if [ -f "$CONF_FILE" ]; then
        source "$CONF_FILE"
    fi
}

save_config() {
    cat > "$CONF_FILE" <<EOF
CFG_IP="${CFG_IP}"
CFG_SERVER="${CFG_SERVER}"
CFG_LISTEN="${CFG_LISTEN}"
CFG_TOKEN="${CFG_TOKEN}"
EOF
}

# --- 服务管理函数 ---
create_service() {
    echo -e "${YELLOW}正在配置 Systemd 服务...${PLAIN}"
    CMD_ARGS="-l ${CFG_LISTEN} -f ${CFG_SERVER} -ip ${CFG_IP}"
    if [ ! -z "$CFG_TOKEN" ]; then
        CMD_ARGS="${CMD_ARGS} -token ${CFG_TOKEN}"
    fi
    CMD_ARGS="${CMD_ARGS} -n 4" # 默认开启 4 个多路复用长连接

    cat > "/etc/systemd/system/${SERVICE_NAME}.service" <<EOF
[Unit]
Description=ECH Tunnel Client - Instance: ${INSTANCE_NAME}
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=${BIN_PATH} ${CMD_ARGS}
Restart=always
RestartSec=5
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    systemctl enable "${SERVICE_NAME}" >/dev/null 2>&1
}

start_service() {
    if [ -z "$CFG_SERVER" ]; then
        echo -e "${RED}错误：服务端地址未设置！${PLAIN}"
        read -p "按回车键继续..."
        return
    fi

    # 智能补全协议头
    FIXED=0
    if [[ "$CFG_SERVER" != wss://* ]]; then
        CFG_SERVER="wss://${CFG_SERVER}"
        FIXED=1
    fi
    if [[ "$CFG_LISTEN" != proxy://* && "$CFG_LISTEN" != tcp://* ]]; then
        if [[ "$CFG_LISTEN" =~ ^[0-9]+$ ]]; then
            CFG_LISTEN="proxy://0.0.0.0:${CFG_LISTEN}"
        else
            CFG_LISTEN="proxy://${CFG_LISTEN}"
        fi
        FIXED=1
    fi
    if [ $FIXED -eq 1 ]; then
        save_config
    fi

    download_bin
    create_service 
    
    echo -e "${YELLOW}正在启动 [${INSTANCE_NAME}] ...${PLAIN}"
    systemctl restart "${SERVICE_NAME}"
    sleep 1.5
    
    if systemctl is-active --quiet "${SERVICE_NAME}"; then
        echo -e "${GREEN}启动成功！${PLAIN}"
    else
        echo -e "${RED}启动失败！日志如下：${PLAIN}"
        journalctl -u "${SERVICE_NAME}" -n 10 --no-pager
    fi
    read -p "按回车键继续..."
}

stop_service() {
    systemctl stop "${SERVICE_NAME}"
    systemctl disable "${SERVICE_NAME}" >/dev/null 2>&1
    echo -e "${YELLOW}实例 [${INSTANCE_NAME}] 已停止。${PLAIN}"
    read -p "按回车键继续..."
}

uninstall_service() {
    echo -e "${RED}警告：将删除实例 [${INSTANCE_NAME}] 的所有配置和服务。${PLAIN}"
    read -p "确认？[y/n]: " choice
    if [[ "$choice" == "y" || "$choice" == "Y" ]]; then
        systemctl stop "${SERVICE_NAME}" 2>/dev/null
        systemctl disable "${SERVICE_NAME}" 2>/dev/null
        rm -f "/etc/systemd/system/${SERVICE_NAME}.service"
        rm -f "$CONF_FILE"
        systemctl daemon-reload
        echo -e "${GREEN}已彻底删除。${PLAIN}"
        return 0 
    else
        echo -e "已取消。"
        return 1
    fi
}

# --- 三级页面：实例配置菜单 ---
instance_menu() {
    while true; do
        load_instance_config "$INSTANCE_NAME"
        clear
        echo -e "${SKYBLUE}====================================${PLAIN}"
        echo -e "${SKYBLUE}   配置实例: ${YELLOW}${INSTANCE_NAME}${PLAIN}"
        echo -e "${SKYBLUE}====================================${PLAIN}"
        
        echo -e "当前配置："
        echo -e " 1. 优选 IP/域名 : ${GREEN}${CFG_IP}${PLAIN}"
        echo -e " 2. 服务端地址   : ${GREEN}${CFG_SERVER:-[未设置]}${PLAIN}"
        echo -e " 3. 本地监听地址 : ${GREEN}${CFG_LISTEN}${PLAIN}"
        echo -e " 4. Token (可选) : ${GREEN}${CFG_TOKEN:-[未设置]}${PLAIN}"
        echo -e "------------------------------------"
        
        if systemctl is-active --quiet "${SERVICE_NAME}"; then
            # 升级：使用 systemctl 直接获取精准 PID，避免 pgrep 误杀误报
            MAIN_PID=$(systemctl show --property MainPID --value "${SERVICE_NAME}")
            echo -e " 运行状态: ${GREEN}运行中 (PID: ${MAIN_PID})${PLAIN}"
        else
            echo -e " 运行状态: ${RED}未运行${PLAIN}"
        fi
        echo -e "------------------------------------"
        echo -e " 5. ${YELLOW}启动 / 重启服务${PLAIN}"
        echo -e " 6. 停止服务"
        echo -e " 7. 查看实时日志"
        echo -e " 8. 卸载当前实例"
        echo -e " 0. 返回主菜单"
        echo ""
        read -p "请选择 [0-8]: " choice
        
        case "$choice" in
            1) read -p "请输入优选IP: " i; [ ! -z "$i" ] && CFG_IP="$i" && save_config ;;
            2) 
                read -p "服务端地址(如 abc.cloudflare.com): " i
                if [ ! -z "$i" ]; then
                    i=${i#wss://}
                    CFG_SERVER="wss://${i}"
                    save_config
                fi
                ;;
            3) 
                echo -e "输入端口(如 1080) 或 IP:端口"
                read -p "监听地址: " i
                if [ ! -z "$i" ]; then
                    i=${i#proxy://}
                    if [[ "$i" =~ ^[0-9]+$ ]]; then
                        CFG_LISTEN="proxy://0.0.0.0:${i}"
                    else
                        CFG_LISTEN="proxy://${i}"
                    fi
                    save_config
                fi
                ;;
            4) read -p "Token: " i; CFG_TOKEN="$i"; save_config ;;
            5) start_service ;;
            6) stop_service ;;
            7) echo -e "${YELLOW}Ctrl+C 退出日志${PLAIN}"; journalctl -u "${SERVICE_NAME}" -f ;;
            8) 
                uninstall_service
                if [ $? -eq 0 ]; then return; fi 
                ;;
            0) return ;; 
            *) echo "无效输入"; sleep 1 ;;
        esac
    done
}

# --- 二级页面：查看/管理实例 ---
list_instances() {
    while true; do
        clear
        echo -e "${SKYBLUE}====================================${PLAIN}"
        echo -e "${SKYBLUE}       实例列表 (选择以管理)${PLAIN}"
        echo -e "${SKYBLUE}====================================${PLAIN}"
        
        # 兼容处理：如果没有配置文件，files 数组会包含一个带 * 的无效字符串
        shopt -s nullglob
        files=(${CONF_BASE_DIR}/*.conf)
        shopt -u nullglob
        
        count=0
        if [ ${#files[@]} -eq 0 ]; then
            echo -e "${YELLOW}当前没有任何实例，请先新建。${PLAIN}"
            echo ""
            read -p "按回车返回..." 
            return
        fi

        for conf in "${files[@]}"; do
            count=$((count+1))
            filename=$(basename -- "$conf")
            name="${filename%.*}"
            if systemctl is-active --quiet "ech-tunnel-${name}"; then
                status="${GREEN}[运行中]${PLAIN}"
            else
                status="${RED}[已停止]${PLAIN}"
            fi
            echo -e " ${GREEN}${count}.${PLAIN} ${name} \t${status}"
        done
        
        echo ""
        echo -e " 0. 返回主菜单"
        echo ""
        read -p "请输入序号选择实例: " idx
        
        if [ "$idx" == "0" ]; then
            return
        elif [[ "$idx" =~ ^[0-9]+$ ]] && [ "$idx" -le "$count" ] && [ "$idx" -gt 0 ]; then
            real_index=$((idx-1))
            selected_conf="${files[$real_index]}"
            filename=$(basename -- "$selected_conf")
            selected_name="${filename%.*}"
            
            INSTANCE_NAME="$selected_name"
            load_instance_config "$INSTANCE_NAME"
            instance_menu
        else
            echo -e "${RED}无效序号${PLAIN}"
            sleep 1
        fi
    done
}

# --- 批量操作菜单 ---
batch_operation() {
    clear
    echo -e "${SKYBLUE}====================================${PLAIN}"
    echo -e "${SKYBLUE}         批量管理所有实例${PLAIN}"
    echo -e "${SKYBLUE}====================================${PLAIN}"
    echo -e " 1. 启动/重启 所有实例"
    echo -e " 2. 停止 所有实例"
    echo -e " 0. 返回"
    echo ""
    read -p "请选择: " batch_choice

    if [ "$batch_choice" == "0" ]; then return; fi

    if [[ "$batch_choice" != "1" && "$batch_choice" != "2" ]]; then
        echo -e "${RED}无效输入${PLAIN}"
        sleep 1
        return
    fi
    
    shopt -s nullglob
    files=(${CONF_BASE_DIR}/*.conf)
    shopt -u nullglob

    if [ ${#files[@]} -eq 0 ]; then
        echo -e "${YELLOW}没有实例可操作。${PLAIN}"
        sleep 1
        return
    fi

    for conf in "${files[@]}"; do
        filename=$(basename -- "$conf")
        name="${filename%.*}"
        svc="ech-tunnel-${name}"
        
        if [ "$batch_choice" == "1" ]; then
            echo -e "正在启动 ${name} ..."
            systemctl restart "$svc"
        elif [ "$batch_choice" == "2" ]; then
            echo -e "正在停止 ${name} ..."
            systemctl stop "$svc"
        fi
    done
    echo -e "${GREEN}批量操作完成。${PLAIN}"
    read -p "按回车继续..."
}

# --- 一级主菜单 ---
main_menu() {
    while true; do
        clear
        echo -e "${SKYBLUE}====================================${PLAIN}"
        echo -e "${SKYBLUE}    X-Tunnel 管理脚本 (Linux)${PLAIN}"
        echo -e "${SKYBLUE}====================================${PLAIN}"
        echo -e " 1. 查看 / 管理实例"
        echo -e " 2. 新建实例"
        echo -e " 3. 批量停止 / 启动"
        echo -e " ------------------------"
        echo -e " 0. 退出面板"
        echo ""
        read -p "请选择 [0-3]: " main_choice
        
        case "$main_choice" in
            1) list_instances ;;
            2) 
                read -p "请输入新实例名称 (仅限英文/数字，如 us1): " new_name
                if [ ! -z "$new_name" ]; then
                    INSTANCE_NAME="$new_name"
                    load_instance_config "$INSTANCE_NAME"
                    if [ ! -f "$CONF_FILE" ]; then save_config; fi
                    instance_menu
                fi
                ;;
            3) batch_operation ;;
            0) exit 0 ;;
            *) echo "无效输入"; sleep 1 ;;
        esac
    done
}

# --- 脚本入口 ---
check_root
install_dependencies
download_bin 
main_menu
