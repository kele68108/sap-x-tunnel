#!/usr/bin/env bash
set -e

# =========================================================
# SAP BAS / 本地沙盒 纯 Bash 隧道启动脚本 (后台不死版)
# =========================================================

# 1. 变量直填区 (在这里直接写死你的配置)
PORT="8080"
X_TOKEN="kele666"
ARGO_TOKEN="eyJhIjoiNTA0NmI1ODdjNmU0YmRhN2FlNTM2ZGZjZGVjM2M1NDkiLCJ0IjoiNTUyMGMwOGUtZDBhNS00ZjUxLTkxYjUtODg0NGE3NzYxN2I0IiwicyI6IllqQXhNR00wTnpJdFl6WXdZUzAwTkdKaUxUZ3lNREF0T0RSaE1UY3pNVFF6WXpOayJ9"   

# 内部端口，不用改
INTERNAL_PORT=8880

if [ -z "$ARGO_TOKEN" ] || [ "$ARGO_TOKEN" == "这里填入你的Cloudflare_Tunnel_Token" ]; then
    echo "[SYSTEM] 严重错误：请先在脚本代码中填入真实的 ARGO_TOKEN！"
    exit 1
fi

# 2. 启动极简 HTTP 服务，占用 $PORT 端口
# 【修改点 1】：加上 nohup，并且屏蔽所有输出，让它彻底沉入后台
echo "[SYSTEM] 启动 HTTP 健康检查探针，监听端口: $PORT"
nohup python3 -c "
import http.server, socketserver
class Handler(http.server.BaseHTTPRequestHandler):
    def log_message(self, format, *args):
        pass
    def do_GET(self):
        self.send_response(200)
        self.end_headers()
        self.wfile.write(b'BAS Tunnel Service is running.')
try:
    socketserver.TCPServer(('', $PORT), Handler).serve_forever()
except Exception as e:
    pass
" >/dev/null 2>&1 &

# 3. 生成随机字符串用于临时文件名
WORK_DIR="/tmp"
XT_NAME=$(cat /dev/urandom | tr -dc 'a-z0-9' | head -c 8)
CF_NAME=$(cat /dev/urandom | tr -dc 'a-z0-9' | head -c 8)
XT_PATH="${WORK_DIR}/${XT_NAME}"
CF_PATH="${WORK_DIR}/${CF_NAME}"

XT_URL="https://github.com/kele68108/sap-x-tunnel/raw/refs/heads/main/x-tunnel-linux-amd64"
CF_URL="https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64"

# 4. 下载核心组件并赋权
echo "[SYSTEM] 正在下载核心组件..."
curl -sL -o "$XT_PATH" "$XT_URL"
curl -sL -o "$CF_PATH" "$CF_URL"

echo "[SYSTEM] 赋予执行权限..."
chmod 755 "$XT_PATH" "$CF_PATH"

# 5. 启动核心进程 (转入后台运行)
# 【修改点 2】：加上 nohup，防止 SIGHUP 信号
echo "[SYSTEM] 启动 X-Tunnel，监听本地端口: $INTERNAL_PORT"
nohup "$XT_PATH" -l "ws://127.0.0.1:${INTERNAL_PORT}" -token "$X_TOKEN" >/dev/null 2>&1 &

echo "[SYSTEM] 启动 Cloudflare Argo Tunnel..."
nohup "$CF_PATH" tunnel --edge-ip-version auto run --token "$ARGO_TOKEN" >/dev/null 2>&1 &

# 6. 阅后即焚魔法
# 【修改点 3】：让清理脚本也完全静默，避免 90 秒后在终端突然冒出一行字打断你敲代码
(
    sleep 90  
    rm -f "$XT_PATH" "$CF_PATH"
) >/dev/null 2>&1 &

# 【修改点 4】：删除了 trap 清理逻辑
# 【修改点 5】：删除了 wait 挂起逻辑

# 7. 事了拂衣去
echo "[SYSTEM] ========================================"
echo "[SYSTEM] 所有服务已成功剥离并潜入后台运行！"
echo "[SYSTEM] 脚本即将退出，您可以放心按下 Ctrl+C 或关闭终端了。"
echo "[SYSTEM] ========================================"
exit 0
