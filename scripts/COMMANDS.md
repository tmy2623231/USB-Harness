# USB Harness — 命令速查

> 所有脚本都在 `scripts/` 目录；入口是根目录的 `launch.bat`（Windows）与 `launch.sh`（Linux/macOS）。

## 日常使用

| 操作 | 命令 |
|------|------|
| 启动（交互菜单） | 双击 `launch.bat` / `bash launch.sh`（菜单 `[2]` 检查更新） |
| 直接启动 Web | `launch.bat web` / `bash launch.sh web` |
| 查看状态 | `launch.bat status` / `bash launch.sh status` |
| 检查更新 | `launch.bat check-update` / `bash launch.sh check-update` |
| 检查并升级（有新版时提示） | `launch.bat upgrade` / `bash launch.sh upgrade` |
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
├── HARNESS_VERSION            # 程序版本（Release 打包时写入，check-update 读取）
├── .ready.flag                # 就绪标记（node=/dsh=/harness=/created=，setup 生成）
├── scripts/                   # 启动器 / 安装 / 重置 / 升级脚本
│   ├── launch-windows.ps1     # Windows 交互菜单
│   ├── setup-windows.ps1      # Windows 首次配置
│   ├── setup-unix.sh          # Linux/macOS 首次配置
│   ├── upgrade-windows.ps1    # Windows 检查更新 / 升级 / 回滚
│   ├── upgrade-unix.sh        # Linux/macOS 检查更新 / 升级 / 回滚
│   ├── reset-windows.ps1      # Windows 重置
│   └── reset-unix.sh          # Linux/macOS 重置
├── brand-patch/               # 品牌补丁（去 DeepSeek 化，安装时自动应用）
├── config/settings.example.yaml
├── docs/                      # 文档
├── .cache/                    # 便携 Node + dsh（安装时生成）
└── data/dsh/                  # 配置 / 密钥 / 会话（DSH_HOME，升级永不触碰）
```

## 模型配置（进入 Web 界面后）

**设置 → 模型** → 添加「自定义 OpenAI 兼容网关」，填写：

- **baseURL**：如 `https://bi.tianmaoyi.cn:4443/v1`（阿里云百炼）、`http://127.0.0.1:11434/v1`（本地 Ollama）
- **API Key**：网关提供的密钥
- **模型列表**：网关支持的模型 id（如 `qwen3.8-max`）

保存后即生效；在对话页右上角模型选择器里选定模型即可开始使用。

## 工作区

- 工作区由用户在 Web 界面中自行选择（新建会话时选择目录）。
- 会话中读写文件、运行命令都基于所选工作区目录。

## 检查更新 / 升级

启动器菜单 `[2]` 或直通命令 `check-update` 会做**双层检测**（两源独立，互不拖累）：

| 检测项 | 来源 | 有新版本时的行为 |
|--------|------|------------------|
| 程序版本（完整包） | GitHub Releases（本项目） | 提示到 Releases 页下载完整包，**数据可沿用** |
| dsh 版本（引擎） | npm（npmmirror 优先，回退官方源） | 提示上游已发新版，**需本项目适配后**才会在此提供升级 |

`check-update` 输出格式固定为三行结论；某项网络失败只跳过该项并给出警告，不影响另一项。

### 退出码（check-update / upgrade 直通模式透传）

| 码 | 含义 |
|----|------|
| 0 | 已是最新（或升级成功） |
| 1 | 检测到更新（仅 check-update） |
| 2 | 网络不可达（菜单模式自动吞掉，不影响菜单循环） |
| 3 | 本地版本未知（环境不完整，请先 setup） |
| 4 | peer 未适配被阻断（上游 dsh 新版但本项目未适配） |
| 5 | 升级失败，已自动回滚到旧版本 |
| 6 | 磁盘空间不足，中止升级 |

### 强制升级（维护者用）

`scripts/upgrade-windows.ps1 -DshVersion <x.y.z>` / `bash scripts/upgrade-unix.sh <x.y.z>`
可在 peer 已适配的前提下强制升级 dsh。**前置条件**：`setup-*.ps1|sh` 内 `PeerFix` / `PEERS`
中 `@deepseek-ai/dsh-*` 的版本串已与目标版本严格一致（脚本会自动校验，不一致直接阻断，退出码 4）。
普通用户请直接等待本项目发布适配版 Release，菜单 `[2]` 会提示。

### 升级过程与数据安全

- 升级流程：写 journal（`.cache/upgrade.state`，含旧 flag 全文 base64 备份）→ `.cache/app`
  改名备份为 `.cache/app.bak-upgrade`（同盘 O(1)）→ 重新安装新版本 → 自检
  （`dsh --version` 版本匹配 + 随机空闲端口 HTTP 探测 + 日志无模块缺失错误）→ 成功清理 / 失败自动回滚。
- **`data/dsh/`（配置、密钥、会话）自始至终零改动**——升级只动 `.cache/` 内的运行环境。
- 升级中断电/中断：下次启动器自动裁决恢复（以「app 能跑且版本与 flag 一致」为真值锚点，
  残留备份只做单向供给，绝不反向覆盖可用环境）。
- 旧版说明（不再推荐）：删除 `.cache/app` 后重新运行配置脚本（`launch.bat setup`）仍可用，
  但该方式失败无法自动回滚。

## 常见问题

- 端口 3080 被占用：启动时自动顺延；也可用环境变量 `PORT=3090 bash launch.sh`。
- 默认监听 `0.0.0.0`（局域网可访问）。**不要对公网开放**。
- 仅本机访问：`bash launch.sh` 后用 `--host 127.0.0.1`（Windows 见 start 逻辑说明）。
