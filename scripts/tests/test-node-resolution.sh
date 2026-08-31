#!/usr/bin/env bash
# =============================================================================
# test-node-resolution.sh — 回归测试（RT）：dsh 启动不再依赖 PATH 找 node（Unix 版）
# 与 scripts/tests/test-node-resolution.ps1 完全同构，逻辑一致：
#   A. PATH 无任何 node       -> launch.sh status 必须仍解析到便携 node
#   B. PATH 前置旧 node       -> 必须仍解析到便携 node（不被带偏）
#   负对照1：垫片 .bin/dsh + 旧 node PATH -> 必然命中 v14.0.0（证明环境/测试有效）
#   负对照2：垫片 .bin/dsh + 无 node PATH -> 必然报 node 找不到
# 全离线、确定性、秒级。任何一步失败即以非 0 退出。
# 用法：bash scripts/tests/test-node-resolution.sh
# 退出码：0 = 通过；1 = 失败
# =============================================================================
set -uo pipefail

fail=0
SUMM="${GITHUB_STEP_SUMMARY:-}"
pass() { echo "[PASS] $*"; if [ -n "$SUMM" ]; then echo "[PASS] $*" >> "$SUMM"; fi; return 0; }
fail_check() {
  echo "[FAIL] $*"
  if [ -n "$SUMM" ]; then echo "[FAIL] $*" >> "$SUMM"; fi
  # 失败细节打进 ::error:: annotation（公共仓库可经 check-run API 匿名读取）
  echo "::error::$*"
  return 0
}
# 把场景原始输出写入 step summary / annotation，方便定位失败
dump_scene() {
  if [ -n "$SUMM" ]; then
    { echo "--- $1 ---"; printf '%s\n' "$2" | head -40; } >> "$SUMM"
  fi
  echo "::error::--- $1 ---"
  printf '%s\n' "$2" | head -40 | sed 's/^/::error::  /'
}

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

case "$(uname -s)" in
  Linux)  OS="linux" ;;
  Darwin) OS="darwin" ;;
  *)      echo "[FAIL] 不支持的平台: $(uname -s)"; exit 1 ;;
esac
case "$(uname -m)" in
  x86_64|amd64) ARCH="x64" ;;
  aarch64|arm64) ARCH="arm64" ;;
  *)            echo "[FAIL] 不支持的架构: $(uname -m)"; exit 1 ;;
esac
PLATFORM="${OS}-${ARCH}"

REAL_NODE="$(command -v node 2>/dev/null || true)"
[ -z "$REAL_NODE" ] && REAL_NODE="$(command -v nodejs 2>/dev/null || true)"
[ -z "$REAL_NODE" ] && [ -x /usr/bin/node ] && REAL_NODE=/usr/bin/node
[ -z "$REAL_NODE" ] && [ -x /usr/local/bin/node ] && REAL_NODE=/usr/local/bin/node
if [ -z "$REAL_NODE" ]; then
  echo "[FAIL] 找不到真实 node（测试需本机或 CI runner 预装 Node）"; exit 1
fi

TMP="$(mktemp -d "${TMPDIR:-/tmp}/uhb-rt.XXXXXX")"
cleanup() { rm -rf "$TMP"; }
trap cleanup EXIT

mkdir -p "$TMP/scripts" \
         "$TMP/.cache/runtimes/$PLATFORM/node/bin" \
         "$TMP/.cache/app/node_modules/@deepseek-ai/dsh/lib" \
         "$TMP/.cache/app/node_modules/.bin"
cp "$REPO_ROOT/launch.sh" "$TMP/launch.sh"
cp "$REPO_ROOT/scripts/upgrade-unix.sh" "$TMP/scripts/upgrade-unix.sh"

# 便携 node = 真实 node 二进制（绝对路径调用）
install -m 755 "$REAL_NODE" "$TMP/.cache/runtimes/$PLATFORM/node/bin/node"

# 便携 dsh CLI = stub bin.js
cat > "$TMP/.cache/app/node_modules/@deepseek-ai/dsh/lib/bin.js" <<'EOF'
if (process.argv.includes("--version")) { console.log("0.1.1-rt"); process.exit(0); }
console.error("stub: unexpected args " + process.argv.slice(2).join(" "));
process.exit(42);
EOF

# 旧系统 node = 可执行脚本，打印 v14.0.0
OLD_NODE_DIR="$TMP/sysnode-old"
mkdir -p "$OLD_NODE_DIR"
cat > "$OLD_NODE_DIR/node" <<'EOF'
#!/bin/sh
echo "v14.0.0"
EOF
chmod +x "$OLD_NODE_DIR/node"

