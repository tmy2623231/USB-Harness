#!/usr/bin/env bash
# =============================================================================
# upgrade-unix.sh — 检查更新 / 升级 dsh（Linux/macOS）
# 与 scripts/upgrade-windows.ps1 同构；传 dsh 版本走 DSH_VERSION 环境变量
# （setup-unix.sh 原生支持 env 覆盖，无需改其参数面）。
# 用法：
#   bash scripts/upgrade-unix.sh --check-only
#   bash scripts/upgrade-unix.sh                 # 交互式检查 + 可选升级
#   bash scripts/upgrade-unix.sh 0.1.2           # 直接升级到指定 dsh 版本
#   bash scripts/upgrade-unix.sh --reconcile-only
# 退出码：0=已最新或升级成功  1=有更新（仅 check）  2=网络不可达  3=本地版本未知
#         4=peer 未适配被阻断  5=升级失败已回滚  6=磁盘不足
# =============================================================================
set -uo pipefail
# 注意：不用 set -e —— 所有失败路径显式处理，避免非零退出码炸穿调用方（launch.sh || true 双保险）

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# ---- 平台/架构（与 setup-unix.sh 同款判定）----
case "$(uname -s)" in
  Linux)  OS="linux" ;;
  Darwin) OS="darwin" ;;
  *)      echo "不支持的平台: $(uname -s)" >&2; exit 1 ;;
esac
case "$(uname -m)" in
  x86_64|amd64) ARCH="x64" ;;
  aarch64|arm64) ARCH="arm64" ;;
  *)             echo "不支持的架构: $(uname -m)" >&2; exit 1 ;;
esac
PLATFORM="${OS}-${ARCH}"

REPO='tmy2623231/USB-Harness'
APP="$ROOT/.cache/app"
BAK="$ROOT/.cache/app.bak-upgrade"
JOURNAL="$ROOT/.cache/upgrade.state"
FLAG="$ROOT/.ready.flag"
HARNESS_FILE="$ROOT/HARNESS_VERSION"
SETUP_SCRIPT="$ROOT/scripts/setup-unix.sh"
NPM_CACHE="$ROOT/.cache/npm-cache"
NPM="$ROOT/.cache/runtimes/${PLATFORM}/node/bin/npm"
SELF_LOG="$ROOT/data/logs/dsh-selfcheck.log"
# dsh 的 CLI 入口（bin.js）。优先用便携 node 绝对路径直调，摆脱 .bin 垫片
# （#!/usr/bin/env node）靠 PATH 找 node 的坑；垫片仅作 bin.js 缺失时的回退。
DSH_CLI="$APP/node_modules/@deepseek-ai/dsh/lib/bin.js"
DSH_BIN="$APP/node_modules/.bin/dsh"

# 兜底：把便携 node 提到 PATH 最前（对 dsh 内部再派生的子进程同样生效）。
# 注意：这只是兜底——dsh 主进程的 node 解析已不再依赖 PATH（见 dsh()）。
export PATH="$ROOT/.cache/runtimes/${PLATFORM}/node/bin:$PATH"

LD='unknown'; LH=''; LN='unknown'          # 本地 dsh / harness / node
LH_LATEST=''; LD_LATEST=''                 # 上游最新
NET_ERRORS=()

w_warn() { echo "  [!] $*"; }
w_ok()   { echo "  [✓] $*"; }

# 统一调用 dsh：便携 node 绝对路径直调 CLI 入口。.bin 垫片靠 PATH 找 node——
# 干净机器报 "command not found: node"，装了旧系统 node（<16.9）则插件树加载失败
# （Object.hasOwn is not a function）。直调后这两类问题从根上消失。
dsh() {
  if [ -f "$DSH_CLI" ]; then "$ROOT/.cache/runtimes/${PLATFORM}/node/bin/node" "$DSH_CLI" "$@"
  else                        "$DSH_BIN" "$@"; fi
}

