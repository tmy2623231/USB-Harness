#!/usr/bin/env bash
# =============================================================================
# launch.sh — USB Harness 启动器（Linux/macOS）
# 职责：环境校验 → 首启自动安装 → 交互菜单（启动/检查更新/重置/切换模式/退出）
# 用法：bash launch.sh [web|cli|setup|reset|status|check-update|upgrade]
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
# dsh 的 CLI 入口（bin.js）。优先用便携 node 绝对路径直调，摆脱 .bin 垫片
# （#!/usr/bin/env node）靠 PATH 找 node 的坑；垫片仅作 bin.js 缺失时的回退。
DSH_CLI="$ROOT/.cache/app/node_modules/@deepseek-ai/dsh/lib/bin.js"
DSH_BIN="$ROOT/.cache/app/node_modules/.bin/dsh"
DSH_HOME_DIR="$ROOT/data/dsh"
LOG_DIR="$ROOT/data/logs"
LOG_FILE="$LOG_DIR/dsh-web.log"
CLI_LOG_FILE="$LOG_DIR/dsh-cli.log"
CLI_ERR_FILE="$LOG_DIR/dsh-cli.err.log"
# 运行模式持久化位置（config/launch.conf，与 launch-windows.ps1 共用同一格式）
LAUNCH_CONF="$ROOT/config/launch.conf"

# 兜底：把便携 node 提到 PATH 最前（对 dsh 内部再派生的子进程同样生效）。
# 注意：这只是兜底——dsh 主进程的 node 解析已不再依赖 PATH（见 dsh()）。
export PATH="$NODE_DIR/bin:$PATH"
UPGRADE_SCRIPT="$ROOT/scripts/upgrade-unix.sh"

# 读取本包版本（程序版本）：优先 .ready.flag 的 harness= 行，缺失回退 HARNESS_VERSION
# 必须定义在横幅（下方 echo）之前
get_harness_ver() {
  local v=""
  if [ -f "$ROOT/.ready.flag" ]; then
    v="$(sed -n 's/^harness=//p' "$ROOT/.ready.flag" | head -1 | tr -d '\r')" || true
  fi
  if [ -z "$v" ] && [ -f "$ROOT/HARNESS_VERSION" ]; then
    v="$(tr -d '\r\n' < "$ROOT/HARNESS_VERSION")" || true
  fi
  printf '%s' "$v"
}

mkdir -p "$DSH_HOME_DIR" "$LOG_DIR"

# ---------------------------------------------------------------------------
# 运行模式（web / cli）读写
# 默认 web：文件缺失、为空、值无法识别时一律回落 web —— 保证不改变既有默认行为。
# ---------------------------------------------------------------------------
get_launch_mode() {
  local v=""
  if [ -f "$LAUNCH_CONF" ]; then
    v="$(sed -n 's/^[[:space:]]*mode[[:space:]]*=[[:space:]]*//p' "$LAUNCH_CONF" | head -1 | tr -d '\r' \
         | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' -e 's/^["'"'"']//' -e 's/["'"'"']$//')"
  fi
  case "$(printf '%s' "$v" | tr '[:upper:]' '[:lower:]')" in
    cli) printf 'cli' ;;
    *)   printf 'web' ;;
  esac
}

mode_label() {
  if [ "$1" = "cli" ]; then printf 'CLI（单次任务 task）'; else printf 'Web（图形界面）'; fi
}

echo ""
echo "============================================"
echo "   USB Harness — 便携式 AI 助手"
# 启动横幅直接显示版本号，一眼可见（状态面板里也有）
HV="$(get_harness_ver)"
if [ -n "$HV" ]; then
  echo "   版本      : v$HV"
else
  echo "   版本      : 未记录（旧版包）"
fi
echo "============================================"

# 统一调用 dsh：便携 node 绝对路径直调 CLI 入口。.bin 垫片靠 PATH 找 node——
# 干净机器报 "command not found: node"，装了旧系统 node（<16.9）则插件树加载失败
# （Object.hasOwn is not a function）。直调后这两类问题从根上消失。
dsh() {
  if [ -f "$DSH_CLI" ]; then "$NODE_BIN" "$DSH_CLI" "$@"
  else                        "$DSH_BIN" "$@"; fi
}

