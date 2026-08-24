# USB Harness — 兼容性矩阵

> 记录「USB Harness」对 deepseek-harness (dsh) 能力的覆盖情况，以及各环境下的兼容边界。
> 原则：核心能力来自官方预编译包，**未做裁剪改写**；边界仅来自 U 盘/宿主机约束。

## 1. dsh 能力覆盖

| dsh 能力 | 覆盖 | 说明 |
|----------|------|------|
| Web UI（网页界面） | ✅ 100% | 由 `@deepseek-ai/dsh` 内置 `dsh-web-app` 提供，默认 `127.0.0.1:3080` |
| 实时对话 / 流式输出 | ✅ 100% | 官方实现，未改动 |
| 模型加载（DeepSeek 官方 / OpenAI 兼容 / Ollama） | ✅ 100% | 通过 Web UI「设置→模型」配置 |
| headless 无头单次任务 | ✅ 100% | `dsh --profile headless "任务"`，脚本已封装 `-Headless` |
| 工具/插件体系（文件、Shell、Web 搜索、MCP 等） | ✅ 100% | 全部随 npm 包携带 |
| 会话持久化（SQLite） | ✅ 100% | 存于 `data/dsh/storages`，随盘 |
| 凭据/配置持久化 | ✅ 100% | 存于 `data/dsh/.credentials.yaml` 与 `settings.yaml` |
| **社区插件安装（`dsh plugin`）** | ⚠️ 部分 | 依赖 pnpm；仅 NTFS/本地磁盘可用，exFAT/FAT32 受限 |

## 2. 文件系统兼容

| 文件系统 | 核心运行 | `dsh plugin`（pnpm） | 备注 |
|----------|----------|----------------------|------|
| NTFS | ✅ | ✅ | 首选，全功能（链接方式最省空间） |
| exFAT | ✅ | ⚠️ 受限 | 跨平台大文件友好；符号链接不可用时自动回退为目录复制，核心照常可用；装插件建议改 NTFS |
| FAT32 | ✅ | ❌ | 回退复制可运行；受单文件 4GB 限制 + 性能差，不推荐 |

## 3. 运行环境兼容

| 项 | 状态 | 依据 |
|----|------|------|
| Node.js 22.x LTS（≥22.19） | ✅ 推荐 | dsh 要求 `^22.19.0 \|\| >=24.0.0`，本项目锁定 22.23.2 |
| Node.js 24.x（≥24.0） | ✅ 兼容 | 同一 `engines` 范围 |
| Node.js 23.x | ❌ 不支持 | dsh 官方明确排除 23 |
| Windows 10/11 x64 | ✅ 交付目标 | — |
| macOS / Linux | 🔧 可扩展 | 需另行下载对应 Node 构建，脚本逻辑一致 |

## 4. 已验证项（本地实测，2026-08-21）

| 验证项 | 结果 | 方法 |
|--------|------|------|
| `@deepseek-ai/dsh` 包存在且可安装 | ✅ v0.1.1-rc.1 | `npm view` + 本地 `npm install` |
| dsh CLI 启动器参数（`--profile`/`--patch`/`--dump-config`/`web`/`plugin`） | ✅ | 读取 `lib/bin.js` 源码 |
| `DSH_HOME` 环境变量可重定向 | ✅ 官方支持 | 官方文档/第三方实测一致 |
| 默认端口 3080、仅监听 loopback | ✅ | 官方 README |
| `--no-open` 标志 | ✅ | 官方 README |
| Node 22.x 最新 LTS 版本号 | ✅ v22.23.2 (Jod) | `nodejs.org/dist/index.json` |
| **实测：E: U 盘全流程安装** | ✅ 535MB | `npm install`（430 包，6 分钟） |
| **实测：`dsh --version`** | ✅ 0.1.1-rc.1 | 便携 Node 22.23.2 运行 |
| **实测：`dsh web` 启动** | ✅ HTTP 200 | `--port 3080 --no-open`，真实服务响应 |
| **实测：web 子命令参数** | ✅ | `--port`（含 0=自动选端口）/`--host`/`--no-open` 均确认 |

### 已知坑位（2026-08-21 实装记录）

1. **npm 大依赖树解析卡死**（20 分钟纯 CPU 空转、零网络）→ 需加 `--legacy-peer-deps`。
2. **dsh rc.1 发布内部不一致**：多个包的 peerDependencies 指向 `0.1.1-rc.2` 子包，
   rc.1 bundle 未包含 → `--legacy-peer-deps` 会跳过这些 peer，启动报
   `ERR_MODULE_NOT_FOUND`。**修复**：显式补齐 25 个缺失 peer 包（见 `scripts/setup-windows.ps1`
   注释与下文）。
3. **npm 缓存 EPERM**：强杀进程残留的缓存锁会触发 `EPERM` 打不开缓存文件 →
   `scripts/setup-windows.ps1` 已把 npm 缓存移入项目内 `.cache/npm-cache`（随盘，避开系统盘）。
4. **PowerShell `$Host` 是只读自动变量**：早期 `start.ps1` 曾把监听地址参数命名为 `-Host`
   导致脚本无法运行，已改用 `0.0.0.0` 直通 dsh `--host`（见 `scripts/launch-windows.ps1`）。

> ⚠️ dsh 官方变更声明：官方明确「THERE WILL BE COMPATIBILITY-BREAKING CHANGES」。
> 配置字段、端口、目录名（如 `storages` vs `sessions`）可能随版本变化。升级后请以
> 当前版本文档为准；本项目锁定版本号以降低风险。

## 5. 边界与风险

| 风险 | 等级 | 缓解 |
|------|------|------|
| dsh 预发布版本破坏性变更 | 中 | 锁定 `@deepseek-ai/dsh` 与 Node 版本号；升级走独立脚本 |
| U 盘丢失 → 凭据泄露 | 高 | BitLocker/VeraCrypt 加密 U 盘 |
| 宿主机禁止从可移动盘执行 | 低 | 复制到本地磁盘运行（脚本已支持） |
| exFAT 装社区插件失败 | 低 | 改用 NTFS，或本地磁盘装好再拷回 |
| 端口 3080 冲突 | 低 | `launch-windows.ps1` 自动探测并换端口 |
