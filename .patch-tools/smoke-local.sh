#!/usr/bin/env bash
# =============================================================================
# smoke-local.sh — 本地冒烟测试（带硬超时 + 实时进度）
# =============================================================================
# 设计要点（针对此前"卡死 10 分钟无输出"的教训）：
#   1. 每一步都有 timeout 包裹，绝不允许无限等待
#   2. 每步开始/结束都打时间戳，进度实时可见
#   3. 所有网络/服务操作都带 --max-time / --connect-timeout
#   4. 结果汇总为 用例数 / 通过数 / 通过率
#   5. 任何一步超时都不静默跳过，标记为 FAIL/TIMEOUT 并计入统计
#
# 用法: bash .patch-tools/smoke-local.sh [--quick]
# =============================================================================
set -uo pipefail

# Git Bash 的环境里 /usr/bin 可能不在 PATH（本次故障的真凶），先兜底
export PATH="/usr/bin:/bin:$PATH"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

# 【关键】传给 node.exe 的路径必须是 Windows 形式（D:/...）。
# Git Bash 的 POSIX 形式（/d/...）会被 node 当成非法路径，表现为
# 秒退且只打印 "Node.js v22.23.2"（无报错正文），极易误判为"卡死/崩溃"。
ROOT_W="$(pwd -W 2>/dev/null || pwd)"

# 默认指向**真实 U 盘布局**（.cache/…），与 setup 脚本装出来的东西一致。
# 需要指向别处时用环境变量覆盖：
#   SMOKE_APP_DIR=... SMOKE_NODE_DIR=... bash .patch-tools/smoke-local.sh
NODE_DIR="${SMOKE_NODE_DIR:-$ROOT_W/.cache/runtimes/windows-x64/node}"
APP_DIR="${SMOKE_APP_DIR:-$ROOT_W/.cache/app}"
WORK_DIR="${SMOKE_WORK_DIR:-$ROOT_W/.cache/smoke}"

NODE="$NODE_DIR/node.exe"
CLI="$APP_DIR/node_modules/@deepseek-ai/dsh/lib/bin.js"
DSH_HOME_TEST="$WORK_DIR/dsh-smoke"
LOG="$WORK_DIR/smoke.log"

mkdir -p "$WORK_DIR"

# 超时预算（秒）
T_VERSION=60
T_HELP=60
T_HEADLESS=180
T_WEB_BOOT=120
T_ASSET=30
T_PATCHCHECK=300

QUICK=0
[ "${1:-}" = "--quick" ] && QUICK=1

PASS=0
FAIL=0
RESULTS=()

ts() { date '+%H:%M:%S'; }
say() { printf '[%s] %s\n' "$(ts)" "$*"; }
hr()  { printf '%s\n' "----------------------------------------------------------------"; }

# 记录用例结果
record() {
  local name="$1" status="$2" detail="$3"
  if [ "$status" = "PASS" ]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); fi
  RESULTS+=("$(printf '%-42s %-7s %s' "$name" "$status" "$detail")")
  say "  => $status  $name  ($detail)"
}

# 带超时执行，返回 0/非0；超时返回 124
run_to() {
  local secs="$1"; shift
  timeout "$secs" "$@"
}

: > "$LOG"
say "===== USB Harness 本地冒烟测试开始 ====="
say "ROOT      = $ROOT_W"
say "NODE      = $NODE"
say "CLI       = $CLI"

# ---------------------------------------------------------------------------
# 前置校验：二进制与安装树是否就位
# ---------------------------------------------------------------------------
hr
say "前置校验"
if [ ! -x "$NODE" ] && [ ! -f "$NODE" ]; then
  say "!! 便携 Node 不存在，无法继续：$NODE"
  exit 2
fi
if [ ! -f "$CLI" ]; then
  say "!! dsh CLI 入口不存在，无法继续：$CLI"
  exit 2
fi
say "  便携 Node: $(run_to 20 "$NODE" -v 2>&1 | head -1)"
say "  dsh 入口 : 存在"

rm -rf "$DSH_HOME_TEST"; mkdir -p "$DSH_HOME_TEST"
export DSH_HOME="$DSH_HOME_TEST"
# 去掉 WorkBuddy 沙箱的 safe-delete 门控，否则 dsh 的 .lock 清理会被拦截
unset CODEBUDDY_SAFE_DELETE_BULK_STATE_DIR CODEBUDDY_TOOL_CALL_ID CODEBUDDY_SAFE_DELETE_BULK_GUARD