# ---------------------------------------------------------------------------
# 本地版本（dsh 优先跑 --version，flag 后备；全程 || 兜底防 set -u/-o 传染）
# ---------------------------------------------------------------------------
get_local_versions() {
  if [ -f "$DSH_CLI" ] || [ -x "$DSH_BIN" ]; then
    LD="$(dsh --version 2>/dev/null | tail -1 | tr -d '\r')" || true
    [ -z "$LD" ] && LD='unknown'
  fi
  if [ "$LD" = "unknown" ] && [ -f "$FLAG" ]; then
    LD="$(sed -n 's/^dsh=//p' "$FLAG" 2>/dev/null | head -1 | tr -d '\r')" || true
    [ -z "$LD" ] && LD='unknown'
  fi
  if [ -f "$FLAG" ]; then
    LH="$(sed -n 's/^harness=//p' "$FLAG" 2>/dev/null | head -1 | tr -d '\r')" || true
  fi
  if [ -z "$LH" ] && [ -f "$HARNESS_FILE" ]; then
    LH="$(tr -d '\r\n' < "$HARNESS_FILE" 2>/dev/null)" || true
  fi
  if [ -x "$ROOT/.cache/runtimes/${PLATFORM}/node/bin/node" ]; then
    LN="$("$ROOT/.cache/runtimes/${PLATFORM}/node/bin/node" -v 2>/dev/null)" || true
  fi
  return 0
}

# ---------------------------------------------------------------------------
# 上游最新（GitHub 与 npm 两源独立探测，失败互不拖累，绝不 exit）
# ---------------------------------------------------------------------------
get_latest_versions() {
  LH_LATEST="$(curl -L --fail --max-time 10 -s \
    "https://api.github.com/repos/$REPO/releases/latest" 2>/dev/null \
    | grep -o '"tag_name": *"[^"]*"' | head -1 | cut -d'"' -f4)" || true
  [ -z "$LH_LATEST" ] && NET_ERRORS+=("GitHub Release 检测失败")

  if [ -x "$NPM" ]; then
    LD_LATEST="$("$NPM" view @deepseek-ai/dsh version --cache "$NPM_CACHE" \
      --registry=https://registry.npmmirror.com 2>/dev/null | tail -1 | tr -d '\r')" || true
    if [ -z "$LD_LATEST" ]; then
      LD_LATEST="$("$NPM" view @deepseek-ai/dsh version --cache "$NPM_CACHE" 2>/dev/null | tail -1 | tr -d '\r')" || true
    fi
    [ -z "$LD_LATEST" ] && NET_ERRORS+=("npm 版本检测失败（npmmirror 与官方源均未返回）")
  else
    NET_ERRORS+=("便携 Node 不存在，跳过 npm 版本检测")
  fi
  return 0
}

show_report() {
  echo ""
  echo "========== 版本检查 =========="
  if [ -n "$LH_LATEST" ]; then
    if [ -n "$LH" ] && [ "$LH" = "$LH_LATEST" ]; then
      w_ok "程序版本: $LH（已是最新）"
    elif [ -z "$LH" ]; then
      w_warn "程序版本: 未记录（旧版包）。最新完整包: $LH_LATEST，建议从 Releases 页下载更新"
    else
      w_warn "程序版本: $LH → 有新版本 $LH_LATEST！请到 Releases 页下载完整包（数据可沿用）"
    fi
  else
    w_warn "程序版本: 无法连接 GitHub，已跳过该项检查"
  fi
  if [ -n "$LD_LATEST" ]; then
    if [ "$LD" = "$LD_LATEST" ]; then
      w_ok "dsh 版本 : $LD（已是最新）"
    elif [ "$LD" = "unknown" ]; then
      w_warn "dsh 版本 : 未知（环境不完整）。上游最新: $LD_LATEST"
    else
      w_warn "dsh 版本 : $LD → 上游有新版本 $LD_LATEST（需本项目适配后才会在此提供升级）"
    fi
  else
    w_warn "dsh 版本 : 无法连接 npm 源，已跳过该项检查"
  fi
  echo "=============================="
}

