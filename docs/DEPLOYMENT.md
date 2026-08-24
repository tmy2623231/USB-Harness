# USB Harness — 部署指南

> 目标：把整个 `USB-Harness` 目录拷到 U 盘，插入任意 Windows 10/11 电脑，
> 双击 `launch.bat` 即可运行 USB Harness Web AI 助手，无需在宿主机安装任何东西。

## 0. 环境要求（宿主机）

| 项 | 要求 |
|----|------|
| 操作系统 | Windows 10/11（x64）。macOS/Linux 可作为扩展，见 §6 |
| 磁盘空间 | U 盘至少 **1.5 GB**（便携 Node ~50MB + dsh 依赖 ~300–500MB + 缓存），推荐 4 GB+ |
| 接口 | USB 3.0/3.1 或外部 SSD（USB 2.0 会导致模块导入明显变慢） |
| 网络 | 首次配置需联网下载 Node 与 dsh；日常对话需访问所配置的模型 API/Ollama |

**宿主机无需预装**：Node.js、npm、pnpm、Python 都不需要。

## 1. 首次准备（两种方式）

### 方式 A：在开发机上先跑一遍（推荐）

在联网的电脑上进入 `USB-Harness` 目录，PowerShell 执行：

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\setup-windows.ps1
```

脚本会依次完成：
1. 下载便携版 Node.js（22.x LTS，锁定 `v22.23.2`）→ 解压到 `.cache/runtimes/windows-x64/node/`
2. `npm install --prefix .cache/app @deepseek-ai/dsh` → 预装 dsh 及全部依赖到 `.cache/app/node_modules/`
3. 应用品牌补丁（去 DeepSeek 化）
4. 初始化 `data/dsh/` 并写入 `.ready.flag`

### 方式 B：直接用 launch.bat 触发按需初始化

`launch.bat` 检测到 `.cache` 未就绪时，会自动调用 `scripts\setup-windows.ps1` 完成首次配置，
然后进入交互菜单。

## 2. 日常启动

双击 **`launch.bat`**（交互菜单），或直接启动：

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\launch-windows.ps1 web
```

启动后：
- 默认监听 `0.0.0.0:3080`（本机 `http://127.0.0.1:3080`，局域网 `http://<本机IP>:3080`）
- 首次进入 Web UI：**设置 → 模型** 里添加自定义 OpenAI 兼容网关（baseURL + API Key + 模型），保存即生效
- 选择「工作区」（项目目录）后即可开始对话

### 启动器命令（launch-windows.ps1）

```powershell
.\scripts\launch-windows.ps1            # 交互菜单
.\scripts\launch-windows.ps1 web        # 直接启动 Web（默认 0.0.0.0:3080）
.\scripts\launch-windows.ps1 setup      # 重新配置 / 重装
.\scripts\launch-windows.ps1 status     # 查看状态
.\scripts\launch-windows.ps1 reset      # 重置（清空数据）
```

## 3. USB 文件系统：格式与权限兼容性（重点）

| 文件系统 | 支持度 | 说明 |
|----------|--------|------|
| **NTFS** | ✅ 完全支持 | 首选。支持符号链接，`dsh plugin`（pnpm）也可正常用 |
| **exFAT** | ✅ 核心功能支持 | 推荐用于跨 Win/mac 大文件。符号链接不可用时自动回退为目录复制（见下方说明），核心可用；但 `dsh plugin` 装社区插件需 pnpm，会受限 |
| **FAT32** | ✅ 核心功能支持 | 单文件 ≤ 4GB 一般够用；回退复制可运行，但不支持符号链接且性能差，不推荐 |