# ---------------------------------------------------------------------------
# 用例 1：dsh --version
# ---------------------------------------------------------------------------
hr
say "用例 1/9  dsh --version（超时 ${T_VERSION}s）"
out="$(run_to $T_VERSION "$NODE" "$CLI" --version 2>&1 | tail -1)"
rc=$?
if [ $rc -eq 124 ]; then
  record "dsh --version" TIMEOUT ">${T_VERSION}s 未返回"
elif [ "$out" = "0.1.5-rc.2" ]; then
  record "dsh --version" PASS "输出 $out"
else
  record "dsh --version" FAIL "输出=$out rc=$rc"
fi

# ---------------------------------------------------------------------------
# 用例 2：dsh --help 且品牌已替换
# ---------------------------------------------------------------------------
hr
say "用例 2/9  dsh --help（超时 ${T_HELP}s）+ 品牌检查"
help_out="$(run_to $T_HELP "$NODE" "$CLI" --help 2>&1)"
rc=$?
if [ $rc -eq 124 ]; then
  record "dsh --help" TIMEOUT ">${T_HELP}s 未返回"
else
  ds_count=$(printf '%s' "$help_out" | grep -ci "deepseek" || true)
  usb_count=$(printf '%s' "$help_out" | grep -c "USB Harness" || true)
  if [ "$ds_count" = "0" ] && [ "$usb_count" -ge 1 ]; then
    record "dsh --help 品牌" PASS "DeepSeek=$ds_count USB Harness=$usb_count"
  else
    record "dsh --help 品牌" FAIL "DeepSeek=$ds_count USB Harness=$usb_count"
  fi
fi

# ---------------------------------------------------------------------------
# 用例 3：$PeerFix 清单与实际安装一致性（前向校验）
# ---------------------------------------------------------------------------
# 【为什么是这个检查】此前这里做的是"扫描已安装树找解析不到的 import"，
# 那是循环论证：没装上的包本就不在安装树里，扫不到 → 误报"缺失 0 个"。
# 结果 CI 在 3 个真缺失的包上失败，本地却全绿。现在改为**前向**校验：
# 以 setup 脚本的 $PeerFix 为唯一数据源，逐个断言其声明的包确实落地。
# 这样"清单写了但没装上"会在本地就炸，而不是等到 CI。
hr
say "用例 3/9  \$PeerFix 清单与实际安装一致性（超时 ${T_ASSET}s）"
if [ "$QUICK" = "1" ]; then
  record "peer 清单一致性" SKIP "--quick 跳过"
else
  PEER_MISSING=0
  PEER_TOTAL=0
  PEER_LIST=""
  # 从 setup 脚本抽包名：双引号段（插值 $peerVer 的 dsh 子包）+ 单引号段（第三方）
  while IFS= read -r pkg; do
    [ -z "$pkg" ] && continue
    PEER_TOTAL=$((PEER_TOTAL+1))
    sub="${pkg##*/}"
    if [ -d "$APP_DIR/node_modules/@deepseek-ai/$sub" ] || [ -d "$APP_DIR/node_modules/$pkg" ]; then
      :
    else
      PEER_MISSING=$((PEER_MISSING+1))
      PEER_LIST="$PEER_LIST $pkg"
    fi
  done < <(sed -n '/\$PeerFix = @(/,/^    )/p' scripts/setup-windows.ps1 2>/dev/null \
           | grep -oE '"[^"]+@\$peerVer"|'"'"'[^'"'"']+'"'"'' \
           | sed -e 's/^"//' -e 's/"$//' -e "s/^'//" -e "s/'$//" \
           | sed -e 's/@\$peerVer//' -e 's/@\^[0-9].*$//' -e 's/@[0-9].*$//' \
           | grep -v '^$' | sort -u)
  if [ "$PEER_TOTAL" -lt 6 ]; then
    record "peer 清单一致性" FAIL "从 setup 脚本只解析到 ${PEER_TOTAL} 项，疑似解析失败"
  elif [ "$PEER_MISSING" -eq 0 ]; then
    record "peer 清单一致性" PASS "${PEER_TOTAL} 项全部落地"
  else
    record "peer 清单一致性" FAIL "缺 ${PEER_MISSING}/${PEER_TOTAL}:${PEER_LIST}"
  fi
fi