# ---------------------------------------------------------------------------
# peer 一致性守门：setup-unix.sh 的 PEERS 中 dsh-*@^X 的 X 必须与目标一致
# ---------------------------------------------------------------------------
peer_match() {
  local target="$1"
  [ -f "$SETUP_SCRIPT" ] || { w_warn "找不到 setup-unix.sh"; return 1; }
  # 从 PEERS=( ... ) 块提取 @deepseek-ai/dsh-*@^X 的 X，要求唯一且等于 target
  local versions
  versions="$(sed -n '/PEERS=(/,/^  )/p' "$SETUP_SCRIPT" \
    | grep -o "@deepseek-ai/dsh-[a-z0-9-]*@\^[0-9][^']*" \
    | sed 's/.*@\^//' | sort -u)" || true
  [ -n "$versions" ] || { w_warn "无法从 setup-unix.sh 解析 peer 版本"; return 1; }
  local count
  count="$(echo "$versions" | wc -l | tr -d ' ')"
  if [ "$count" != "1" ]; then
    w_warn "peer 版本串存在多个不同值，脚本可能被改坏："
    echo "$versions" | sed 's/^/    /'
    return 1
  fi
  if [ "$versions" != "$target" ]; then
    w_warn "peer 列表与 dsh@$target 不一致（锁定为 $versions），强制升级已阻断。"
    echo "    上游 dsh 已发新版但本项目尚未适配。请等待本项目发布适配版 Release（菜单 [2] 会提示），"
    echo "    或由维护者更新 setup-unix.sh 的 PEERS 版本串后再试。"
    return 1
  fi
  return 0
}

# ---------------------------------------------------------------------------
# 升级后自检：①dsh --version == 目标 ②启动 + HTTP 探测 + 无模块缺失
# ---------------------------------------------------------------------------
self_check() {
  local expect="$1"
  local got
  got="$(dsh --version 2>/dev/null | tail -1 | tr -d '\r')" || true
  if [ "$got" != "$expect" ]; then
    w_warn "dsh --version 返回 '$got'，期望 '$expect'"
    return 1
  fi
  w_ok "dsh --version = $got"

  # 随机空闲口 3900-3999，避开用户可能正在跑的 3080
  local port=0 p
  for p in $(seq 3900 3999); do
    if ! (exec 3<>"/dev/tcp/127.0.0.1/$p") 2>/dev/null; then port=$p; break; fi
    exec 3>&- 2>/dev/null || true
  done
  if [ "$port" = "0" ]; then
    w_warn "3900-3999 端口全被占用，跳过 HTTP 探测（不阻断）"
    return 0
  fi

  mkdir -p "$ROOT/data/logs" "$ROOT/data/dsh"
  # 直调便携 node.exe 绝对路径 + CLI 入口（不经垫片，避免 PATH 解析到旧系统 node）
  if [ -f "$DSH_CLI" ]; then
    DSH_HOME="$ROOT/data/dsh" "$ROOT/.cache/runtimes/${PLATFORM}/node/bin/node" "$DSH_CLI" \
      web --port "$port" --host 127.0.0.1 --no-open > "$SELF_LOG" 2>&1 &
  else
    DSH_HOME="$ROOT/data/dsh" "$DSH_BIN" \
      web --port "$port" --host 127.0.0.1 --no-open > "$SELF_LOG" 2>&1 &
  fi
  local pid=$!
  local ok=0 i
  for i in $(seq 1 20); do
    sleep 1
    kill -0 "$pid" 2>/dev/null || break
    if curl -s -o /dev/null --max-time 2 "http://127.0.0.1:$port" 2>/dev/null; then ok=1; break; fi
  done
  kill "$pid" 2>/dev/null || true
  pkill -P "$pid" 2>/dev/null || true
  wait "$pid" 2>/dev/null || true

  if [ "$ok" = "1" ]; then
    w_ok "启动自检通过（HTTP 200 @127.0.0.1:$port）"
  else
    w_warn "HTTP 探测未就绪（不阻断，已记录日志）"
  fi
  if grep -qE 'ERR_MODULE_NOT_FOUND|Cannot find module' "$SELF_LOG" 2>/dev/null; then
    w_warn "自检日志含模块缺失错误"
    return 1
  fi
  return 0
}

# ---------------------------------------------------------------------------
# 回滚：恢复 bak + journal 中的 flag 原样还原
# ---------------------------------------------------------------------------
rollback() {
  local reason="$1"
  w_warn "升级失败：$reason"
  echo "  正在回滚到旧版本 ..."
  local flag_b64=""
  if [ -f "$JOURNAL" ]; then
    flag_b64="$(sed -n 's/^flag_bak_b64=//p' "$JOURNAL" | head -1)" || true
  fi
  if [ -d "$BAK" ]; then
    [ -d "$APP" ] && rm -rf "$APP"
    mv "$BAK" "$APP" && w_ok "已恢复旧版本运行环境"
  fi
  if [ -n "$flag_b64" ]; then
    echo "$flag_b64" | base64 -d > "$FLAG" 2>/dev/null && w_ok "已还原 .ready.flag"
  fi
  rm -f "$JOURNAL"
  echo "  data/（配置/会话/密钥）未受任何影响。"
  exit 5
}

set_journal_step() {
  local step="$1"
  if [ -f "$JOURNAL" ]; then
    grep -v '^step=' "$JOURNAL" > "$JOURNAL.tmp" 2>/dev/null || true
    echo "step=$step" >> "$JOURNAL.tmp"
    mv -f "$JOURNAL.tmp" "$JOURNAL"
  fi
}

get_dir_size_mb() {
  local s
  s="$(du -sm "$1" 2>/dev/null | cut -f1)" || s=0
  echo "${s:-0}"
}

# ---------------------------------------------------------------------------
# 升级主流程
# ---------------------------------------------------------------------------
do_upgrade() {
  local target="$1"
  echo ""
  echo "===== 升级 dsh：当前 → $target ====="

  peer_match "$target" || exit 4
  if [ ! -x "$ROOT/.cache/runtimes/${PLATFORM}/node/bin/node" ]; then
    w_warn "便携 Node 不存在，请先运行 setup"; exit 3
  fi
  [ -f "$FLAG" ] || { w_warn ".ready.flag 不存在，请先运行 setup"; exit 3; }

  # 磁盘预检：备份与新版并存峰值 ≈ 2×app
  local app_mb free_mb drive free_mb2
  app_mb="$(get_dir_size_mb "$APP")"
  drive="$(echo "$ROOT" | cut -d/ -f2)"
  if [ "$app_mb" -gt 0 ] 2>/dev/null; then
    free_mb2="$(df -Pm "$ROOT" 2>/dev/null | tail -1 | awk '{print $4}')" || free_mb2=0
    if [ "${free_mb2:-0}" -lt $((12 * app_mb / 10)) ] 2>/dev/null; then
      w_warn "磁盘剩余 ${free_mb2}MB 不足以安全升级（需 ≥ $((12 * app_mb / 10))MB 备份空间）"
      echo "    可清理磁盘后重试，或删除 .cache/app 后重跑 setup（该方式失败无法自动回滚，慎用）。"
      exit 6
    fi
  fi

  if [ "$LD" = "unknown" ] || [ -z "$LD" ]; then w_warn "当前 dsh 版本未知，无法安全升级"; exit 3; fi
  if [ "$LD" = "$target" ]; then w_ok "当前已是 $target，无需升级"; exit 0; fi

  # ① journal 先行（flag 全文 base64 存，规避 CRLF/多行破坏结构）
  local flag_b64
  flag_b64="$(base64 < "$FLAG" 2>/dev/null | tr -d '\n')" || flag_b64=""
  {
    printf 'old_dsh=%s\nnew_dsh=%s\nstep=journal\n' "$LD" "$target"
    printf "flag_bak_b64=%s\n" "$flag_b64"
  } > "$JOURNAL"

  # ② 备份：同盘 rename，O(1)；失败重试 3 次
  local moved=0 i
  for i in 1 2 3; do
    if mv "$APP" "$BAK" 2>/dev/null; then moved=1; break; fi
    w_warn "备份改名第 $i 次失败（可能被占用），1 秒后重试 ..."
    sleep 1
  done
  if [ "$moved" != "1" ]; then
    rm -f "$JOURNAL"
    echo "FAILED: app 目录被占用，升级中止（原环境未受影响）" >&2
    exit 1
  fi
  set_journal_step "backup-done"

  # ③ 重装：Node 已在 → [1/3] 跳过；app 已改名走 → [2/3][3/3] 必执行并重写 flag
  echo "  安装新版本（依赖大部分命中本地缓存，通常 1-3 分钟）..."
  if ! DSH_VERSION="$target" bash "$SETUP_SCRIPT"; then
    rollback "setup 失败"
  fi
  set_journal_step "installed"

  # ④ 自检（失败 → 自动回滚）
  if ! self_check "$target"; then
    rollback "升级后自检未通过"
  fi
  set_journal_step "verified"

  # ⑤ 成功清理
  rm -f "$JOURNAL"
  rm -rf "$BAK" 2>/dev/null || true
  echo ""
  echo "UPGRADE_OK dsh=$target"
  exit 0
}

# ---------------------------------------------------------------------------
# 断电/中断残留裁决（幂等，无网络）
# ---------------------------------------------------------------------------
reconcile() {
  [ -d "$BAK" ] || return 0
  w_warn "检测到上次升级的残留，正在裁决恢复 ..."
  local flag_b64=""
  if [ -f "$JOURNAL" ]; then
    flag_b64="$(sed -n 's/^flag_bak_b64=//p' "$JOURNAL" | head -1)" || true
  fi

  if [ ! -d "$APP" ]; then
    mv "$BAK" "$APP"
    w_warn "已恢复旧版本环境（上次升级在安装阶段中断）。"
  else
    local app_ver="unknown" flag_dsh=""
    if [ -f "$DSH_CLI" ] || [ -x "$DSH_BIN" ]; then
      app_ver="$(dsh --version 2>/dev/null | tail -1 | tr -d '\r')" || true
    fi
    if [ -f "$FLAG" ]; then
      flag_dsh="$(sed -n 's/^dsh=//p' "$FLAG" | head -1 | tr -d '\r')" || true
    fi
    if [ -n "$app_ver" ] && [ "$app_ver" != "unknown" ] && [ "$app_ver" = "$flag_dsh" ]; then
      rm -rf "$BAK"
      w_warn "上次升级已完成但清理被打断，已保留新版本（$app_ver）并清理备份。"
    else
      rm -rf "$APP"
      mv "$BAK" "$APP"
      if [ -n "$flag_b64" ]; then
        echo "$flag_b64" | base64 -d > "$FLAG" 2>/dev/null || true
      fi
      w_warn "上次升级未完成（新环境不完整），已回滚到旧版本。"
    fi
  fi
  rm -f "$JOURNAL"
  return 0
}

# ---------------------------------------------------------------------------
# 主流程
# ---------------------------------------------------------------------------
case "${1:-}" in
  --reconcile-only) reconcile; exit 0 ;;
  --check-only)     CHECK_ONLY=1 ;;