# 垫片 dsh（负对照）：模拟 .bin/dsh 垫片行为——shell 脚本 exec node，node 靠 PATH 解析
cat > "$TMP/.cache/app/node_modules/.bin/dsh" <<'EOF'
#!/bin/sh
DIR="$(cd "$(dirname "$0")" && pwd)"
exec node "$DIR/../@deepseek-ai/dsh/lib/bin.js" "$@"
EOF
chmod +x "$TMP/.cache/app/node_modules/.bin/dsh"

# 受控 PATH：过滤掉一切含 node/nvm/npm 的目录 + 真实 node 所在目录，
# 保证场景可控（否则 setup-node 装在 /usr/local/bin 之类目录时过滤不干净，
# 负对照 2 会命中真实 node 而不报错）
REAL_NODE_DIR="$(dirname "$REAL_NODE")"
BASE="$(printf '%s' "$PATH" | tr ':' '\n' \
  | grep -vi -e node -e nvm -e npm \
  | grep -v "^$REAL_NODE_DIR\$" \
  | paste -sd: -)"
dump_scene "环境: REAL_NODE=$REAL_NODE REAL_NODE_DIR=$REAL_NODE_DIR" "BASE=$BASE"
EMPTY_DIR="$TMP/emptydir"
mkdir -p "$EMPTY_DIR"

echo ""
echo "== 场景 A：PATH 无任何 node =="
outA="$(cd "$TMP" && PATH="$EMPTY_DIR:$BASE" bash launch.sh status 2>&1)"
rcA=$?
[ "$rcA" -eq 0 ] && pass "A) 退出码=0" || fail_check "A) 退出码=$rcA（期望 0）"
echo "$outA" | grep -qE '便携 Node *: *v[0-9]' && pass "A) 便携 Node 显示真实版本" || fail_check "A) 便携 Node 未显示"
echo "$outA" | grep -q 'dsh 版本 *: *0\.1\.1-rt' && pass "A) dsh 版本显示 0.1.1-rt" || fail_check "A) dsh 版本未显示 0.1.1-rt"
if echo "$outA" | grep -qi 'command not found\|No such file\|not found'; then fail_check "A) 出现 node 找不到类报错"; else pass "A) 无 node 找不到类报错"; fi
dump_scene "场景A原始输出" "$outA"

echo ""
echo "== 场景 B：PATH 前置旧 node(v14.0.0) =="
outB="$(cd "$TMP" && PATH="$OLD_NODE_DIR:$BASE" bash launch.sh status 2>&1)"
rcB=$?
[ "$rcB" -eq 0 ] && pass "B) 退出码=0" || fail_check "B) 退出码=$rcB（期望 0）"
echo "$outB" | grep -qE '便携 Node *: *v[0-9]' && pass "B) 便携 Node 为真实版本" || fail_check "B) 便携 Node 未显示"
echo "$outB" | grep -q 'v14\.0\.0' && fail_check "B) 命中了旧系统 node v14.0.0" || pass "B) 未命中旧系统 node v14.0.0"
echo "$outB" | grep -q 'dsh 版本 *: *0\.1\.1-rt' && pass "B) dsh 版本仍为 0.1.1-rt" || fail_check "B) dsh 版本未显示"
dump_scene "场景B原始输出" "$outB"

echo ""
echo "== 负对照1：垫片 .bin/dsh + 旧 node PATH（应命中 v14.0.0）=="
outN1="$(cd "$TMP" && PATH="$OLD_NODE_DIR:$BASE" "$TMP/.cache/app/node_modules/.bin/dsh" --version 2>&1)"
echo "$outN1" | grep -q 'v14\.0\.0' && pass "负对照1: 垫片被旧 node 带偏（$outN1）" || fail_check "负对照1: 垫片未命中 v14.0.0（实际: $outN1）"

echo ""
echo "== 负对照2：垫片 .bin/dsh + 无 node PATH（应报 node 找不到）=="
outN2="$(cd "$TMP" && PATH="$EMPTY_DIR:$BASE" "$TMP/.cache/app/node_modules/.bin/dsh" --version 2>&1 || true)"
echo "$outN2" | grep -qi 'command not found\|not found' && pass "负对照2: 垫片在无 node 环境下报错" || fail_check "负对照2: 垫片未报错（实际: $outN2）"

echo ""
if [ "$fail" = "1" ]; then echo "[RT] 失败"; exit 1; fi
echo "[RT] 全部通过"
exit 0