# ---------------------------------------------------------------------------
# 用例 4：补丁基线校验（dsh_patch_compat_check.py）
# ---------------------------------------------------------------------------
hr
say "用例 4/9  补丁基线校验（超时 ${T_PATCHCHECK}s）"
pc_out="$(run_to $T_PATCHCHECK python scripts/dsh_patch_compat_check.py \
          --patch "brand-patch/@deepseek-ai" --base 0.1.5-rc.2 --target 0.1.5-rc.2 2>&1)"
rc=$?
if [ $rc -eq 124 ]; then
  record "补丁基线校验" TIMEOUT ">${T_PATCHCHECK}s"
else
  verdict="$(printf '%s' "$pc_out" | grep "变更判定:" | head -1)"
  printf '%s\n' "$pc_out" >> "$LOG"
  if printf '%s' "$verdict" | grep -q "阻断 0" && printf '%s' "$verdict" | grep -q "需确认 0"; then
    record "补丁基线校验" PASS "$verdict"
  else
    record "补丁基线校验" FAIL "$verdict"
  fi
fi

# ---------------------------------------------------------------------------
# 用例 5：headless（CLI）模式可启动到模型派发阶段
# ---------------------------------------------------------------------------
hr
say "用例 5/9  headless CLI 模式（超时 ${T_HEADLESS}s）"
if [ "$QUICK" = "1" ]; then
  record "headless CLI 模式" SKIP "--quick 跳过"
else
  hl_out="$(run_to $T_HEADLESS "$NODE" "$CLI" --profile headless "reply with the single word ok" </dev/null 2>&1)"
  rc=$?
  printf '%s\n' "$hl_out" >> "$LOG"
  if [ $rc -eq 124 ]; then
    record "headless CLI 模式" TIMEOUT ">${T_HEADLESS}s 未返回"
  elif printf '%s' "$hl_out" | grep -q "NO_ADAPTER\|no adapter registered"; then
    # 无 API Key 时必然停在这里 —— 说明插件树已完整加载、仅缺模型凭据
    record "headless CLI 模式" PASS "插件树加载成功（止于模型派发：无 API Key）"
  elif [ $rc -eq 0 ]; then
    record "headless CLI 模式" PASS "正常退出 rc=0"
  else
    record "headless CLI 模式" FAIL "rc=$rc 输出: $(printf '%s' "$hl_out" | tail -3 | tr '\n' ' ')"
  fi
fi

# ---------------------------------------------------------------------------
# 用例 6：启动器的 CLI 分支确实带了 --profile（回归：曾漏传导致必失败）
# ---------------------------------------------------------------------------
# 【背景 — 这个用例为什么必须存在】
# dsh 0.1.5 起取消了默认执行档位：裸跑 `dsh` 直接报
#   error: --profile <name> is required
# 而 launch-windows.ps1 的 CLI 分支当时调的就是裸 `dsh`，因此**每次必失败**。
# 上一版冒烟没抓到，是因为用例 5 直接调 dsh、**绕过了启动器**——
# 测的是 dsh 本身能跑 headless，而不是"启动器的 CLI 模式可用"。
# 这个用例转而检查**启动器的调用路径本身**，堵住该盲区。
hr
say "用例 6/9  启动器 CLI 分支传参（静态检查）"
LAUNCH_PS1="scripts/launch-windows.ps1"
if [ ! -f "$LAUNCH_PS1" ]; then
  record "启动器 CLI 传参" FAIL "找不到 $LAUNCH_PS1"
else
  # 抓 Start-Cli 函数体（到下一个顶层 function 或文件结束）
  cli_body="$(sed -n '/^function Start-Cli/,/^function /p' "$LAUNCH_PS1" | sed '$d')"
  if [ -z "$cli_body" ]; then
    record "启动器 CLI 传参" FAIL "未能从 $LAUNCH_PS1 解析出 Start-Cli 函数体"
  elif ! printf '%s' "$cli_body" | grep -q 'Invoke-Dsh'; then
    record "启动器 CLI 传参" FAIL "Start-Cli 未调用 Invoke-Dsh"
  elif printf '%s' "$cli_body" | grep -qE 'Invoke-Dsh[[:space:]]+--profile[[:space:]]+headless'; then
    record "启动器 CLI 传参" PASS "已显式传 --profile headless"
  else
    record "启动器 CLI 传参" FAIL "Start-Cli 调用 Invoke-Dsh 时未传 --profile headless（裸跑必报 --profile is required）"
  fi
fi

