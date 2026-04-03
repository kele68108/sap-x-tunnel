#!/usr/bin/env bash
set -e

# =========================================================
# SAP BAS / 本地沙盒 纯 Bash 隧道启动脚本 (变量直填版)
# =========================================================

# 1. 变量直填区 (在这里直接写死你的配置)
PORT="8080"
X_TOKEN="kele666"
ARGO_TOKEN="eyJhIjoiNTA0NmI1ODdjNmU0YmRhN2FlNTM2ZGZjZGVjM2M1NDkiLCJ0IjoiNTUyMGMwOGUtZDBhNS00ZjUxLTkxYjUtODg0NGE3NzYxN2I0IiwicyI6IllqQXhNR00wTnpJdFl6WXdZUzAwTkdKaUxUZ3lNREF0T0RSaE1UY3pNVFF6WXpOayJ9"   # <--- 请在这里填入你真实的 Token

# 内部端口，不用改
INTERNAL_PORT=8080

if [ -z "$ARGO_TOKEN" ] || [ "$ARGO_TOKEN" == "这里填入你的Cloudflare_Tunnel_Token" ]; then
    echo "[SYSTEM] 严重错误：请先在脚本代码中填入真实的 ARGO_TOKEN！"
    exit 1
fi

# 2. 启动极简 HTTP 服务，占用 $PORT 端口 (防止报错或探测)
echo "[SYSTEM] 启动 HTTP 健康检查探针，监听端口: $PORT"
python3 -c "
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
    print(e)
" &
HTTP_PID=$!

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
echo "[SYSTEM] 启动 X-Tunnel，监听本地端口: $INTERNAL_PORT"
"$XT_PATH" -l "ws://127.0.0.1:${INTERNAL_PORT}" -token "$X_TOKEN" >/dev/null 2>&1 &
XT_PID=$!

echo "[SYSTEM] 启动 Cloudflare Argo Tunnel..."
"$CF_PATH" tunnel --edge-ip-version auto run --token "$ARGO_TOKEN" >/dev/null 2>&1 &
CF_PID=$!

# 6. 阅后即焚魔法
(
    sleep 90  # BAS里测试可以缩短一点时间，比如30秒后就删
    echo "[SYSTEM] 触发阅后即焚，清理硬盘物理文件..."
    rm -f "$XT_PATH" "$CF_PATH"
    echo "[SYSTEM] 痕迹清理完毕，组件全内存运行中！"
) &

# 7. 优雅退出处理
cleanup() {
    echo ""
    echo "[SYSTEM] 收到终止信号，准备清理退出..."
    kill $XT_PID $CF_PID $HTTP_PID 2>/dev/null || true
    echo "[SYSTEM] 进程已全部终止。"
    exit 0
}
trap cleanup SIGTERM SIGINT

# 8. 挂起主进程
echo "[SYSTEM] 所有服务均已在后台启动，按 Ctrl+C 可一键安全退出并清理。"
wait $HTTP_PID $XT_PID $CF_PID