> **为什么 exFAT / FAT32 也能跑核心功能**：本项目通过 `brand-patch` 给 dsh 打了**复制回退补丁**——
> 启动时创建符号链接（junction）若因文件系统不支持而失败（FAT32/exFAT），自动改为**复制真实包目录**代替链接，
> 功能完全一致，仅多占约几百 MB 空间。因此核心功能不再依赖 NTFS。
> 只有需要安装社区插件的 `dsh plugin` 子命令（内部用 pnpm）仍要求 NTFS 或本地磁盘。

## 4. 端口与监听地址

- dsh Web 默认端口 **3080**，本项目默认监听 **`0.0.0.0`（全接口）**——本机 + 局域网均可访问。
- 已移除 dsh 对 `--host 0.0.0.0` 的安全拒绝（`dsh-web-app/lib/startup.js`），绑定 0.0.0.0 时
  dsh 会自动信任所有局域网 IP（`resolveLanTrust`），跨机器访问 `/api` 正常。
- `launch-windows.ps1` 启动前会探测 3080 是否被占用：若占用，自动选择下一个可用端口。
- ⚠️ **不要对公网开放**：Web UI 可执行命令、读写文件、管理凭据，0.0.0.0 仅用于可信局域网。

## 5. 路径 / 权限 / 安全

### 路径长度（Windows MAX_PATH）
- dsh 的 `node_modules` 层级较深，若 U 盘被挂载为超长盘符路径（如多层子目录），可能触发 260 字符限制。
- 建议：把 `USB-Harness` 放在**盘符根目录**（如 `E:\USB-Harness`），或开启长路径支持。
- `launch-windows.ps1` 会输出完整 `DSH_HOME` 路径，便于排查。

### 权限与凭据
- 凭据明文存放在 `data/dsh/.credentials.yaml`，U 盘丢失即泄露。**务必用 BitLocker
  （Windows 专业版）或 VeraCrypt 加密 U 盘**。
- 该文件已被 `.gitignore` 排除，切勿提交到任何仓库。

### 杀毒软件
- 便携 `node.exe` 及大量 `.js`/`.cmd` 可能被实时扫描拖慢启动，或极少数误报。
- 若启动异常缓慢，可将 U 盘目录加入杀软排除项（企业环境需遵循安全策略）。

### 从可移动盘执行
- 个别安全策略（如 AppLocker / WDAC / 组策略「禁止从可移动介质运行程序」）会阻止
  从 U 盘执行 `node.exe`。若被拦截，属**宿主机策略**而非本项目问题，需 IT 放行，
  或临时把目录复制到本地磁盘运行（`launch-windows.ps1` 支持在任意本地路径运行）。

## 6. Linux / macOS 运行

已内置 Linux/macOS 脚本（与 Windows 逻辑一致，自动下载对应平台的便携 Node）：

```bash
bash scripts/setup-unix.sh   # 首次配置：下载 Linux 便携 Node + 安装 dsh + 应用品牌补丁
bash launch.sh               # 启动（交互菜单；直接启动用 bash launch.sh web）
```

- 支持 `linux-x64` / `linux-arm64` / `darwin-x64` / `darwin-arm64`（自动识别）。
- 便携 Node 下载自 nodejs.org（`node-v22.23.2-<os>-<arch>.tar.xz`），解压到 `.cache/runtimes/<os>-<arch>/node/`。
- 凭据权限：Linux/macOS 建议 `chmod 600 data/dsh/.credentials.yaml`（Windows 无此概念）。
- 脚本已通过 `bash -n` 语法校验，且为 LF 换行（Windows 上编辑后勿转成 CRLF）。

## 7. 升级与清理

- **升级 dsh**：删除 `.cache/app/node_modules` 与 `.cache/app/package*.json`，重跑
  `scripts\setup-windows.ps1`（版本在脚本顶部 `$DshVersion` 可锁定）。
- **升级便携 Node**：删除 `.cache/runtimes/windows-x64/node`，重跑 setup（版本在 `$NodeVersion`）。
- **彻底重置**：删除 `data/dsh/` 会清空所有配置、密钥与会话——**操作前先备份**。