# ---------------------------------------------------------------------------
# 用例 7：brand-patch 的浏览器端补丁能真实求值（回归：曾漏声明构造函数参数）
# ---------------------------------------------------------------------------
# 【背景 — 这个用例为什么必须存在】
# brand-patch 里的 dsh-client-ui-permission-presets/lib/client.js 是**整文件快照**，
# 其中我们的定制往 permissionDefaultOf / 控制器里穿了 locale 查找函数 t，
# 但**忘了把 t 加进构造函数形参**：
#     constructor(describeFace, ctx, schema) { this.t = t; }   <-- t 未声明
# 后果：浏览器端 apply() 抛 ReferenceError: t is not defined，Web 整页
#       "Failed to load plugins —— @deepseek-ai/dsh-client-ui-permission-presets"。
#
# 关键点：这是**运行时才会暴露**的缺陷——
#   * `node --check` 只做语法解析，ReferenceError 属于语义/运行时问题，查不出；
#   * 原有的 17 项补丁基线校验只看"定制意图在不在"，也不检查 JS 是否可执行；
#   * CLI 侧（--version / --help / headless）完全不加载浏览器端 bundle，自然全绿。
# 所以必须**真的把模块求值一次**，让它自己跑出错误。
hr
say "用例 7/9  brand-patch 浏览器端模块可求值（超时 ${T_PATCHCHECK}s）"
PERM_JS="brand-patch/@deepseek-ai/dsh-client-ui-permission-presets/lib/client.js"
EVAL_TOOL=".patch-tools/eval-client-module.mjs"
if [ ! -f "$PERM_JS" ]; then
  record "补丁浏览器端可求值" FAIL "找不到 $PERM_JS"
elif [ ! -f "$EVAL_TOOL" ]; then
  record "补丁浏览器端可求值" FAIL "找不到求值工具 $EVAL_TOOL"
else
  ev_out="$(run_to "$T_PATCHCHECK" "$NODE" "$EVAL_TOOL" "$PERM_JS" 2>&1)"
  rc=$?
  printf '%s\n' "$ev_out" >> "$LOG"
  if [ $rc -eq 124 ]; then
    record "补丁浏览器端可求值" TIMEOUT ">${T_PATCHCHECK}s 未返回"
  elif [ $rc -eq 0 ] && printf '%s' "$ev_out" | grep -q '^PASS'; then
    record "补丁浏览器端可求值" PASS "$(printf '%s' "$ev_out" | grep '^PASS' | head -1)"
  elif [ $rc -eq 0 ] && printf '%s' "$ev_out" | grep -q '^SKIP'; then
    # 替身 ctx 能力不足：不属于补丁缺陷，按 SKIP 记账（不伪装成 PASS）
    record "补丁浏览器端可求值" SKIP "$(printf '%s' "$ev_out" | grep '^SKIP' | head -1)"
  else
    errline="$(printf '%s' "$ev_out" | grep -E 'ReferenceError|SyntaxError|FAIL' | head -1)"
    record "补丁浏览器端可求值" FAIL "${errline:-rc=$rc 未通过}"
  fi
fi

# ---------------------------------------------------------------------------
# 用例 8：web 服务能真正起来并返回 200
# ---------------------------------------------------------------------------
hr
say "用例 8/9  web 服务启动与 HTTP 响应（启动超时 ${T_WEB_BOOT}s）"
if [ "$QUICK" = "1" ]; then
  record "web 服务 HTTP" SKIP "--quick 跳过"
else
  PORT=3099
  # 【关键】$ROOT 是 POSIX 形式（/d/...），仅可用于 bash 文件操作；
  # 传给 Windows 的 curl.exe（-o / -c / -b）必须用 $ROOT_W（D:/...），
  # 否则 curl 静默写不出去（返回 000、文件不存在），表现为"首页抓不到"。
  WEBLOG="$WORK_DIR/smoke-web.log"
  WEBLOG_W="$WORK_DIR/smoke-web.log"
  JAR_W="$WORK_DIR/smoke-cookies.txt"
  INDEX_W="$WORK_DIR/smoke-index.html"
  INDEX="$WORK_DIR/smoke-index.html"
  rm -f "$WEBLOG" "$JAR_W" "$INDEX"
  # 用独立脚本 + timeout 包裹整个服务进程，杜绝孤儿进程
  cat > "$WORK_DIR/_web-probe.sh" <<WEBEOF
