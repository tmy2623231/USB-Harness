# USB Harness — 架构与整合决策

> 本文档说明「USB Harness」如何将 `Hermes-USB-Portable` 的便携框架与
> `deepseek-harness (dsh)` 的全部能力整合为一个可放进 U 盘、插入任意 Windows
> 电脑即插即用的 AI 助手。

## 1. 两个源项目的角色分工

| 源项目 | 在本项目中的角色 | 保留的内容 | 舍弃的内容 |
|--------|------------------|-----------|-----------|
| **Hermes-USB-Portable** | **便携外壳 / 部署框架** | 便携运行时自动下载、数据随盘携带、零宿主机污染、双击启动 | 其底层 Agent（Nous Hermes Agent）被替换为 dsh |
| **deepseek-harness (dsh)** | **核心 AI 能力** | Web UI、实时对话、流式输出、模型加载、全部工具/插件、API 兼容性 100% | 其「必须全局安装 Node/pnpm、数据写 `~/.dsh`」的宿主绑定 |

一句话：**用 Hermes 的「壳」装 dsh 的「芯」**。

## 2. 关键整合决策（及其理由）

### 决策 1：用官方 npm 预编译包，而不是从源码编译 monorepo

dsh 提供官方发布包 `@deepseek-ai/dsh`（当前 `0.1.1-rc.1`），`npx @deepseek-ai/dsh web`
即可启动完整 Web UI。本项目选择**预编译包**而非源码构建，理由：

- **100% 功能兼容**：npm 包由官方源码构建，包含全部功能插件（`dsh-web-app`、`dsh-headless`、
  `dsh-tool-*`、会话持久化、MCP 等），功能与源码版一致。
- **体积与稳定性**：源码 monorepo 13k+ 提交、pnpm workspace + 原生模块（node-pty）需本地编译，
  体积大、且开发者预览期每天都有破坏性变更；预编译包体积小、版本可锁定。
- **U 盘友好**：源码构建依赖 pnpm 的符号链接式 `node_modules`，在 exFAT/FAT32 上会直接失败。

### 决策 2：用 npm（而非 pnpm）安装核心运行环境

- Windows 上 npm 生成**扁平化（hoisted）`node_modules` + `.cmd` 启动 shim**，**不使用符号链接**，
  因此可运行在 exFAT / FAT32 / NTFS 上。
- **运行时回退**：dsh 启动时会在 `$DSH_HOME/profiles/node_modules/` 下创建符号链接（模块回退机制），
  exFAT/FAT32 不支持时会失败。本项目通过 `brand-patch` 给 `dsh-app-boot` 打了**复制回退补丁**——
  链接创建失败时自动复制真实包目录代替，因此核心功能在三种文件系统上均可用（详见 [DEPLOYMENT.md](./DEPLOYMENT.md)）。
- pnpm 使用硬链接/符号链接 store，是 U 盘（尤其 exFAT）的已知故障点。
- **例外**：`dsh plugin` 子命令内部会转发到 pnpm，用于安装社区插件。这是**可选扩展**，
  见 [DEPLOYMENT.md](./DEPLOYMENT.md#可选安装社区插件)。

### 决策 3：用 `DSH_HOME` 重定向实现「数据随盘」

dsh 官方支持 `DSH_HOME` 环境变量，默认 `~/.dsh` 可重定向到任意目录。本项目将其指向
`<U盘根>\data\dsh\`，于是：

```
data/dsh/
├── profiles/          # web / headless 等命名产品入口
├── sessions/          # 会话事件流日志
├── storages/          # 持久化会话存储
├── settings.yaml      # 主配置（模型/供应商路由）
├── .credentials.yaml  # API 密钥（明文，仅随盘，勿提交 git）
└── cordis.patch.yml   # 用户自定义补丁层（可选）
```

**效果**：API 密钥、配置、会话历史、已安装插件全部留在 U 盘，宿主机零残留。

### 决策 4：便携 Node.js + 预置依赖，实现「零宿主机依赖」

- 便携版 Node.js 从官方 `nodejs.org/dist` 下载 `node-*.zip`（非安装器，解压即用），
  版本锁定 **22.x LTS**（满足 dsh 的 `^22.19.0 || >=24.0.0`，23 被官方排除）。
- `@deepseek-ai/dsh` 预装到 `.cache/app/node_modules`，随盘携带。
- 启动脚本只把 U 盘内的 `node` 与 `.bin` 注入 `PATH`，**不修改系统环境变量、不写注册表**。

## 3. 目录结构

```
USB-Harness/
├── launch.bat / launch.sh       # 一键启动入口（交互菜单，仿 Hermes-USB-Portable）
├── scripts/
│   ├── launch-windows.ps1       # Windows 启动器：中文菜单 + 环境 + 运行 dsh web
│   ├── setup-windows.ps1        # 首次配置：下载 Node + 安装 dsh + 品牌补丁
│   ├── setup-unix.sh            # Linux/macOS 首次配置
│   ├── reset-windows.ps1        # 重置（清空 .cache 与 data/dsh）
│   ├── reset-unix.sh            # Linux/macOS 重置
│   └── COMMANDS.md              # 命令速查
├── brand-patch/                 # 品牌补丁（去 DeepSeek 化，安装时自动应用）
├── config/
│   └── settings.example.yaml    # 参考配置模板（OpenAI 兼容网关 / Ollama）
├── docs/
│   ├── ARCHITECTURE.md          # 本文档
│   ├── DEPLOYMENT.md            # 部署指南（U 盘格式/权限/端口/长路径/杀软）
│   ├── COMPATIBILITY.md         # 兼容性矩阵与已验证项
│   └── TROUBLESHOOTING.md       # 故障排查
├── .cache/                      # 运行时（随盘携带，勿入 git）
│   ├── runtimes/windows-x64/node/   # 便携 Node.js
│   └── app/node_modules/            # @deepseek-ai/dsh 及其依赖
├── data/                        # 运行期数据（DSH_HOME）
│   ├── dsh/                     # profiles/sessions/settings.yaml/.credentials.yaml
│   └── logs/                    # 启动日志
└── .gitignore
```

## 4. 启动时序

```
用户双击 launch.bat（或 bash launch.sh）
  → 调用 scripts/launch-windows.ps1
  → 解析 U 盘根目录（scripts/ 的上一级）
  → 校验 .cache 就绪（Node + dsh 均存在）→ 否则自动调用 setup-windows.ps1
  → 显示交互菜单（启动 Web / 重新配置 / 重置 / 状态）
  → [1] 启动：设置 DSH_HOME、注入 PATH、探测 3080 端口
  → 运行 dsh web --port <N> --host 0.0.0.0
  → 输出访问地址到控制台与 data/logs/
```

## 5. 与「100% 兼容」的关系

dsh 的能力（模型加载、对话、Web UI、流式输出、API、工具/插件、headless、MCP）**全部来自
官方预编译包，未做任何裁剪或改写**。本项目只在其外层增加：便携运行时、`DSH_HOME` 重定向、
端口处理、启动脚本与文档。因此不存在「改写后功能丢失」的风险；兼容性边界只在
**U 盘文件系统（exFAT 不支持符号链接 → 影响 pnpm 装插件）** 与 **宿主机是否允许从可移动盘运行**。
详见 [COMPATIBILITY.md](./COMPATIBILITY.md)。
