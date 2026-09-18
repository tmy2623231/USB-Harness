# USB Harness — 命令速查

> 所有脚本都在 `scripts/` 目录；入口是根目录的 `launch.bat`（Windows）与 `launch.sh`（Linux/macOS）。

## 日常使用

| 操作 | 命令 |
|------|------|
| 启动（交互菜单） | 双击 `launch.bat` / `bash launch.sh` |
| 直接启动 Web | `launch.bat web` / `bash launch.sh web` |
| 查看状态 | `launch.bat status` / `bash launch.sh status` |
| 重新配置 / 重装 | `launch.bat setup` / `bash launch.sh setup` |
| 重置（清数据，保留运行环境） | `launch.bat reset` / `bash launch.sh reset` |
| 完全重置（连环境一起删） | `.\scripts\reset-windows.ps1 -Full` / `bash scripts/reset-unix.sh --full` |

## 重置说明（重要）

- **软重置（默认）**：只清空 `data/dsh/`（配置、密钥、会话），**保留 `.cache/` 运行环境**
  （便携 Node + dsh 依赖 + 离线安装包）。重置后**无需联网下载**，直接重新启动即可，
  只是回到「未配置模型」的全新状态。
- **完全重置（`-Full` / `--full`）**：连 `.cache/` 一起删，重新安装（会优先用 U 盘离线包，
  尽量少下载）。

## 中国网络 / 离线安装

- **默认已适配中国网络**：Node 下载优先 npmmirror 镜像、npm 用 `registry.npmmirror.com`，
  失败自动回退官方源（nodejs.org / npmjs.org）。
- **U 盘预置离线包**：`install` 会优先使用 `.cache/downloads/` 里的 Node 安装包
  （`node-v22.23.2-win-x64.zip`），无需联网即可装 Node。
- **已装好就直接用**：`.cache/`（便携 Node + dsh 依赖）已随 U 盘携带，
  插入电脑双击 `launch.bat` 即可用，**无需重新安装**。

## 手动配置（首次安装）

```powershell
# Windows
powershell -ExecutionPolicy Bypass -File .\scripts\setup-windows.ps1
```

```bash
# Linux/macOS
bash scripts/setup-unix.sh
```

## 目录结构

```
USB-Harness/
├── launch.bat / launch.sh     # 一键启动入口
├── HARNESS_VERSION            # 版本标记（Release 打包时写入；启动器不再展示）
├── .ready.flag                # 就绪标记（node=/dsh=/harness=/created=，setup 生成）
├── scripts/                   # 启动器 / 安装 / 重置脚本
│   ├── launch-windows.ps1     # Windows 交互菜单
│   ├── setup-windows.ps1      # Windows 首次配置
│   ├── setup-unix.sh          # Linux/macOS 首次配置
│   ├── reset-windows.ps1      # Windows 重置
│   └── reset-unix.sh          # Linux/macOS 重置
├── brand-patch/               # 品牌补丁（去 DeepSeek 化，安装时自动应用）
├── config/settings.example.yaml
├── docs/                      # 文档
├── .cache/                    # 便携 Node + dsh（安装时生成）
└── data/dsh/                  # 配置 / 密钥 / 会话（DSH_HOME）
```

## 模型配置（进入 Web 界面后）

**设置 → 模型** → 添加「自定义 OpenAI 兼容网关」，填写：

- **baseURL**：如 `https://your-gateway.example.com/v1`（自建或云端 OpenAI 兼容网关）、`http://127.0.0.1:11434/v1`（本地 Ollama）
- **API Key**：网关提供的密钥
- **模型列表**：网关支持的模型 id（如 `your-model-id`）

保存后即生效；在对话页右上角模型选择器里选定模型即可开始使用。

## 工作区

- 工作区由用户在 Web 界面中自行选择（新建会话时选择目录）。
- 会话中读写文件、运行命令都基于所选工作区目录。

## 版本更新（本项目不内置自动升级）

本项目**没有**「检查更新 / 一键升级」功能：`brand-patch` 是整文件快照覆盖，
让 npm 原地升级 dsh 会把 14 个包的定制悄悄覆盖掉。因此：