# 环境就绪校验
ready() { [ -x "$NODE_BIN" ] && { [ -f "$DSH_CLI" ] || [ -x "$DSH_BIN" ]; }; }

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
    echo "  dsh 版本  : $(dsh --version 2>/dev/null || echo '未知')"
    HARNESS_VER="$(get_harness_ver)"
    if [ -n "$HARNESS_VER" ]; then echo "  程序版本  : $HARNESS_VER"; else echo "  程序版本  : 未记录（旧版包）"; fi
    echo "  数据目录  : $DSH_HOME_DIR"
    LAUNCH_MODE="$(get_launch_mode)"
    echo "  默认模式  : $(mode_label "$LAUNCH_MODE")（菜单直接选，无需切换）"
    if [ "$LAUNCH_MODE" = "web" ]; then
      echo "  监听地址  : http://0.0.0.0:3080（本机 + 局域网）"
    else
      echo "  监听地址  : 不适用（CLI 模式不监听端口）"
    fi
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
  # exec 只能作用于外部命令，函数 dsh 不能 exec，这里按 CLI 是否存在显式展开
  if [ -f "$DSH_CLI" ]; then
    exec "$NODE_BIN" "$DSH_CLI" web --port "$PORT" --host 0.0.0.0 --no-open 2>&1 | tee -a "$LOG_FILE"
  else
    exec "$DSH_BIN" web --port "$PORT" --host 0.0.0.0 --no-open 2>&1 | tee -a "$LOG_FILE"
  fi
}

# 启动 dsh 单次任务模式（headless profile）
#
# 【重要变更 — dsh 0.1.5 起】
# 0.1.5 取消了「无默认执行档位」的行为：裸跑 `dsh` 会直接报
#   error: --profile <name> is required
# 且上游**不再提供开箱即用的交互式终端对话档位**，可用的只有 web / headless / acp / sdk。
# 因此原先「不带子命令进入交互式 TUI」的设计前提已不存在，改为使用 headless：
#   dsh --profile headless "<task>"  ->  跑一个全新会话，打印最终答案后退出
#
# 【文案对齐 — 与上游 dsh 用词一致】
# 上游 `dsh --profile headless --help` 原文：
#   Usage: dsh --profile headless [options] [task...]
#   Arguments: task   the task text; multiple words are joined by spaces
#   Answer one task, stream reasoning to stderr, print the final assistant message, and exit.
#
# 与 start_web 共用同一份环境变量（DSH_HOME / PATH），模型配置、会话数据完全一致。
start_cli() {
  export DSH_HOME="$DSH_HOME_DIR"
  export PATH="$NODE_DIR/bin:$ROOT/.cache/app/node_modules/.bin:$PATH"
  echo ""
  echo "  说明: 输入一个任务（task），dsh 跑完一次会话后打印最终答案并退出"
  echo "  等价命令: dsh --profile headless \"<task>\""
  echo "  提示: 本模式不监听端口，浏览器访问不可用"
  echo "  想切回 Web 界面: 返回菜单后选 [1] 启动 Web 界面即可，无需切换"
  echo ""
  read -r -p "  请输入任务内容 / task（直接回车取消）: " task
  if [ -z "${task// }" ]; then
    echo "  已取消，未执行任何任务。"
    return
  fi
  echo ""
  echo "  [task] $task"
  echo ""
  # 【为什么这里把 stdout / stderr 分开处理】
  # headless 档位把「推理过程」写到 **stderr**（上游原话："stream reasoning to
  # stderr, print the final assistant message, and exit"）。若用 `2>&1 | tee` 混流，
  # 推理过程会和最终答案糊在一起，看不出哪段是答案。
  # 故 stdout → 终端 + cli.log；stderr → 终端（前缀 [reasoning]，暗灰）+ err.log。
  # 与 launch-windows.ps1 的处理方式保持一致（那边用 .NET Process 读两条流）。
  if [ -f "$DSH_CLI" ]; then
    "$NODE_BIN" "$DSH_CLI" --profile headless "$task" >"$CLI_LOG_FILE.tmp" 2>"$CLI_ERR_FILE.tmp"
    rc=$?
  else
    "$DSH_BIN" --profile headless "$task" >"$CLI_LOG_FILE.tmp" 2>"$CLI_ERR_FILE.tmp"
    rc=$?
  fi
  # 推理过程：落日志，终端只给一句轻提示（不刷屏）
  if [ -s "$CLI_ERR_FILE.tmp" ]; then
    cat "$CLI_ERR_FILE.tmp" >>"$CLI_ERR_FILE"
    echo "  [推理过程] $(head -c 400 "$CLI_ERR_FILE.tmp" | tr '\n' ' ')"
    echo "  （完整推理过程已写入 $CLI_ERR_FILE）"
    echo ""
  fi
  # 最终答案：终端正文 + 落日志
  if [ -s "$CLI_LOG_FILE.tmp" ]; then
    echo "  ===== 最终答案 ====="
    echo ""
    sed 's/^/  /' "$CLI_LOG_FILE.tmp"
    echo ""
    cat "$CLI_LOG_FILE.tmp" >>"$CLI_LOG_FILE"
  else
    echo "  （本次没有产生最终答案）"
    echo ""
  fi
  rm -f "$CLI_LOG_FILE.tmp" "$CLI_ERR_FILE.tmp"
  if [ "$rc" -ne 0 ]; then
    echo "[错误] dsh headless 退出码 $rc。"
    if grep -q 'NO_ADAPTER' "$CLI_ERR_FILE" 2>/dev/null; then
      echo "  [提示] NO_ADAPTER 表示「插件树已加载成功，但没有可用的模型」。"
      echo "         请返回菜单选 [1] 启动 Web 界面，在 设置 → 模型 里配置一个提供方后再试。"
    fi
    echo ""
  fi
  echo "dsh 已退出（代码 $rc）。按回车键返回菜单 ..."
  read -r _
}

