<div align="center">

# 🚀 USB Harness — 即插即用的 U 盘 AI 助手

**deepseek-harness 便携式变体 · 免安装 LLM Web UI · 离线可用 · 中国网络适配**

<img src="docs/banner.svg" alt="USB Harness banner" width="800"/>

[![License](https://img.shields.io/github/license/tmy2623231/USB-Harness?color=blue)](LICENSE)
[![Release](https://img.shields.io/github/v/release/tmy2623231/USB-Harness?color=orange&label=latest)](https://github.com/tmy2623231/USB-Harness/releases/latest)
[![Downloads](https://img.shields.io/github/downloads/tmy2623231/USB-Harness/total?color=green)](https://github.com/tmy2623231/USB-Harness/releases/latest)
[![Stars](https://img.shields.io/github/stars/tmy2623231/USB-Harness?color=yellow)](https://github.com/tmy2623231/USB-Harness)
[![Platform](https://img.shields.io/badge/platform-Windows%20%7C%20Linux%20%7C%20macOS-blueviolet)](launch.sh)
[![dsh](https://img.shields.io/badge/dsh-0.1.5--rc.2-purple)](https://github.com/deepseek-ai/deepseek-harness)
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
- ✅ **交互式启动器**：中文菜单（启动 / 检查更新 / 重置 / 切换运行模式 / 退出），首启自动安装
- ✅ **Web / CLI 双模式**：默认 Web 图形界面，可在控制台菜单一键切换为 **CLI 单次任务模式**；默认仍为 Web，不影响任何既有行为
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
[1] 启动（当前模式：Web 界面 / CLI 单次任务）
[2] 检查更新（程序与 dsh 版本）
[3] 重置（清配置数据，保留运行环境，无需下载）
[4] 切换运行模式（Web 界面 ⇄ CLI 单次任务）
[5] 退出
```

默认监听 `http://0.0.0.0:3080`（本机 `http://127.0.0.1:3080`，局域网 `http://<本机IP>:3080`）。

### 运行模式：Web 界面 / CLI 单次任务

启动器菜单 `[4] 切换运行模式` 可在两种模式间切换，**默认 Web 界面**：

| 模式 | 启动内容 | 适用场景 |
|------|----------|----------|
| **Web 界面**（默认） | 启动 dsh Web 服务并自动打开浏览器 | 图形化对话、多模态输入、局域网共享 |
| **CLI 单次任务** | 输入一个 task，dsh 跑完一次会话后打印最终答案并退出 | 无浏览器环境、SSH 远程、脚本化/批处理场景 |

**模式持久化位置**：`config/launch.conf` 的 `mode` 字段（Windows 与 Linux/macOS 共用同一文件格式）。
该文件**不存在、为空或值无法识别时一律按 Web 界面处理**，因此删除该文件即可恢复默认，不影响任何既有行为。

```ini
# config/launch.conf
mode = web      # web = Web 界面（默认）；cli = CLI 单次任务
```

CLI 单次任务底层调用的是 dsh 的 `--profile headless`：

```bash
dsh --profile headless "<task>"
```

dsh 0.1.5 自带的档位只有 `web` / `acp` / `headless` / `sdk` 四个，**没有开箱即用的
终端多轮对话档位**——dsh 本身是 CLI，但它的交互体验主要在 Web 界面上。
术语与上游对齐（`dsh --profile headless --help` 原文：*"Answer one task, stream reasoning
to stderr, print the final assistant message, and exit."*），启动器界面统一使用
**「任务 / task」** 表述。日志写入 `data/logs/dsh-cli.log`。
切换后菜单 `[1]` 会显示当前模式，直接启动对应界面。

#### 怎么验证 CLI 模式真的能用

CLI 模式**没有独立于模型的验证方式**——它必须有一个可用的模型才能跑出答案。
判据分两层：

| 现象 | 含义 |
|------|------|
| `dsh: NO_ADAPTER: no adapter registered for provider "pi-ai"` | **插件树已加载成功，只是没配模型**。这说明 CLI 模式的调用链路是通的，缺的只是模型凭据 |
| 打印出模型生成的答案 | 全链路可用 |

因此验证步骤是：先在 **Web 界面 → 设置 → 模型** 里配好一个自定义提供方（见下节），
再回到 CLI 模式发一个简单任务（例如 `1+1 等于几`）。能打印出答案即代表 CLI 模式正常。

也可以绕过启动器直接测（最直接）：

```bash
export DSH_HOME="<解压目录>/data/dsh"
"<解压目录>/.cache/runtimes/windows-x64/node/node.exe" \
  "<解压目录>/.cache/app/node_modules/@deepseek-ai/dsh/lib/bin.js" \
  --profile headless "1+1 等于几"
```

> 注意：`NO_ADAPTER` 时报错走的是 stderr，PowerShell 会把它渲染成 `NativeCommandError`
> 红字，这是**渲染问题不是崩溃**——该进程退出码为 0。

### 3. 配置模型（进入 Web UI 后）

**设置 → 模型 → 添加自定义提供方**，填入：

- **API 地址**：OpenAI 兼容网关地址，如 `https://your-gateway.example.com/v1`、本地 Ollama `http://127.0.0.1:11434/v1`
- **API 密钥**：网关提供的密钥
- **模型目录**：点击「获取可用模型」自动拉取，或手动添加模型 ID

保存后在对话页右上角选择模型即可开始使用。全新安装时欢迎页点「继续」会**直接弹出添加自定义模型表单**。

> **本项目不内置任何模型凭据**（这是有意的：见「安全须知」与隐私清理说明），
> 因此首次使用**必须自己配一次模型**，这是预期行为、不是故障。

#### 还没配模型时，会看到哪些"像报错"的提示？

提前知道就不会误判成崩溃：

| 场景 | 现象 | 是否正常 |
|------|------|----------|
| CLI 单次任务 | `dsh: NO_ADAPTER: no adapter registered for provider "pi-ai"` | ✅ 正常。说明插件树已完整加载，只是没有可用的模型适配器 |
| Web 对话 | 发消息报模型不可用 / 无适配器 | ✅ 正常。同上，去「设置 → 模型」配好即可 |
| 启动阶段 | 控制台出现 `error:` 开头的红字（PowerShell 的 `NativeCommandError`） | ✅ 多数正常。Node 把 stderr 写警告时，PowerShell 会统一渲染成红字 |

> **判断口径**：只要 Web 首页能打开、插件列表能加载，就说明程序本身没问题，
> 缺的只是模型配置。**真正需要警惕的是浏览器里出现
> `Failed to load plugins`**——那说明某个补丁产物在浏览器端执行时抛错了，
> 属于程序缺陷，请反馈。

### 4. 选择工作区

会话基于工作区（项目目录）运行，在 Web 界面中自行选择。会话中读写文件、执行命令都以所选工作区为根。

### 5. 关于启动与运行速度

本项目的性能画像与「U 盘 + 便携运行时」的定位强相关，**不是程序缺陷**。实测数据与成因如下：

| 环节 | 实测耗时 | 说明 |
|------|----------|------|
| 便携 node 冷启动 | ≈ 0.75 s | Windows 首次加载 `node.exe`（从 U 盘/需杀软扫描） |
| dsh 模块解析（`--version`） | ≈ 1.3 s | 插件树 + 依赖图解析 |
| **`dsh web` 冷启动到可响应** | **≈ 8.3 s** | 上表各项叠加 + 前端资源装载 |
| token 交换握手 | ≈ 4 ms | 纯本地计算，可忽略 |
| 带 cookie 取首页 | ≈ 7 ms（28.5 KB） | 之后为静态资源（gzip 后更小） |
| 浏览器侧 JS 总量 | ≈ 9.8 MB（41 个 UI 包） | 首次加载需解压 + 执行，是「感觉慢」的主因 |

**主要成因（按影响排序）**：

1. **前端体积大**：`dsh-web-frontend` 4.8 MB（含 `vendor` 724 KB、语法高亮 `cpp` 624 KB、
   `ruby` 416 KB 等按需 chunk），41 个 `dsh-client-ui-*` 包共约 9.8 MB 源码。
   浏览器首次执行 + React 挂载占了大头。**第二次打开会走浏览器缓存**，明显变快。
2. **U 盘顺序读 + 杀毒扫描**：`.cache/` 下上万个文件，每次冷启动都要重新遍历；
   实时防护对 `node.exe` 的首次扫描会额外增加数秒。
3. **冷启动一次性开销**：便携 node 首次加载、插件树解析、会话目录初始化。
4. **模型未配置不算卡点**：`NO_ADAPTER` 是立即返回的，不产生等待。

**优化建议（按性价比排序）**：

- **把包放在本机硬盘（推荐）**：U 盘定位是"带走即用"，日常使用建议拷到本地 SSD
  再启动，可省掉 U 盘读 + 杀软扫描的两项开销。
- **把包目录加入杀毒软件白名单**：实时防护停止对 `.cache/` 的逐文件扫描，效果最明显。
- **保持 Web 服务常驻**：启动后不关，用浏览器刷新而非重启服务。首启 8.3 s 是**一次性的**，
  之后就绪状态下的请求都在毫秒级。
- **用本机 `http://127.0.0.1:3080` 而非局域网 IP**：loopback 免去网卡栈开销，
  上游也明确说明部分功能在局域网地址下受限。
- **不要在 CLI 单次任务模式下反复启动**：该模式每次都要重新加载整棵插件树，
  批量任务场景建议改用 `web` 模式常驻。

> 说明：本项目**不做**上游包的裁剪（如删语法高亮 chunk）——那会让 `brand-patch`
> 与上游快照产生额外分叉，抬高后续版本对齐成本。性能优化一律走"环境侧"手段。

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
│   ├── launch.conf            # 运行模式（web / cli），由启动器菜单 [4] 切换
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
例如 `0.1.5-rc.2` 表示本包适配 dsh `0.1.5-rc.2`）。若需要发布「不涉及上游变更」的
包装热修复，在 dsh 版本后追加纯数字补丁号，如 `0.1.5-rc.2.1`。
v1.0.0–v1.0.5 为旧版外壳自编号，已弃用。

| 组件 | 版本 | 说明 |
|------|------|------|
| 本包（USB Harness） | `0.1.5-rc.2` | 版本号跟随适配的 dsh 版本（热修复可加 `.N` 后缀） |
| `@deepseek-ai/dsh` | `0.1.5-rc.2` | 预发布候选版（rc），官方声明会有破坏性变更 |
| 便携 Node.js | `22.23.2` (LTS Jod) | 满足 dsh `^22.19.0 \|\| >=24.0.0`（23 不支持） |

> **node 解析**：启动器 / 升级脚本用便携 node 的绝对路径直调 dsh 的 CLI 入口
> （`lib/bin.js`），**不经过**依赖 PATH 的 `.bin` 垫片——机器上有没有 node、node 多旧，
> 都不影响本包运行（历史事故：`node 不是内部或外部命令` / `Object.hasOwn is not a function`，
> 见 `scripts/tests/test-node-resolution.*` 回归测试）。

> **peer 依赖补齐清单随版本重定**：dsh 的多个子包把彼此声明为 `peerDependencies`，主包 bundle
> 未包含，而 `--legacy-peer-deps` 会跳过它们，导致启动报 `ERR_MODULE_NOT_FOUND`。
> 补齐清单是**逐版本实测出来的**，不是固定值：`0.1.1-rc.2` 下为 25 个，`0.1.5-rc.2` 下为 **26 个**。
> 重定方法（对安装树里全部 `@deepseek-ai/*` 的 import 说明符逐个做模块解析，凡解析不到的即为缺失项）
> 见 [docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md#peer-依赖补齐清单的重定方法)。

### dsh 0.1.5-rc.2 变更要点（相对 0.1.1-rc.2）

| 类别 | 变更 | 对你的影响 |
|------|------|-----------|
| **新功能** | 新增 `agent-presets` 挂载点（`dsh.configTrees`）：会话预设从发布包内的 `config/` 目录迁到可挂载的 preset 目录 | 无感；本项目 `brand-patch` 已随之调整落点，预设功能不受影响 |
| **新功能** | CLI 新增 `--from-default-profile <name>`：以某个已保存的默认 profile 为起点启动 | 便于把调好的会话配置固化成默认档，CLI 单次任务同样受益 |
| **行为变更** | 执行档位精简为 `web` / `acp` / `headless` / `sdk` 四种；裸跑 `dsh` 会直接报 `error: --profile <name> is required` | **必须显式给 profile**；本项目的「CLI 单次任务」即 `--profile headless`，已封装在启动器里，无需手敲 |
| **行为变更** | Web 侧新增 `rejectElectronProfile` 校验；`import.meta.main` + `export { runCli }` 使 CLI 可作为模块被调用 | 无感；属于上游内部结构调整 |
| **安全（本项目已定向放开）** | 上游收紧：`--host 0.0.0.0` 被显式拒绝（理由：会把远程代码执行暴露到网络） | **本项目保留放行**——U 盘插一台机器、同局域网设备访问是本项目的核心场景。此为**有意的定制差异**，不是漏洞：请务必只在可信内网使用，切勿对公网开放（详见「安全须知」） |
| **问题修复** | 上游 0.1.1-rc.2 → 0.1.5-rc.2 区间累计修复（含插件树加载、会话持久化、工具链稳定性等） | 直接受益；本项目 `brand-patch` 已整体重做到 0.1.5-rc.2 基线，不会回滚这些修复 |

**与上游的定制差异（本项目有意保留，非疏漏）**

| # | 差异点 | 上游行为 | 本项目行为 | 原因 |
|---|--------|----------|-----------|------|
| 1 | `--host 0.0.0.0` | 显式报错拒绝 | 放行，默认监听 `0.0.0.0:3080` | U 盘共享场景需同网段设备访问；已用 `token` 交换会话 cookie 的 browser-trust fence 兜底 |
| 2 | 符号链接创建失败 | 直接报错 | 自动回退为真实目录复制 | FAT32/exFAT 不支持 symlink，回退后三种格式均可运行 |
| 3 | 品牌标识 / 产品名 / 欢迎文案 | DeepSeek 品牌 | 「USB Harness」自绘标识 | 去品牌化，避免用户误认为官方发行版 |
| 4 | 官方 `llm-deepseek` 适配器 | 默认启用 | 默认禁用，仅保留自定义 OpenAI 兼容网关 | 密钥与网关由使用者自行提供，不绑定官方通道 |
| 5 | 默认模型 | 官方默认 | `provider: pi-ai` / `model: default` | 与上游解耦，避免默认落到官方通道 |

> **适用边界**：上游文档中的 Files API 配额项（`maxRequestFilesBytes` 等）仅在使用 **DeepSeek 官方通道**时生效。
> 本项目默认已禁用官方适配器（见「品牌改造」），走自定义 OpenAI 兼容网关时以目标网关自身的限制为准。

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
  3. **重定 `PeerFix` / `PEERS` 清单**——补齐清单是逐版本实测的，不能照抄上一版。
     用「对安装树里全部 `@deepseek-ai/*` 的 import 说明符逐个做模块解析，凡解析不到的即为缺失项」
     的方法重定（详见 [docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md#peer-依赖补齐清单的重定方法)）。
     注意：靠「跑一次 dsh 看缺哪个包」的方式**会严重漏报**——多数模块是懒加载的。
  4. 跑完整冒烟测试（`bash .patch-tools/smoke-local.sh`）确认全绿，再 `launch.bat upgrade`
     （或 `scripts/upgrade-windows.ps1 -DshVersion <v>` / `bash scripts/upgrade-unix.sh <v>`）
  5. 启动后确认无 `ERR_MODULE_NOT_FOUND`，并在 Web UI 中确认品牌改造仍生效、`--host 0.0.0.0` 仍被放行

> 升级只动 `.cache/` 运行环境，**`data/dsh/`（配置/密钥/会话）零改动**，失败自动回滚到升级前状态。
> 普通用户无需手动升级：直接下载 [Releases](https://github.com/tmy2623231/USB-Harness/releases/latest) 最新完整包即可。

## 安全须知

- API 密钥明文存放于 `data/dsh/.credentials.yaml`，**U 盘丢失即泄露**。务必用 BitLocker / VeraCrypt 加密 U 盘
- 默认监听 `0.0.0.0`（局域网可访问）。**不要对公网开放**——Web UI 可执行命令、读写文件、管理凭据
- 该文件已被 `.gitignore` 排除，切勿提交到任何仓库

### 打开页面显示 401 / `authentication required`

这是 dsh 的 **browser-trust fence** 在正常工作，不是故障：

- **裸地址**（`http://127.0.0.1:3080` 或 `http://<局域网IP>:3080`）→ 直接返回 `401`
- **带启动时打印的 token**（`http://127.0.0.1:3080/?token=XXXX`）→ 种下会话 cookie，之后正常

**正确做法**：用启动器启动后**等浏览器自动打开**（启动器已轮询就绪并打开带 token 的正确地址）；
若需手动访问，请从启动窗口里复制那一整行 `dsh web: http://...?token=...`，
**务必连 `?token=` 一起复制**——只抄域名和端口会得到 401。

> 从别的设备（局域网 IP）访问时同理，token 就在启动窗口那行的 `LAN:` 部分。

#### 为什么一定要有 token？（这个设计防的是什么）

**因为本项目的核心场景是「U 盘插一台机器，同局域网其他设备也能访问」——
服务监听在 `0.0.0.0`，意味着同网段任何人都能连上这个端口。**

而这个 Web UI 的能力远不止聊天：它能**在你的电脑上执行命令、读写文件、管理凭据**。
没有任何门槛的话，「同一 WiFi 下的任何人」都等于拿到了你电脑的 shell。

token 就是这道门槛。实测的完整握手流程：

| 访问方式 | 实测结果 | 含义 |
|----------|----------|------|
| 裸地址（无 token） | `401` | 拒绝 |
| 错误 token | `401` | 拒绝 |
| 正确 token | `303` + `Set-Cookie: dsh-auth-…` | 换取会话 cookie |
| 带着 cookie 访问干净地址 | `200` | 正常使用 |

**两个容易误解的点**：

1. **token 只需用一次**。它只负责「第一次握手」，之后浏览器靠 cookie 自动通行，
   有效期内（默认 30 天）不用再碰 token。所以它**不是**每次访问都要粘一遍的东西——
   如果每次都要，说明浏览器在丢 cookie（检查是否开了无痕模式 / 清站点数据）。
2. **token 每次启动都重新生成**（实测连续 4 次启动得到 4 个不同的值），
   而 cookie 的签名密钥持久保存在 `data/dsh/.credentials.yaml`。所以：
   **只需把 U 盘里的这个文件保管好，重启不会导致已登录的浏览器掉线。**

> ⚠️ **不要把带 token 的链接发到群里或截图公开**。
> 那串 token 等价于一次登录凭证——谁拿到谁就能访问，且在你本次运行期间一直有效。
> 真要给别人用，让对方走 `LAN:` 那个地址（仍受同样保护）；
> 或者用完直接重启 dsh，旧 token 与旧 cookie 一并作废。

> 补充：上游 dsh 的 README 明确写着 `dsh web --host 0.0.0.0` **是「不支持」的**，
> 因为上游认为把可执行代码的界面暴露到网络风险过大。本项目为 U 盘场景**有意放行**，
> 因此这道 token 栅栏在本项目里**比在上游更重要**——它是放行 `0.0.0.0` 的前提。

## 文档

| 文档 | 内容 |
|------|------|
| [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) | 整合架构与关键决策 |
| [docs/DEPLOYMENT.md](docs/DEPLOYMENT.md) | 部署指南（U 盘格式/权限/端口/长路径/杀软） |
| [docs/COMPATIBILITY.md](docs/COMPATIBILITY.md) | 兼容性矩阵、已验证项与逐条版本变更清单 |
| [docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md) | 故障排查 |
| [docs/RELEASE_README_SYNC.md](docs/RELEASE_README_SYNC.md) | 发布同步规范（dsh 升级时如何更新本文档） |
| [docs/UPGRADE_REPORT_0.1.5-rc.2.md](docs/UPGRADE_REPORT_0.1.5-rc.2.md) | 本次升级变更清单（移植内容 / 冲突差异 / 测试结果 / 分支验证 / 隐私清理） |
| [CHANGELOG.md](CHANGELOG.md) | 本项目版本更新日志 |

## License

本项目为 deepseek-harness 的派生变体，遵循 **MIT License**（与上游 [deepseek-harness](https://github.com/deepseek-ai/deepseek-harness)
一致）。上游版权归 DeepSeek AI 所有，本项目的便携外壳与品牌改造部分见 [LICENSE](LICENSE)。
第三方依赖许可证见上游 `THIRD_PARTY_NOTICES.md`。

## 致谢

- [deepseek-harness](https://github.com/deepseek-ai/deepseek-harness) — 核心 AI 能力与许可基础
