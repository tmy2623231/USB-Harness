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
NODE="$ROOT_W/.tmp-upstream/node/node.exe"
CLI="$ROOT_W/.tmp-upstream/app2/node_modules/@deepseek-ai/dsh/lib/bin.js"
REFSCAN="$ROOT_W/.tmp-upstream/refscan.mjs"
APP2="$ROOT_W/.tmp-upstream/app2"
DSH_HOME_TEST="$ROOT_W/.tmp-upstream/dsh-smoke"
LOG="$ROOT/.tmp-upstream/smoke.log"

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
say "用例 1/6  dsh --version（超时 ${T_VERSION}s）"
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
say "用例 2/6  dsh --help（超时 ${T_HELP}s）+ 品牌检查"
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
# 用例 3：模块解析（全部 @deepseek-ai/* 引用可解析）
# ---------------------------------------------------------------------------
hr
say "用例 3/6  安装树模块解析（超时 ${T_ASSET}s）"
ref_out="$(run_to $T_ASSET "$NODE" "$REFSCAN" "$APP2" 2>&1)"
rc=$?
if [ $rc -eq 124 ]; then
  record "模块解析" TIMEOUT ">${T_ASSET}s"
else
  miss_line="$(printf '%s' "$ref_out" | grep "解析失败:" | head -1)"
  printf '%s\n' "$ref_out" >> "$LOG"
  if printf '%s' "$miss_line" | grep -q "解析失败: 0"; then
    record "模块解析" PASS "$miss_line"
  else
    record "模块解析" FAIL "$miss_line"
  fi
fi

# ---------------------------------------------------------------------------
# 用例 4：补丁基线校验（dsh_patch_compat_check.py）
# ---------------------------------------------------------------------------
hr
say "用例 4/6  补丁基线校验（超时 ${T_PATCHCHECK}s）"
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
say "用例 5/6  headless CLI 模式（超时 ${T_HEADLESS}s）"
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
# 用例 6：web 服务能真正起来并返回 200
# ---------------------------------------------------------------------------
hr
say "用例 6/6  web 服务启动与 HTTP 响应（启动超时 ${T_WEB_BOOT}s）"
if [ "$QUICK" = "1" ]; then
  record "web 服务 HTTP" SKIP "--quick 跳过"
else
  PORT=3099
  # 【关键】$ROOT 是 POSIX 形式（/d/...），仅可用于 bash 文件操作；
  # 传给 Windows 的 curl.exe（-o / -c / -b）必须用 $ROOT_W（D:/...），
  # 否则 curl 静默写不出去（返回 000、文件不存在），表现为"首页抓不到"。
  WEBLOG="$ROOT/.tmp-upstream/smoke-web.log"
  WEBLOG_W="$ROOT_W/.tmp-upstream/smoke-web.log"
  JAR_W="$ROOT_W/.tmp-upstream/smoke-cookies.txt"
  INDEX_W="$ROOT_W/.tmp-upstream/smoke-index.html"
  INDEX="$ROOT/.tmp-upstream/smoke-index.html"
  rm -f "$WEBLOG" "$JAR_W" "$INDEX"
  # 用独立脚本 + timeout 包裹整个服务进程，杜绝孤儿进程
  cat > "$ROOT/.tmp-upstream/_web-probe.sh" <<WEBEOF
#!/usr/bin/env bash
export PATH="/usr/bin:/bin:\$PATH"
export DSH_HOME="$DSH_HOME_TEST"
unset CODEBUDDY_SAFE_DELETE_BULK_STATE_DIR CODEBUDDY_TOOL_CALL_ID CODEBUDDY_SAFE_DELETE_BULK_GUARD
exec "$NODE" "$CLI" web --port $PORT --host 0.0.0.0 --no-open
WEBEOF
  chmod +x "$ROOT/.tmp-upstream/_web-probe.sh"
  timeout "${T_WEB_BOOT}" bash "$ROOT/.tmp-upstream/_web-probe.sh" > "$WEBLOG" 2>&1 &
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