# 【为什么取消了「切换运行模式」这一项】
# 原先流程是「[4] 切换模式 → 下次 [1] 启动才生效」，要先切换、再启动，绕一圈还容易忘。
# 本质问题是：**运行模式几乎总是「这一次」的选择**，
# 却用「先改持久配置、下次生效」的交互去表达它。
# 改为菜单里直接选——选完即执行，不需要先切换、也不需要记住当前处在哪个模式。
# config/launch.conf 仍保留并继续维护：命令行直启（launch.sh web / cli）需要它作默认值。
# 注意：菜单选择【不】写回 launch.conf——菜单选择是一次性动作，
# 改持久值会让「上次点了什么」悄悄影响下次不带参数的启动，反而更难预期。

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
# web / cli 为显式指定，优先于 config/launch.conf 里记录的当前模式；
# 不带参数（进入交互菜单）时才按记录的模式分派。
case "$ACTION" in
  web)    start_web; exit 0 ;;
  cli)    start_cli; exit 0 ;;
  setup)  do_setup; exit 0 ;;
  reset)  do_reset; exit 0 ;;
  status) show_status; exit 0 ;;
  check-update) bash "$UPGRADE_SCRIPT" --check-only; exit $? ;;
  upgrade)      bash "$UPGRADE_SCRIPT"; exit $? ;;
esac

# 交互菜单
while true; do
  show_status
  echo "  [1] 启动 Web 界面（图形化，浏览器访问）"
  echo "  [2] 单次任务 CLI（输入一个 task，跑完打印答案后退出）"
  echo "  [3] 检查更新（程序与 dsh 版本）"
  echo "  [4] 重置（清配置数据，保留运行环境，无需下载）"
  echo "  [5] 退出"
  echo ""
  read -r -p "  请选择 " choice
  case "$choice" in
    1) start_web ;;
    2) start_cli ;;
    3) bash "$UPGRADE_SCRIPT" --check-only || true ;;
    4) do_reset ;;
    5) exit 0 ;;
    "") ;;
    *) echo "[警告] 无效选择：$choice" ;;
  esac
done
