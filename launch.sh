#!/usr/bin/env bash
# =============================================================================
# launch.sh — USB Harness 启动器（Linux/macOS）
# 职责：环境校验 → 首启自动安装 → 交互菜单（启动/检查更新/配置/重置/状态/退出）
# 用法：bash launch.sh [web|setup|reset|status|check-update|upgrade]
# =============================================================================
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ACTION="${1:-}"

# 平台/架构
case "$(uname -s)" in
  Linux)  OS="linux" ;;
  Darwin) OS="darwin" ;;
  *)      echo "不支持的平台: $(uname -s)" >&2; exit 1 ;;
esac
case "$(uname -m)" in
  x86_64|amd64) ARCH="x64" ;;
  aarch64|arm64) ARCH="arm64" ;;
  *)            echo "不支持的架构: $(uname -m)" >&2; exit 1 ;;
esac
PLATFORM="${OS}-${ARCH}"

NODE_DIR="$ROOT/.cache/runtimes/${PLATFORM}/node"
NODE_BIN="$NODE_DIR/bin/node"
DSH_BIN="$ROOT/.cache/app/node_modules/.bin/dsh"
DSH_HOME_DIR="$ROOT/data/dsh"
LOG_DIR="$ROOT/data/logs"
LOG_FILE="$LOG_DIR/dsh-web.log"
UPGRADE_SCRIPT="$ROOT/scripts/upgrade-unix.sh"

mkdir -p "$DSH_HOME_DIR" "$LOG_DIR"

echo ""
echo "============================================"
echo "   USB Harness — 便携式 AI 助手"
echo "============================================"

# 环境就绪校验
ready() { [ -x "$NODE_BIN" ] && [ -x "$DSH_BIN" ]; }

do_setup() {
  bash "$ROOT/scripts/setup-unix.sh"
}

# 显示状态
show_status() {
  echo ""
  echo "--------------------------------------------"
  echo "  USB Harness 状态"
  echo "--------------------------------------------"
  if ready; then
    echo "  便携 Node : $("$NODE_BIN" -v)"
    echo "  dsh 版本  : $("$DSH_BIN" --version 2>/dev/null || echo '未知')"
    HARNESS_VER=""
    if [ -f "$ROOT/.ready.flag" ]; then
      HARNESS_VER="$(sed -n 's/^harness=//p' "$ROOT/.ready.flag" | head -1 | tr -d '\r')"
    fi
    [ -z "$HARNESS_VER" ] && [ -f "$ROOT/HARNESS_VERSION" ] && HARNESS_VER="$(tr -d '\r\n' < "$ROOT/HARNESS_VERSION")"
    if [ -n "$HARNESS_VER" ]; then echo "  程序版本  : $HARNESS_VER"; else echo "  程序版本  : 未记录（旧版包）"; fi
    echo "  数据目录  : $DSH_HOME_DIR"
    echo "  监听地址  : http://0.0.0.0:3080（本机 + 局域网）"
  else
    echo "  环境      : 未安装（首次使用需联网下载）"
  fi
  echo "--------------------------------------------"
  echo ""
}

# 启动 Web 界面
start_web() {
  PORT="${PORT:-3080}"
  export DSH_HOME="$DSH_HOME_DIR"
  export PATH="$NODE_DIR/bin:$ROOT/.cache/app/node_modules/.bin:$PATH"
  echo ""
  echo "  本机访问:   http://127.0.0.1:$PORT"
  echo "  局域网访问: http://<本机IP>:$PORT"
  echo "  提示: 功能完整请用本机地址 127.0.0.1（局域网 IP 访问时部分功能受限）"
  echo "  正在启动服务，请稍候… 浏览器将在服务就绪后自动打开"
  echo "  按 Ctrl+C 停止服务"
  echo ""
  # USB Harness: dsh 自动打开的是 http://0.0.0.0:port（浏览器不可访问），
  # 故加 --no-open，由这里轮询端口就绪后再打开正确的 http://127.0.0.1:port。
  ( for i in $(seq 1 120); do
      if (echo > /dev/tcp/127.0.0.1/$PORT) 2>/dev/null; then
        command -v xdg-open >/dev/null 2>&1 && xdg-open "http://127.0.0.1:$PORT" >/dev/null 2>&1 || open "http://127.0.0.1:$PORT" >/dev/null 2>&1
        break
      fi
      sleep 0.5
    done ) &
  exec "$DSH_BIN" web --port "$PORT" --host 0.0.0.0 --no-open 2>&1 | tee -a "$LOG_FILE"
}

# 重置
do_reset() {
  bash "$ROOT/scripts/reset-unix.sh"
}

# 首启自动安装
if ! ready; then
  echo "[警告] 未检测到运行环境，首次使用需要联网下载便携 Node 与 dsh（约 3-8 分钟）。"
  read -r -p "是否现在安装？[Y/N] " ans
  if [[ "$ans" =~ ^[Yy] ]]; then
    do_setup
  else
    echo "已取消安装。"
    exit 0
  fi
fi

# 升级残留裁决（幂等，无网络）：上次升级中断时自动恢复环境
bash "$UPGRADE_SCRIPT" --reconcile-only || true

# 命令行动作直通
case "$ACTION" in
  web)    start_web; exit 0 ;;
  setup)  do_setup; exit 0 ;;
  reset)  do_reset; exit 0 ;;
  status) show_status; exit 0 ;;
  check-update) bash "$UPGRADE_SCRIPT" --check-only; exit $? ;;
  upgrade)      bash "$UPGRADE_SCRIPT"; exit $? ;;
esac

# 交互菜单
while true; do
  show_status
  echo "  [1] 启动 Web 界面"
  echo "  [2] 检查更新（程序与 dsh 版本）"
  echo "  [3] 重置（清配置数据，保留运行环境，无需下载）"
  echo "  [4] 退出"
  echo ""
  read -r -p "  请选择 " choice
  case "$choice" in
    1) start_web ;;
    2) bash "$UPGRADE_SCRIPT" --check-only || true ;;
    3) do_reset ;;
    4) exit 0 ;;
    *) echo "[警告] 无效选择：$choice" ;;
  esac
done