esac

get_local_versions
get_latest_versions
show_report

if [ "${CHECK_ONLY:-0}" = "1" ]; then
  if [ ${#NET_ERRORS[@]} -gt 0 ] && [ -z "$LH_LATEST" ] && [ -z "$LD_LATEST" ]; then exit 2; fi
  if [ "$LD" = "unknown" ] && [ -z "$LH" ]; then exit 3; fi
  has_update=0
  if [ -n "$LH_LATEST" ] && [ "$LH" != "$LH_LATEST" ]; then has_update=1; fi
  if [ -n "$LD_LATEST" ] && [ "$LD" != "$LD_LATEST" ]; then has_update=1; fi
  exit $has_update
fi

if [ -n "${1:-}" ] && [ "${1:-}" != "--check-only" ]; then
  do_upgrade "$1"
fi

# 交互式路径：仅当上游 dsh 有新版时询问
if [ -n "$LD_LATEST" ] && [ "$LD" != "unknown" ] && [ "$LD" != "$LD_LATEST" ]; then
  echo ""
  printf "  是否强制升级 dsh 到 %s？（升级前会做适配校验，失败自动回滚）[y/N] " "$LD_LATEST"
  read -r ans
  if echo "$ans" | grep -qi '^y'; then do_upgrade "$LD_LATEST"; fi
elif [ ${#NET_ERRORS[@]} -gt 0 ] && [ -z "$LH_LATEST" ] && [ -z "$LD_LATEST" ]; then
  echo ""
  w_warn "网络不可用，无法检查更新。可稍后重试。"
  exit 2
else
  echo ""
  w_ok "一切正常。"
  exit 0
fi