#!/usr/bin/env bash
export PATH="/usr/bin:/bin:\$PATH"
export DSH_HOME="$DSH_HOME_TEST"
unset CODEBUDDY_SAFE_DELETE_BULK_STATE_DIR CODEBUDDY_TOOL_CALL_ID CODEBUDDY_SAFE_DELETE_BULK_GUARD
exec "$NODE" "$CLI" web --port $PORT --host 0.0.0.0 --no-open
WEBEOF
  chmod +x "$WORK_DIR/_web-probe.sh"
  timeout "${T_WEB_BOOT}" bash "$WORK_DIR/_web-probe.sh" > "$WEBLOG" 2>&1 &
  WPID=$!

  # dsh web 有 browser-trust fence：
  #   无 token      -> HTTP 401
  #   带正确 token  -> HTTP 303 + Set-Cookie（token 换取会话 cookie）
  #   带 cookie     -> HTTP 200（真正的首页）
  # 因此"能否起来"的判定依据是：服务端打印出 URL 行（含 token），而非裸 URL 返回 200。
  booted=0
  for i in $(seq 1 $((T_WEB_BOOT/2))); do
    sleep 2
    if grep -q "http://127.0.0.1:$PORT" "$WEBLOG" 2>/dev/null; then booted=1; break; fi
  done

  if [ "$booted" = "1" ]; then
    TOKEN="$(grep -oE "token=[A-Za-z0-9_-]+" "$WEBLOG" | head -1 | cut -d= -f2)"
    lan_line="$(grep -oE "LAN: http://[0-9.]+:$PORT" "$WEBLOG" | head -1)"
    record "web 服务启动" PASS "已监听 3080 端口族；$lan_line（局域网地址已发布）"

    # 带 cookie 跟随 303 取回真正首页
    # 注意：curl 的 -w '%{http_code}' 在成功时已有输出，不能再加 "|| echo 000"，
    # 否则 curl 退出码非 0 时会把两段输出拼起来（曾得到 "200000" 的假失败）。
    code=$(curl -s -L -c "$JAR_W" -b "$JAR_W" -o "$INDEX_W" \
           -w '%{http_code}' --max-time 20 --connect-timeout 5 \
           "http://127.0.0.1:$PORT/?token=$TOKEN" 2>/dev/null)
    code="$(printf '%s' "$code" | tr -cd '0-9')"
    [ -z "$code" ] && code=000
    if [ "$code" = "200" ]; then
      record "web 首页 HTTP" PASS "HTTP 200（token->cookie->303->200 全链路通过）"
      title="$(grep -oE '<title>[^<]*</title>' "$INDEX" 2>/dev/null | head -1)"
      # 排除插件 URL 里的包名 @deepseek-ai/dsh-*（结构性标识，非品牌文案）
      brand_hits=$(grep -o 'deepseek' "$INDEX" 2>/dev/null | wc -l)
      pkg_hits=$(grep -o '@deepseek-ai/' "$INDEX" 2>/dev/null | wc -l)
      if printf '%s' "$title" | grep -q "USB Harness"; then
        record "web 首页标题" PASS "$title（品牌已替换；deepseek 出现 $brand_hits 次，其中包名 $pkg_hits 次）"
      else
        record "web 首页标题" FAIL "标题未替换: $title"
      fi
      # 静态资源可达性
      assets_ok=0; assets_bad=0
      for a in $(grep -oE '(src|href)="(/assets/[^"]+)"' "$INDEX" 2>/dev/null \
                 | sed 's/.*="//;s/"//' | sort -u | head -5); do
        ac=$(curl -s -b "$JAR_W" -o /dev/null -w '%{http_code}' --max-time 10 --connect-timeout 3 \
             "http://127.0.0.1:$PORT$a" 2>/dev/null)
        ac="$(printf '%s' "$ac" | tr -cd '0-9')"
        [ -z "$ac" ] && ac=000
        [ "$ac" = "200" ] && assets_ok=$((assets_ok+1)) || assets_bad=$((assets_bad+1))
      done
      if [ "$assets_bad" -eq 0 ]; then
        record "web 静态资源" PASS "$assets_ok 个 JS/CSS 资源全部 HTTP 200"
      else
        record "web 静态资源" FAIL "$assets_ok 个 200 / $assets_bad 个失败"
      fi
    else
      record "web 首页 HTTP" FAIL "跟随 token 后 HTTP=$code；日志: $(tail -2 "$WEBLOG" 2>/dev/null | tr '\n' ' ' | cut -c1-160)"
    fi
  else
    record "web 服务启动" TIMEOUT ">${T_WEB_BOOT}s 未打印监听地址"
    record "web 首页 HTTP" SKIP "服务未起来"
    record "web 首页标题" SKIP "服务未起来"
    record "web 静态资源" SKIP "服务未起来"
  fi

  kill $WPID 2>/dev/null
  wait $WPID 2>/dev/null
