#!/usr/bin/env bash
# =============================================================================
# setup-unix.sh — USB Harness 首次配置（Linux/macOS）
# 职责：下载便携 Node.js → 安装 @deepseek-ai/dsh → 应用品牌补丁 → 初始化数据目录
# 用法：bash scripts/setup-unix.sh
#       （launch.sh 首次运行时会自动调用本脚本）
# =============================================================================
set -euo pipefail

# 项目根目录 = scripts/ 的上一级
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NODE_VERSION="${NODE_VERSION:-22.23.2}"
DSH_VERSION="${DSH_VERSION:-0.1.5-rc.2}"

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
NODE_NPM="$NODE_DIR/bin/npm"
APP_PREFIX="$ROOT/.cache/app"
DSH_BIN="$APP_PREFIX/node_modules/.bin/dsh"
DSH_HOME_DIR="$ROOT/data/dsh"
NPM_CACHE="$ROOT/.cache/npm-cache"
READY_FLAG="$ROOT/.ready.flag"
# 预置/下载的 Node tarball 落点（此前被引用但从未赋值，set -u 下 Unix 全新安装必崩）
NODE_TARBALL="$ROOT/.cache/downloads/node-v${NODE_VERSION}-${OS}-${ARCH}.tar.xz"

mkdir -p "$NODE_DIR" "$APP_PREFIX" "$DSH_HOME_DIR" "$NPM_CACHE" "$ROOT/.cache/downloads"

echo ""
echo "============================================"
echo "   USB Harness 首次配置"
echo "============================================"
echo "项目根目录 : $ROOT"
echo "平台/架构   : $PLATFORM"
echo "便携 Node   : $NODE_VERSION"
echo "dsh 版本    : $DSH_VERSION"
echo ""

# ---------------------------------------------------------------------------
# 1) 便携 Node.js（优先 U 盘预置包 → 中国镜像 npmmirror → 官方源）
# ---------------------------------------------------------------------------
if [ -x "$NODE_BIN" ]; then
  echo "[1/3] 便携 Node 已存在，跳过。"
else
  echo "[1/3] 准备便携 Node.js $NODE_VERSION ($PLATFORM) ..."
  if [ -f "$NODE_TARBALL" ]; then
    echo "      使用 U 盘预置安装包: $NODE_TARBALL"
    TARBALL="$NODE_TARBALL"
  else
    echo "      下载便携 Node.js（中国镜像 npmmirror 优先）..."
    BASE="node-v${NODE_VERSION}-${OS}-${ARCH}.tar.xz"
    DOWNLOADED=0
    for URL in "https://npmmirror.com/mirrors/node/v${NODE_VERSION}/$BASE" "https://nodejs.org/dist/v${NODE_VERSION}/$BASE"; do
      if curl -L --fail --retry 3 -o "$NODE_TARBALL" "$URL"; then
        DOWNLOADED=1
        break
      else
        echo "      下载失败，尝试下一个源 ..."
      fi
    done
    if [ "$DOWNLOADED" = "0" ]; then
      echo "Node.js 下载失败。可手动下载 $BASE 放到 .cache/downloads/ 后重试（离线安装）。" >&2
      exit 1
    fi
    TARBALL="$NODE_TARBALL"
  fi
  echo "      解压到 $NODE_DIR ..."
  mkdir -p "$NODE_DIR"
  tar -xJf "$TARBALL" -C "$NODE_DIR" --strip-components=1
  "$NODE_BIN" -v
fi

# ---------------------------------------------------------------------------
# 2) 安装 @deepseek-ai/dsh
# ---------------------------------------------------------------------------
if [ -x "$DSH_BIN" ]; then
  echo "[2/3] dsh 已安装，跳过。"