- **普通用户**：新版本发布后，直接到 [Releases 页](https://github.com/tmy2623231/USB-Harness/releases/latest)
  下载最新完整包覆盖解压（`data/dsh/` 配置、密钥、会话全部沿用）。
- **维护者**：适配新版 dsh 的流程（改版本号 → 校验补丁基线 → 重定 peer 清单 → 重装验证）
  见 [README「维护者：适配新版 dsh 的流程」](../README.md) 与
  [docs/RELEASE_README_SYNC.md](../docs/RELEASE_README_SYNC.md)。

## 常见问题

- 端口 3080 被占用：启动时自动顺延；也可用环境变量 `PORT=3090 bash launch.sh`。
- 默认监听 `0.0.0.0`（局域网可访问）。**不要对公网开放**。
- 仅本机访问：`bash launch.sh` 后用 `--host 127.0.0.1`（Windows 见 start 逻辑说明）。
- `node 不是内部或外部命令` 或 Web 报「Object.hasOwn is not a function」：这是旧版本号
  （≤ v1.0.5 / 0.1.1-rc.2 的已知问题）——dsh 的 `.bin` 垫片靠 PATH 找 node，系统没装 node
  或装着旧系统 node（<16.9）时被带偏。**`0.1.1-rc.2.1` 起已根治**：启动器用便携
  node 的绝对路径直调 dsh CLI 入口（`lib/bin.js`），不再经过垫片，与系统 node 完全无关。
  排查手段：确认包根存在 `.cache/app/node_modules/@deepseek-ai/dsh/lib/bin.js`（缺失 =
  安装不完整，重跑 setup）；回归测试见 `scripts/tests/test-node-resolution.ps1`。
- `ERR_MODULE_NOT_FOUND: Cannot find package '@deepseek-ai/dsh-xxx'`：dsh 的 peer 依赖缺陷，
  补齐清单须逐版本实测重定（0.1.1-rc.2 为 25 个，**0.1.5-rc.2 为 71 个**），
  方法见 `docs/TROUBLESHOOTING.md` 的「peer 依赖补齐清单的重定方法」。
  **不要用「扫安装树看缺哪个」的办法**重定——那是循环论证、会报「缺失 0 个」的假阴性。
- 裸跑 `dsh` 报 `error: --profile <name> is required`：0.1.5 起 dsh 无默认执行档位，
  须显式给 `web` / `acp` / `headless` / `sdk`。
  本项目的「命令模式」= `--profile headless`（输入一条命令 → 跑完打印答案 → 退出），
  用启动器菜单 `[2]` 直接选即可，启动器会自动带上 `--profile`，无需手敲。

  > 注意：上游**没有出货交互式 TUI 档位**（`dsh --help` 示例里的 `tui` 附带
  > `assuming the tui profile is installed` 限定条件，实测该档位不存在）。
  > 若想持续多轮对话，请用菜单 `[1]` 的 Web 界面；
  > `headless` 每次只跑一个任务，会话数据仍持久化在 `$DSH_HOME`，可用 `--resume` 续接。
- 启动器 CLI 模式曾报 `--profile is required`（**已修复**）：`launch-windows.ps1` 的 CLI 分支
  原先调用的是裸 `dsh`。由于 0.1.5 取消默认档位，该路径**每次必失败**。
  现已改为显式传入 `--profile headless`（0.1.5-rc.2.5 起因需分离 stdout/stderr，
  改用 .NET `Process` 直接拉起 node，不再经由 `Invoke-Dsh` 包装函数）；
  冒烟用例 6「启动器 CLI 分支传参」专门守护此点（防止再次漏传）。
  该断言的判定口径是「启动 dsh 时带了 `--profile headless`」，**不是**「调用了哪个包装函数」——
  后者属于实现细节，换实现就会误报。
- 启动器 CLI 模式跑任务时**满屏红字**（**已修复**）：终端刷出
  ```
  node.exe : dsh: reasoning:
  + CategoryInfo : NotSpecified: (dsh: reasoning::String) [], RemoteException
  + FullyQualifiedErrorId : NativeCommandError
  ```
  看起来像崩溃，**其实任务成功了**——答案就打在终端里，只是被红字盖住。
  根因：`headless` 按上游设计把**推理过程写 stderr**、最终答案写 stdout；
  PowerShell 原生命令管道会把子进程每一行 stderr 包成 ErrorRecord 渲染成红字。
  另实测 `2>>` 重定向还会让 `dsh-cli.err.log` 写成 **0 字节**（日志同时失效）。
  0.1.5-rc.2.5 起启动器改用 .NET `Process` 分别读两条流：stdout 正常回显为
  「===== 最终答案 =====」，stderr 只提示已落日志。**看到 `NativeCommandError` 不代表失败**，
  请以答案区块与退出码为准。守护用例：冒烟用例 10（行为验证双流分离）。
- 打开 Web 只显示 `401`：dsh 的 browser-trust fence 正常行为，需带启动时打印的 `?token=xxx`
  访问（会 303 种下会话 cookie，之后为 200）。本项目**不自动打开浏览器**：
  等服务就绪后从控制台复制 `web:` 开头那一整行地址（含 token）即可。