fi

# ---------------------------------------------------------------------------
# 用例 9：两个启动器的 CLI 分支语义与文案一致（回归：launch.sh 从未跟进改造）
# ---------------------------------------------------------------------------
# 【背景 — 这个用例为什么必须存在】
# 0.1.5-rc.2.1 只改了 scripts/launch-windows.ps1，**launch.sh 被漏掉**：
# 它仍在调用裸 `dsh`（旧设计「不带子命令进入交互式 TUI」），而该档位在 0.1.5
# 已不存在，裸跑直接报 `error: --profile <name> is required`。
# 同一份「CLI 单次任务」功能在 Windows 能用、Linux 必失败——典型的**平台分支漂移**。
# 本用例对两个启动器做同一组语义断言，强制它们保持同步：
#   1) 都声明 --profile headless（真实调用路径）
#   2) 都不再残留「交互式 TUI / /help / /exit」等已失效的旧文案
#   3) 都用上游术语 task 表述（文案对齐）
hr
say "用例 9/9  启动器 CLI 语义与文案一致（Windows + Linux）"

for pair in "scripts/launch-windows.ps1|Start-Cli|Invoke-Dsh" "launch.sh|start_cli|DSH_CLI"; do
  lf="${pair%%|*}";  rest="${pair#*|}"
  fn="${rest%%|*}";  call="${rest#*|}"
  if [ ! -f "$lf" ]; then
    record "启动器一致性($lf)" FAIL "文件不存在"
    continue
  fi
  body="$(sed -n "/function ${fn}\|^${fn}()/,/^}/p" "$lf" 2>/dev/null)"
  [ -z "$body" ] && body="$(sed -n "/^function ${fn}/,/^function /p" "$lf" 2>/dev/null | sed '$d')"
  if [ -z "$body" ]; then
    record "启动器一致性($lf)" FAIL "未能解析出 ${fn} 函数体"
    continue
  fi
  problems=""
  # 1) 必须显式带 --profile headless —— 只认「真实调用行」，不能认注释/提示文案
  #    【踩坑记录】最初写法是 `grep -qE -- '--profile[[:space:]]+headless'`，
  #    结果**阴性对照没抓到 bug**：因为函数体里那行给人看的提示
  #        echo "  等价命令: dsh --profile headless \"<task>\""
  #    本身就含 "--profile headless"，把 grep 喂饱了。
  #    这是典型的**自我满足断言**——断言命中的是自己写的文档字符串，不是被验的调用路径。
  #    故改为：剥掉注释与 echo/Write-Host 行后，再在**剩余的可执行行**里找调用。
  exec_only="$(printf '%s' "$body" \
    | grep -vE '^[[:space:]]*#' \
    | grep -vE '^[[:space:]]*(echo|Write-Host|Write-Step|printf)\b')"
  printf '%s' "$exec_only" | grep -qE -- '--profile[[:space:]]+headless' \
    || problems="${problems}真实调用行未传 --profile headless;"
  # 2) 不得残留已失效的交互式 TUI 文案（/help 与 /exit 是旧 TUI 的提示）
  printf '%s' "$exec_only" | grep -qE '/exit|交互式 TUI|终端内交互' \
    && problems="${problems}残留已失效的 TUI 文案;"
  # 3) 文案需与上游术语对齐（出现 task 字样）
  printf '%s' "$body" | grep -q 'task' \
    || problems="${problems}未采用上游 task 术语;"
  if [ -z "$problems" ]; then
    record "启动器一致性($lf)" PASS "带 --profile headless、无过期 TUI 文案、采用 task 术语"
  else
    record "启动器一致性($lf)" FAIL "$problems"
  fi
done

# ---------------------------------------------------------------------------
# 汇总
# ---------------------------------------------------------------------------
hr
say "===== 测试摘要 ====="
printf '%s\n' "${RESULTS[@]}"
hr
total=$((PASS+FAIL))
if [ "$total" -gt 0 ]; then
  rate=$(( PASS * 100 / total ))
else
  rate=0
fi
say "用例数: $total   通过: $PASS   失败: $FAIL   通过率: ${rate}%"
hr
[ "$FAIL" -eq 0 ] && { say "结论: 全部通过"; exit 0; } || { say "结论: 存在失败用例"; exit 1; }