else
  echo "[2/3] 用便携 npm 安装 @deepseek-ai/dsh@$DSH_VERSION ..."
  echo "      这会下载完整依赖树，首次约 3-8 分钟，请耐心等待。"
  echo "      使用 --legacy-peer-deps 规避 npm 解析卡死；中国镜像（npmmirror）优先。"
  export PATH="$NODE_DIR/bin:$PATH"
  if ! "$NODE_NPM" install --prefix "$APP_PREFIX" "@deepseek-ai/dsh@$DSH_VERSION" \
    --no-audit --no-fund --fetch-retries=5 --legacy-peer-deps --cache "$NPM_CACHE" \
    --registry=https://registry.npmmirror.com; then
    echo "      中国镜像失败，回退官方 npm 源 ..."
    "$NODE_NPM" install --prefix "$APP_PREFIX" "@deepseek-ai/dsh@$DSH_VERSION" \
      --no-audit --no-fund --fetch-retries=5 --legacy-peer-deps --cache "$NPM_CACHE"
  fi

  # 已知坑位：多个 dsh 子包把彼此声明为 peerDependencies，主包 bundle 未包含，
  # --legacy-peer-deps 会跳过它们，导致启动报 ERR_MODULE_NOT_FOUND。显式补齐。
  # 列表按 0.1.5-rc.2 实测结果重定：对安装树里全部 @deepseek-ai/* 的 import 说明符
  # 逐个做模块解析，凡解析不到的即为缺失项（详见 docs/TROUBLESHOOTING.md）。
  # 重定后多数旧条目已随主包打进依赖树，无需再列；缺失项由 19 个变为 26 个。
  echo "[2.5] 补齐 dsh 缺失的 peer 依赖包（已知 26 个）..."
  PEERS=(
    # --- 仅以 peerDependencies 声明、主包未纳入依赖树的子包（必须补） ---
    "@deepseek-ai/dsh-anonymous-user-id@$DSH_VERSION" "@deepseek-ai/dsh-attachment@$DSH_VERSION"
    "@deepseek-ai/dsh-bash-local@$DSH_VERSION" "@deepseek-ai/dsh-client-store@$DSH_VERSION"
    "@deepseek-ai/dsh-client-ui-dockkit@$DSH_VERSION" "@deepseek-ai/dsh-client-ui-primitives@$DSH_VERSION"
    "@deepseek-ai/dsh-client-ui-slots@$DSH_VERSION" "@deepseek-ai/dsh-code-runtime@$DSH_VERSION"
    "@deepseek-ai/dsh-compaction@$DSH_VERSION" "@deepseek-ai/dsh-fs@$DSH_VERSION"
    "@deepseek-ai/dsh-hook-protocol@$DSH_VERSION" "@deepseek-ai/dsh-jobs@$DSH_VERSION"
    "@deepseek-ai/dsh-output-retention@$DSH_VERSION" "@deepseek-ai/dsh-sandbox@$DSH_VERSION"
    "@deepseek-ai/dsh-sdk-protocol@$DSH_VERSION" "@deepseek-ai/dsh-session-persistence@$DSH_VERSION"
    "@deepseek-ai/dsh-session-query@$DSH_VERSION" "@deepseek-ai/dsh-session-telemetry@$DSH_VERSION"
    "@deepseek-ai/dsh-session-title-llm@$DSH_VERSION" "@deepseek-ai/dsh-settings@$DSH_VERSION"
    "@deepseek-ai/dsh-shell@$DSH_VERSION" "@deepseek-ai/dsh-spill@$DSH_VERSION"
    "@deepseek-ai/dsh-subagent-in-process-driver@$DSH_VERSION" "@deepseek-ai/dsh-util-time@$DSH_VERSION"
    "@deepseek-ai/dsh-util-workspace-path@$DSH_VERSION" "@deepseek-ai/dsh-workflow@$DSH_VERSION"
    # --- 主包依赖树里已存在，但版本号独立于 dsh 的第三方包 ---
    '@deepseek-ai/cordis-plugin-group@^1.0.1' '@cfworker/json-schema@^4.1.1'
    # react 必须锁 18.x：dsh-web-frontend 依赖 react@^18.2.0，用 latest 会拉到 19.x（跨大版本不兼容）
    'react@^18.3.1' 'react-dom@^18.3.1' 'bufferutil@^4.0.1' 'utf-8-validate@^5.0.2'
    '@types/react@^18.3.12'
  )
  if ! "$NODE_NPM" install --prefix "$APP_PREFIX" "${PEERS[@]}" --no-audit --no-fund --legacy-peer-deps --cache "$NPM_CACHE" --registry=https://registry.npmmirror.com; then
    echo "      peer 补齐镜像失败，回退官方源 ..."
    "$NODE_NPM" install --prefix "$APP_PREFIX" "${PEERS[@]}" --no-audit --no-fund --legacy-peer-deps --cache "$NPM_CACHE"
  fi
fi

# ---------------------------------------------------------------------------
# 3) 品牌补丁 + 就绪标记
# ---------------------------------------------------------------------------
echo "[3/3] 应用 USB Harness 品牌补丁（去 DeepSeek 化）..."
if [ -d "$ROOT/brand-patch/@deepseek-ai" ]; then
  cp -r "$ROOT/brand-patch/@deepseek-ai/." "$APP_PREFIX/node_modules/@deepseek-ai/"
  echo "      品牌补丁已应用。"
else
  echo "      未找到 brand-patch，跳过。"
fi

# 就绪标记：harness 行仅当包根存在 HARNESS_VERSION（CI 打包写入）时追加，向后兼容旧三行格式；
# 临时文件 + mv 原子写，避免写一半断电留半行
{
  printf 'node=%s\ndsh=%s\n' "$NODE_VERSION" "$DSH_VERSION"
  if [ -f "$ROOT/HARNESS_VERSION" ]; then
    printf 'harness=%s\n' "$(tr -d '\r\n' < "$ROOT/HARNESS_VERSION")"
  fi
  printf 'created=%s\n' "$(date -Iseconds)"
} > "$READY_FLAG.tmp" && mv -f "$READY_FLAG.tmp" "$READY_FLAG"

echo ""
echo "============================================"
echo "   配置完成！"
echo "============================================"
echo "下一步：运行 bash launch.sh 启动。"
echo "DSH_HOME 将指向: $DSH_HOME_DIR"
echo ""
