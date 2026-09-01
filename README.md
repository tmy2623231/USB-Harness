<div align="center">

# 🚀 USB Harness — 即插即用的 U 盘 AI 助手

**deepseek-harness 便携式变体 · 免安装 LLM Web UI · 离线可用 · 中国网络适配**

<img src="docs/banner.svg" alt="USB Harness banner" width="800"/>

[![License](https://img.shields.io/github/license/tmy2623231/USB-Harness?color=blue)](LICENSE)
[![Release](https://img.shields.io/github/v/release/tmy2623231/USB-Harness?color=orange&label=latest)](https://github.com/tmy2623231/USB-Harness/releases/latest)
[![Downloads](https://img.shields.io/github/downloads/tmy2623231/USB-Harness/total?color=green)](https://github.com/tmy2623231/USB-Harness/releases/latest)
[![Stars](https://img.shields.io/github/stars/tmy2623231/USB-Harness?color=yellow)](https://github.com/tmy2623231/USB-Harness)
[![Platform](https://img.shields.io/badge/platform-Windows%20%7C%20Linux%20%7C%20macOS-blueviolet)](launch.sh)
[![dsh](https://img.shields.io/badge/dsh-0.1.1--rc.2-purple)](https://github.com/deepseek-ai/deepseek-harness)
[![PRs Welcome](https://img.shields.io/badge/PRs-welcome-brightgreen)](https://github.com/tmy2623231/USB-Harness/pulls)

</div>

> **一句话**：把 [DeepSeek Harness](https://github.com/deepseek-ai/deepseek-harness) 的全部 AI 能力装进一个 **U 盘**——
> 插上即用，免安装、零宿主机污染、数据随盘，支持任意 **OpenAI 兼容模型网关**（Ollama / 阿里云百炼 / OpenRouter / vLLM / 本地模型）。

---

## 🎯 适合谁

| 场景 | 为什么选它 |
|------|-----------|
| **不想折腾环境的开发者 / 学生** | 免装 Node、npm、Python，下载解压双击即用 |
| **离线 / 内网环境** | 完整包自带运行时（便携 Node + dsh + 离线包），不联网也能启动 |
| **多台电脑切换** | U 盘一插，配置、会话、模型全带走（数据随盘） |
| **局域网共享** | 一台电脑起服务，手机 / 平板 / 同事浏览器直接访问 |
| **国内网络用户** | Node 下载、npm 安装全程中国镜像优先，失败自动回退官方源 |

## 🚀 下载（推荐：下载即用）

**完整包已含运行时（便携 Node + dsh 依赖 + 离线安装包），解压即可使用，无需联网安装：**

> ## 👉 [前往 Releases 页下载最新完整包](https://github.com/tmy2623231/USB-Harness/releases/latest)

| 方式 | 说明 |
|------|------|
| **Releases 完整包**（推荐） | 下载 `USB-Harness-with-runtime.zip`（约 136 MB）→ 解压 → 双击 `launch.bat` → 直接用 |
| 源码 ZIP / git clone | 仅源码（不含运行时），首次启动需联网安装一次（走中国镜像 + 离线包） |

**完整包使用步骤**：

1. 在 [Releases 页](https://github.com/tmy2623231/USB-Harness/releases/latest) 下载 `USB-Harness-with-runtime.zip`
2. 解压到 U 盘（推荐 NTFS 或 exFAT、≥4GB 空间，详见下方「U 盘格式要求」）
3. Windows 双击 **`launch.bat`**；Linux/macOS 执行 **`bash launch.sh`**
4. 浏览器自动打开 `http://127.0.0.1:3080`，在「设置 → 模型」配置自定义 OpenAI 兼容网关即可使用

---

## 💾 U 盘格式要求（推荐 NTFS；exFAT / FAT32 也能跑）

> **推荐 NTFS，但不再强制。** dsh 在文件系统不支持符号链接（如 FAT32 / exFAT）时，
> 会自动回退为**真实目录复制**，因此三种常见格式均可正常运行。

**机制**：dsh 启动时会在 `data/dsh/profiles/node_modules/` 下创建符号链接（Windows 上为 junction）
指向 `.cache/app/node_modules/` 中的真实包（模块回退机制）。NTFS 原生支持这类链接；
若文件系统不支持（FAT32/exFAT），启动器自动**复制真实包目录**代替链接——功能完全一致，
代价是 `profiles` 目录多占约几百 MB 空间（随包数量而定）。

### 三种常见格式对比

| 格式 | 支持链接 | 单文件上限 | 跨平台兼容性 | 本项目 |
|------|---------|-----------|-------------|--------|
| **NTFS** | 支持（junction） | 无（最大 16EB） | Windows 原生读写；macOS 默认只读（需 Paragon / Tuxera 驱动）；Linux 可读写（ntfs-3g） | ✅ 首选（链接方式最省空间、性能最好） |
| **exFAT** | 不支持 → 自动回退复制 | 无（最大 128PB） | Windows / macOS 原生读写；Linux 5.4+ 内核支持 | ✅ 推荐（跨平台读写最佳 + 回退兜底） |
| **FAT32** | 不支持 → 自动回退复制 | **4GB**（单个文件超过 4GB 无法存储） | 全平台（旧设备兼容性最好） | ✅ 可用（回退复制；受 4GB 限制） |

> **选择建议**
> - **Windows 为主** → NTFS：链接方式最省空间，`dsh plugin` 装社区插件也正常
> - **需要 macOS / Windows 跨平台读写** → exFAT：macOS 上 NTFS 默认只读，exFAT 才是真跨平台；
>   回退机制保证核心功能照常运行
> - **仅兼容老设备** → FAT32：能跑，但受单文件 4GB 限制，不建议

### 格式化 / 转换步骤（Windows）

**方法一：格式化（新 U 盘或已备份数据）**
1. 备份 U 盘内所有数据（格式化会清空）
2. 资源管理器右键 U 盘 → **格式化**
3. 文件系统选择 **NTFS**（或 exFAT）→ 分配单元大小保持默认 → 开始
4. 完成后把 USB Harness 目录复制进去即可

**方法二：无损转换（U 盘已有数据，仅限转 NTFS）**
1. 先运行 `chkdsk X: /f`（X 为盘符）检查并修复文件系统错误
2. 若卷标为空，先设置：`label X: USB-Harness`
3. 执行转换：`convert X: /fs:ntfs`（无需格式化，数据保留）
4. 若提示卷被占用，关闭占用程序后重试，或按提示安排在下次重启时转换

### 注意事项

- **转换 / 格式化前务必备份数据**，并先跑 `chkdsk X: /f`——文件系统有坏块时转换可能中途报错
  （如 `数据错误(循环冗余检查)`），虽然多数情况下仍能完成转换，但风险不可控
- 在 exFAT / FAT32 上运行会启用**复制回退**：`data\dsh\profiles\node_modules\` 下是真实包副本而非链接，
  多占约几百 MB 空间；若之前残留了空目录（如 `@deepseek-ai`），dsh 会自动重建，无需手动清理
- **`dsh plugin`（装社区插件）仍需要符号链接**（内部用 pnpm），仅 NTFS 或本地磁盘可用；
  exFAT / FAT32 上装插件会失败，属已知限制
- U 盘建议 USB 3.0+、容量 ≥ 8GB（完整包约 136MB，解压后约 500MB，运行期还会产生日志与会话数据）

---

## ✨ 功能特性

- ✅ **100% dsh 能力**：Web UI、实时对话、流式输出、模型加载、headless、工具/插件、MCP、权限模式
- ✅ **免安装便携**：便携 Node.js + 预置依赖，宿主机无需 Node/npm/Python
- ✅ **跨平台**：Windows（`launch.bat`）+ Linux/macOS（`launch.sh`），一套目录双端运行
- ✅ **交互式启动器**：中文菜单（启动 / 重置 / 退出），首启自动安装
- ✅ **数据随盘**：`DSH_HOME` 重定向到 `data/dsh/`，密钥/配置/会话全部留在 U 盘
- ✅ **零宿主机污染**：不写注册表、不改系统环境变量
- ✅ **中国网络适配**：Node 下载优先 npmmirror 镜像、npm 用 `registry.npmmirror.com`，失败自动回退官方源
- ✅ **U 盘离线安装包**：`.cache/downloads/` 内置 Node 安装包，重装不依赖网络
- ✅ **软重置**：清配置数据但保留运行环境，重置后无需重新下载
- ✅ **默认监听 0.0.0.0:3080**：本机 + 局域网可访问；端口占用自动顺延
- ✅ **格式兼容**：符号链接不可用时（FAT32/exFAT）自动回退为目录复制，NTFS / exFAT / FAT32 均可运行
- ✅ **图片输入（多模态）**：`read_image` 可直接把 PNG/JPEG/WebP/GIF 交给视觉模型；rc.2 起统一走规范化存储 + 回退管线，大图与多图不再轻易超限（固件/网关侧仍以目标网关自身的限制为准）

## 快速开始

### 1. 拷贝到 U 盘

**方式一（推荐）**：从 [Releases 页](https://github.com/tmy2623231/USB-Harness/releases/latest) 下载
`USB-Harness-with-runtime.zip` 完整包（含运行时），解压后拷贝到 U 盘即可，**无需联网安装**。

**方式二（源码）**：用「Code → Download ZIP」下载源码（或 `git clone`），把整个目录复制到 U 盘
（推荐 NTFS 或 exFAT、USB 3.0+、≥4GB 空间，见「U 盘格式要求」）。源码不含运行时，首次启动会提示联网安装一次。

> **说明**：GitHub 下载的 ZIP 解压后文件夹名是 `USB-Harness-main`（GitHub 的
> `仓库名-分支名` 固定命名，属正常现象），把它重命名为 `USB-Harness` 即可，不改也不影响使用。

### 2. 启动

**Windows**：双击 **`launch.bat`**。
**Linux/macOS**：`bash launch.sh`。

首次运行会自动检测并安装运行环境（优先使用 U 盘离线包 + 中国镜像）。
启动菜单：

```
[1] 启动 Web 界面
[2] 检查更新（程序与 dsh 版本）
[3] 重置（清配置数据，保留运行环境，无需下载）
[4] 退出
```

默认监听 `http://0.0.0.0:3080`（本机 `http://127.0.0.1:3080`，局域网 `http://<本机IP>:3080`）。

### 3. 配置模型（进入 Web UI 后）

**设置 → 模型 → 添加自定义提供方**，填入：

- **API 地址**：OpenAI 兼容网关地址
- **API 密钥**：网关提供的密钥
- **模型目录**：点击「获取可用模型」自动拉取，或手动添加模型 ID

保存后在对话页右上角选择模型即可开始使用。全新安装时欢迎页点「继续」会**直接弹出添加自定义模型表单**。

### 4. 选择工作区

会话基于工作区（项目目录）运行，在 Web 界面中自行选择。会话中读写文件、执行命令都以所选工作区为根。

## 目录结构

```
USB-Harness/
├── launch.bat / launch.sh     # 一键启动入口（交互菜单，首启自动安装）
├── HARNESS_VERSION            # 程序版本标记（Release 打包时写入）
├── .ready.flag                # 就绪标记（node=/dsh=/harness=/created=）
├── scripts/
│   ├── launch-windows.ps1     # Windows 启动器（中文菜单）
│   ├── setup-windows.ps1      # Windows 首次配置（下载/离线 Node + 安装 dsh + 品牌补丁）
│   ├── setup-unix.sh          # Linux/macOS 首次配置
│   ├── upgrade-windows.ps1    # Windows 检查更新/升级（自动回滚，不动 data/）
│   ├── upgrade-unix.sh        # Linux/macOS 检查更新/升级
│   ├── reset-windows.ps1      # Windows 重置（软重置/完全重置 -Full）
│   ├── reset-unix.sh          # Linux/macOS 重置
│   ├── tests/                 # 回归测试（RT）
│   │   ├── test-node-resolution.ps1  # node 解析不依赖 PATH（Windows，离线）
│   │   └── test-node-resolution.sh   # node 解析不依赖 PATH（Linux/macOS，离线）
│   └── COMMANDS.md            # 命令速查
├── brand-patch/               # 品牌补丁（去 DeepSeek 化 + 中文本地化，安装时自动应用）
├── config/
│   └── settings.example.yaml  # 模型配置参考模板
├── docs/
│   ├── ARCHITECTURE.md        # 整合架构与关键决策
│   ├── DEPLOYMENT.md          # 部署指南（U 盘格式/权限/端口/长路径/杀软）
│   ├── COMPATIBILITY.md       # 兼容性矩阵与已验证项
│   └── TROUBLESHOOTING.md     # 故障排查
├── .cache/                    # 便携运行时与依赖（随盘携带，不入 git）
│   ├── runtimes/windows-x64/node/  # 便携 Node.js
│   ├── app/node_modules/           # @deepseek-ai/dsh 及其依赖
│   └── downloads/                  # 离线安装包（无需联网即可装 Node）
├── data/                       # 运行期数据（DSH_HOME，含配置/密钥/会话，不入 git）
│   ├── dsh/
│   └── logs/
└── work/                       # （可选）默认工作目录，项目文件放这里（不入 git）
```

## 品牌改造（brand-patch）

本项目通过 `brand-patch/` 对 dsh 做了**去 DeepSeek 品牌化 + 中文本地化**改造，安装时自动应用：

- 品牌标识、产品名、欢迎文案改为「USB Harness」（保留"欢迎使用"简短简介）
- 「预览版/测试阶段」等字样移除
- 默认移除官方 DeepSeek 适配器（`llm-deepseek` 禁用），模型配置仅保留自定义 OpenAI 兼容网关
- 权限模式等界面文案中文化（只读 / 工作区可写 / 完全访问）
- 升级 dsh 后 `launch.bat setup` 会自动重新应用补丁

## 中国网络 / 离线安装

- **默认已适配中国网络**：Node 下载优先 `npmmirror.com/mirrors/node/`，npm 用 `registry.npmmirror.com`，失败自动回退官方源
- **U 盘预置离线包**：`install` 会优先使用 `.cache/downloads/` 里的 Node 安装包，无需联网即可安装 Node
- **重置不删运行环境**：软重置只清配置数据，`.cache`（Node + dsh + 离线包）原样保留

## 版本锁定

**项目版本号 = 适配的 dsh 版本**（Release tag 与 HARNESS_VERSION 都是 dsh 版本号，
例如 `0.1.1-rc.2` 表示本包适配 dsh `0.1.1-rc.2`）。若需要发布「不涉及上游变更」的
包装热修复，在 dsh 版本后追加纯数字补丁号，如 `0.1.1-rc.2.1`。
v1.0.0–v1.0.5 为旧版外壳自编号，已弃用。

| 组件 | 版本 | 说明 |
|------|------|------|
| 本包（USB Harness） | `0.1.1-rc.2` | 版本号跟随适配的 dsh 版本（热修复可加 `.N` 后缀） |
| `@deepseek-ai/dsh` | `0.1.1-rc.2` | 预发布候选版（rc），官方声明会有破坏性变更 |
| 便携 Node.js | `22.23.2` (LTS Jod) | 满足 dsh `^22.19.0 \|\| >=24.0.0`（23 不支持） |

> **node 解析**：启动器 / 升级脚本用便携 node 的绝对路径直调 dsh 的 CLI 入口
> （`lib/bin.js`），**不经过**依赖 PATH 的 `.bin` 垫片——机器上有没有 node、node 多旧，
> 都不影响本包运行（历史事故：`node 不是内部或外部命令` / `Object.hasOwn is not a function`，
> 见 `scripts/tests/test-node-resolution.*` 回归测试）。

### dsh 0.1.1-rc.2 变更要点（相对 0.1.1-rc.1）

| 类别 | 变更 | 对你的影响 |
|------|------|-----------|
| **新功能** | 统一图片请求管线：`read_image` 走规范化存储 + Files 回退；新增 `maxRequestFilesBytes`（默认 128 MiB）、`maxImagesPerRequest`（默认 600）、`maxInlineRequestImageBytes`（默认 20 MiB）等配额项 | 图片/多模态输入更稳，大图与多图不再轻易超限 |
| **行为变更** | `read_image` 执行时校验当前路由模型；返回值新增缩放后尺寸与坐标比例 | 切换模型后重新提交图片请求即可，无需额外操作 |
| **破坏性变更** | 配置项 `maxRequestImageBytes` **已移除**，拆分为 `maxRequestFilesBytes` + `maxInlineRequestImageBytes` | `settings.yaml` 里写过旧项的，需按新名改写（见下方对照） |
| **破坏性变更** | 权限预设的 Settings 命名空间 `permission` → `permissionPresets`；事件名 `permission/preset` → `permissionPresets/preset` | 自定义 `cordis.patch.yml` 引用旧命名空间的，需同步改名 |
| **废弃项** | 图片区域读取（image-region / region reads）**已移除** | 需裁剪图片时，改用文件系统路径上的其他工具 |
| **问题修复** | Files 解析失败自动回退内联、Files 与流超时解耦、WebP 透明通道兼容等 | 图片上传偶发失败的情况明显减少 |

**失效配置项对照**

| 旧写法（`settings.yaml`） | 新写法 | 迁移动作 |
|---------------------------|--------|----------|
| `maxRequestImageBytes: 20971520` | `maxRequestFilesBytes: 134217728` + `maxInlineRequestImageBytes: 20971520` | 旧名不再生效，按新名改写；不写则用默认值 |

> **适用边界**：上表中 Files API 相关配额（`maxRequestFilesBytes` 等）仅在使用 **DeepSeek 官方通道**时生效。
> 本项目默认已禁用官方适配器（见「品牌改造」），走自定义 OpenAI 兼容网关时以目标网关自身的限制为准；
> 命名空间与事件名变更则是通用的，与用哪个通道无关。

> 完整逐条清单见 [docs/COMPATIBILITY.md](docs/COMPATIBILITY.md)，
> 同步流程见 [docs/RELEASE_README_SYNC.md](docs/RELEASE_README_SYNC.md)。

### 检查更新 / 升级

> 版本号跟随 dsh：`check-update` 显示的「程序版本」即本包适配的 dsh 版本。

- **普通用户**：启动菜单 `[2] 检查更新`（或 `launch.bat check-update` / `bash launch.sh check-update`）
  会同时检测「本项目新 Release」与「上游 dsh 新版」。
  项目有新版 → 提示到 Releases 页下载完整包（数据可沿用）；dsh 上游有新版 → 提示等待本项目适配。
- **维护者升级 dsh 版本**：
  1. 改 `scripts/setup-windows.ps1` 的 `$DshVersion` 与 `scripts/setup-unix.sh` 的 `DSH_VERSION` 为目标版本
  2. 按 [发布同步规范](docs/RELEASE_README_SYNC.md) 校验 `brand-patch` 基线是否与目标版本一致——**版本号与补丁基线必须同时改**，否则会「装旧版、打新版补丁」导致启动崩溃
  3. 同步更新 `PeerFix` / `PEERS` 中 `dsh-*` 的版本串，然后 `launch.bat upgrade`
     （或 `scripts/upgrade-windows.ps1 -DshVersion <v>` / `bash scripts/upgrade-unix.sh <v>`）
  4. 启动后确认无 `ERR_MODULE_NOT_FOUND`，并在 Web UI 中确认品牌改造仍生效

> 升级只动 `.cache/` 运行环境，**`data/dsh/`（配置/密钥/会话）零改动**，失败自动回滚到升级前状态。
> 普通用户无需手动升级：直接下载 [Releases](https://github.com/tmy2623231/USB-Harness/releases/latest) 最新完整包即可。

## 安全须知

- API 密钥明文存放于 `data/dsh/.credentials.yaml`，**U 盘丢失即泄露**。务必用 BitLocker / VeraCrypt 加密 U 盘
- 默认监听 `0.0.0.0`（局域网可访问）。**不要对公网开放**——Web UI 可执行命令、读写文件、管理凭据
- 该文件已被 `.gitignore` 排除，切勿提交到任何仓库

## 文档

| 文档 | 内容 |
|------|------|
| [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) | 整合架构与关键决策 |
| [docs/DEPLOYMENT.md](docs/DEPLOYMENT.md) | 部署指南（U 盘格式/权限/端口/长路径/杀软） |
| [docs/COMPATIBILITY.md](docs/COMPATIBILITY.md) | 兼容性矩阵、已验证项与逐条版本变更清单 |
| [docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md) | 故障排查 |
| [docs/RELEASE_README_SYNC.md](docs/RELEASE_README_SYNC.md) | 发布同步规范（dsh 升级时如何更新本文档） |
| [CHANGELOG.md](CHANGELOG.md) | 本项目版本更新日志 |

## License

本项目为 deepseek-harness 的派生变体，遵循 **MIT License**（与上游 [deepseek-harness](https://github.com/deepseek-ai/deepseek-harness)
一致）。上游版权归 DeepSeek AI 所有，本项目的便携外壳与品牌改造部分见 [LICENSE](LICENSE)。
第三方依赖许可证见上游 `THIRD_PARTY_NOTICES.md`。

## 致谢

- [deepseek-harness](https://github.com/deepseek-ai/deepseek-harness) — 核心 AI 能力与许可基础
