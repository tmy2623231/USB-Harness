# 更新日志

本项目（USB Harness）自身的版本变更记录。
上游 `deepseek-harness (dsh)` 的逐条变更见
[docs/COMPATIBILITY.md](docs/COMPATIBILITY.md#5-版本变更追踪)。

格式参考 [Keep a Changelog](https://keepachangelog.com/zh-CN/)，
版本号遵循[语义化版本](https://semver.org/lang/zh-CN/)。

> **版本体系**：自 `0.1.1-rc.2` 起，**项目版本号 = 适配的 dsh 版本**（Release tag、
> HARNESS_VERSION 均与 dsh 版本一致）；如需发布「不涉及上游变更」的包装热修复，
> 在 dsh 版本后追加包装补丁号，如 `0.1.1-rc.2.1`。`v1.0.0`–`v1.0.5` 为旧版外壳自编号，已弃用。

---

## [0.1.5-rc.2] — 2026-09-17

### 上游对齐（dsh `0.1.1-rc.2` → `0.1.5-rc.2`）

- **版本锁定同步**：`scripts/setup-windows.ps1` 的 `$DshVersion` 与 `scripts/setup-unix.sh`
  的 `DSH_VERSION` 同步为 `0.1.5-rc.2`；CI 正则解析的版本源保持不变（仍是单一数据源）。
- **brand-patch 全部 17 个文件按新基线重建**（关键）。此前 17 个补丁文件中有 **9 个**是
  `0.1.1-rc.2` 的**整文件快照**——整文件沿用会把这些文件在新版本里的**全部上游修复一起回滚**。
  本次改为「新上游基线 + 重新施加定制意图」重建，定制点逐条以**功能断言**校验。
  - 校验结果：**安全 17 / 需确认 0 / 阻断 0 / 异常 0**。
  - 定制清单（全部保留）：品牌标识与文案（8 处）、`--host 0.0.0.0` 放行、
    符号链接失败回退目录复制、默认模型 `provider: pi-ai`、官方 `llm-deepseek` 禁用、
    权限模式中文化、Web 首页标题与 `crypto.randomUUID` polyfill 等。
- **peer 补齐清单重定：25 → 26 个**。dsh 子包互相声明 `peerDependencies` 而主包 bundle
  未包含，`--legacy-peer-deps` 会跳过它们 → 启动报 `ERR_MODULE_NOT_FOUND`。
  重定方法（对安装树里全部 `@deepseek-ai/*` 的 import 说明符逐个做模块解析）
  已写入 `docs/TROUBLESHOOTING.md`。实测 95 个说明符全部可解析、缺失 0。
  - 第三方包（`react@^18.3.1` 等）版本**不跟随** dsh 版本，按各自兼容范围锁定。

### 修复（补丁定制丢失导致 Web 无法启动 —— 严重）

- **根因**：`startup.js` 的定制是删除上游那句
  `program.error("error: --host 0.0.0.0 is intentionally not supported yet for safety ...")`。
  补丁重建时该文件被误判为「仅品牌改名」，删除动作未编码为意图 → 定制静默丢失 →
  `dsh web` 起不来。**而既有的三方校验工具报 OK**：它只比较「补丁 vs 上游」，
  无法回答「定制意图是否还在」。
- **修复**：新增 `allow_all_interfaces` 意图类型，以**字面量查找**确认拦截语句已被移除；
  若未逐字命中而文件里仍有 `0.0.0.0` 相关代码，则**报错退出**（绝不静默跳过），
  交由人工核对上游是否改了写法。
- **教训**：补丁重建后必须补一道**功能断言**，逐条验证定制点存在，不能只信三方差异校验。

### 新增（控制台 CLI 单次任务模式）

- 启动器新增 **[4] 切换运行模式**，可在 **Web 界面**（默认）与 **CLI 单次任务** 间切换。
  - Windows：`scripts/launch-windows.ps1` 新增 `Get-LaunchMode` / `Set-LaunchMode` /
    `Get-LaunchModeLabel` / `Start-Cli` / `Switch-LaunchMode`；菜单重新编号为
    `[1] 启动（当前模式）` `[2] 检查更新` `[3] 重置` `[4] 切换运行模式` `[5] 退出`。
  - Linux/macOS：`launch.sh` 新增同语义的 `get_launch_mode` / `set_launch_mode` /
    `mode_label` / `start_cli` / `switch_launch_mode`。
  - 新增 `config/launch.conf`（`mode = web | cli`），为运行模式**唯一持久化位置**，
    双端共用同一格式。
- **默认行为不变（硬约束）**：`config/launch.conf` 不存在、为空、或 `mode` 值无法识别时，
  一律按 `web` 处理——删除该文件即可恢复默认，且**任何既有默认行为均未改变**。
- 状态面板新增「运行模式」行，并显示当前模式；CLI 模式下不再显示监听地址。
- CLI 模式底层为 `dsh --profile headless`（dsh 0.1.5 起仅有 `web`/`acp`/`headless`/`sdk`），
  日志写入 `data/logs/dsh-cli.log`。

> **定位修正（2026-09-17 补记）**：本项最初按「交互式 TUI」设计，但 dsh 0.1.5 的
> 执行档位中**并不存在交互式 TUI**（`headless` = 跑一次任务、打印答案、退出）。
> 因此该模式重新定位为「**CLI 单次任务**」：启动后提示输入任务，跑完打印答案即退出；
> 需要持续多轮对话请用 Web 界面。菜单、状态面板、提示文案已同步更正。

### 修复（CLI 模式必失败 —— 启动器漏传 `--profile`）

- **`launch-windows.ps1` 的 `Start-Cli` 原先调用裸 `dsh`**。dsh 0.1.5 起取消了默认执行档位，
  裸跑直接报 `error: --profile <name> is required`，**该路径 100% 失败**。
  现已改为 `Invoke-Dsh --profile headless $task`，并增加任务输入与空输入（回车即取消）处理。
- **漏检原因**：冒烟用例 5 虽跑了 `--profile headless`，但**绕过了启动器**直接调 dsh——
  测的是「dsh 能跑 headless」，而非「启动器的 CLI 模式可用」。
  现已补两条守护断言，覆盖**启动器调用路径本身**：
  - 本地：`.patch-tools/smoke-local.sh` 新增**用例 6「启动器 CLI 分支传参」**
    （已做负对照验证：还原为裸调用时判定 FAIL）
  - CI：`.github/workflows/smoke-test.yml` 新增同名步骤「启动器 CLI 分支传参断言」
  - 冒烟用例数 9 → **10**（10/10 通过）

### 变更（适配 dsh 0.1.5 的执行档位）

- dsh 0.1.5 起**没有默认 profile**：裸跑 `dsh` 直接报 `error: --profile <name> is required`。
  本项目的 CLI 模式已封装为 `--profile headless`，用户无需手敲。
- dsh 0.1.5 新增 `dsh.configTrees` 挂载机制，`agent-presets` 从发布包内 `config/` 迁出；
  本项目的 `brand-patch` 已随之调整落点。

### 文档

- `README.md`：版本锁定表、dsh 徽章、变更要点（重写为 `0.1.1-rc.2 → 0.1.5-rc.2`）、
  新增「运行模式」章节与 `config/launch.conf` 说明、目录结构、维护者升级步骤
  （新增「重定 peer 清单」与「跑冒烟测试」两步）。
- `docs/COMPATIBILITY.md`：验证表按 `0.1.5-rc.2` 复核并补充 6 项实测；
  新增 `0.1.1-rc.2 → 0.1.5-rc.2` 逐条变更追踪与**冲突差异表**（7 项定制逐条说明保留原因）；
  已知坑位补充「补齐清单必须逐版本重定」及「整文件沿用补丁的高危性」。
- `docs/TROUBLESHOOTING.md`：新增「peer 依赖补齐清单的重定方法」完整操作章节
  （含可直接运行的 `refscan-registry.py`）；症状表新增 4 条（`ERR_MODULE_NOT_FOUND`、
  `--profile is required`、`401`、`0.0.0.0` 拦截残留）。
- `docs/RELEASE_README_SYNC.md`：第 6 节扩写为「三方校验的检测边界」「按新基线 + 定制意图重建」
  三小节，并明确**默认按重做执行**；操作步骤与验收检查表同步补充。
- `scripts/COMMANDS.md`、`.github/RELEASE_NOTES.md`、`.github/workflows/release.yml`：同步更新。

### 验证

- **冒烟测试 9/9 通过（100%）**，退出码 0，无跳过、无注释、无屏蔽：
  依赖就绪 / 模块解析 / 补丁基线校验 / headless CLI / Web 启动 / 首页 HTTP / 首页标题 /
  静态资源 / 端口监听。
- `@deepseek-ai/*` 模块解析：95 个说明符全部可解析，缺失 0。
- Web 首页全链路：`token → 303 + Set-Cookie → cookie → 200`，`<title>USB Harness</title>`，
  4 个 JS/CSS 资源全部 HTTP 200；486 处 `deepseek` 均为 `@deepseek-ai/` 包名路径，品牌零泄漏。

---

## [0.1.1-rc.2.2] — 2026-08-31

### 修复（检查更新误报「没有可用更新」）

- **根因①：GitHub Release 检测无重试**。`api.github.com` 在国内网络下易一次超时，
  检测被静默跳过 → 只剩 dsh 检测（无更新）→ 误报「已是最新 / 没有可用更新」。
  - 修复：GitHub 检测重试 3 次（超时 8s、间隔 1s）；仍失败时明确提示
    「无法连接 GitHub（已重试 3 次）」并给出 Releases 页链接，不再静默。
- **根因②：版本比较只有字符串相等判断**，无排序兜底，也无法识别「本机高于线上」。
  - 修复：新增语义化版本比较 `Compare-Version`（Windows）/ `cmp_version`（Unix），
    支持 `x.y.z` 与 `x.y.z-rc.a[.b]`，正确处理 `0.1.1-rc.2 < 0.1.1-rc.2.1 < 0.1.1`、
    `rc.2.9 < rc.2.10`（数值段比较）。
  - 更新判定改为「线上 > 本机」才算有更新；本机高于线上时单独提示
    「可能线上被回滚或未同步」。

### 新增（控制台版本显示）

- 启动横幅（第一屏）新增 `版本 : v<版本号>`，配合原有状态面板「程序版本」行；
  统一读取 `.ready.flag` 的 `harness=` 行（回退 `HARNESS_VERSION` 文件），
  旧版包显示「未记录（旧版包）」。

### 验证

- `Compare-Version` / `cmp_version` 单测 9 用例（PS + bash 双端）全部通过。
- 冒烟测试（Windows 含 check-only 真实网络检测 + Linux RT job）全绿。

---

## [0.1.1-rc.2.1] — 2026-08-31

### 修复（根治「node 不是内部或外部命令」/ `Object.hasOwn` 插件加载失败）

- **上一轮修复只做了「把便携 node 提到 PATH 最前」的兜底，没有切断根因**：
  dsh 的 `dsh.cmd` / `.bin/dsh` 垫片（`#!/usr/bin/env node` 的 Windows 版）依然靠
  **PATH 找 node**。实测在装有旧系统 node 的机器上，`Show-Status` 显示正常
  （便携 node v22.23.2），但启动 Web 时插件树加载失败
  （`dsh: plugin tree failed to load`，源自 `dsh-app-boot/lib/index.js` 的 boot 抛错），
  即旧系统 node 仍会在某条路径上被垫片解析到。
- **根治方案：不再经过垫片，直调 CLI 入口**。
  - `launch-windows.ps1` / `upgrade-windows.ps1` / `launch.sh` / `upgrade-unix.sh`
    一律用**便携 node 的绝对路径**直调 `.cache/app/node_modules/@deepseek-ai/dsh/lib/bin.js`
    （新增 `Invoke-Dsh` / `dsh()` 统一入口；垫片仅作 bin.js 缺失时的回退）。
    从此「机器有没有 node、node 多旧」都与 dsh 的解析无关。
  - 启动 Web 时不再用 `2>&1 | Tee-Object`（PowerShell 会把 dsh 的每行 stderr 包成
    ErrorRecord 以整屏红块显示，真实错误被淹没）。改为 stdout 实时回显 + 记日志、
    stderr 落 `data/logs/dsh-web.err.log`，退出码非 0 时打印错误尾部，失败原因直接可见。

### 构建管线 / 回归测试

- **新增 RT（回归测试）`scripts/tests/test-node-resolution.ps1` / `.sh`**：
  在临时沙箱用真实 node + stub dsh，在两种受控 PATH 下断言 `launch status` 仍解析到
  便携 node——场景 A：PATH 无任何 node；场景 B：PATH 前置打印 `v14.0.0` 的旧 node。
  附两个负对照（垫片在这些 PATH 下必然被带偏 / 报 node 找不到），证明测试环境有效、
  且「有人把启动器改回垫片调用」时测试会立即变红。已接入 `smoke-test.yml`
  （Windows 步骤 + 新增 ubuntu-latest 回归 job）。
- `release.yml`：tag 校验放行包装补丁号——tag 须等于 dsh 版本，或在 dsh 版本后追加
  纯数字后缀（如 `0.1.1-rc.2.1`）。

---

## [0.1.1-rc.2] — 2026-08-30

### 变更

- **版本号体系切换**：由外壳自编号（v1.0.x）改为跟随适配的 dsh 版本。
  Release tag / HARNESS_VERSION / `.ready.flag` 的 `harness=` 行统一为 dsh 版本号。
- 内容与 v1.0.5 相同（含 v1.0.5 的 PATH 修复），仅版本标记改为新体系。
- `release.yml`：tag 过滤由 `v*` 改为 `[0-9]*`；新增硬校验
  **tag 名必须等于 setup 脚本锁定的 `$DshVersion`**，防止「打错 tag / 装错 dsh 版本」。

---

## [1.0.5] — 2026-08-30

### 修复

- **dsh 垫片 node 解析问题（两个症状一个根因）**：
  - 症状①：启动器 `Show-Status` / 检查更新报 `node 不是内部或外部命令`（干净机器无系统 node）。
  - 症状②：装了旧系统 node（<16.9，无 `Object.hasOwn`）的机器，Web 打开报
    `Failed to load plugins. Object.hasOwn is not a function`。
  - 根因：`dsh.cmd` / `.bin/dsh` 是 npm 生成的垫片，`.bin` 目录下没有 node.exe，**靠 PATH 找 node**；
    而启动器此前只有 `Start-Web` 预置了便携 node 的 PATH，`Show-Status`、`upgrade-*` 等路径没有。
  - 修复：`launch-windows.ps1` / `upgrade-windows.ps1` 脚本顶部统一把便携 node 目录提到 PATH 最前
    （`launch.sh` / `upgrade-unix.sh` 同步 `export PATH`），本进程内所有 dsh/node 调用
    （状态 / 启动 / 检查更新 / 升级自检 / 子进程 setup/upgrade/reset，自动继承）都命中便携 node 22.23.2，
    与系统是否装了 node、装了什么版本无关。
- 文档：`docs/TROUBLESHOOTING.md` 与 `scripts/COMMANDS.md` 新增两条排查指引
  （明确：请始终用 launch.bat / launch.sh 启动，不要命令行直接敲 dsh）。

---

## [1.0.4] — 2026-08-30

### 新增

- **启动器「检查更新 / 升级」功能**：
  - 菜单新增 `[2] 检查更新`（直通命令 `check-update` / `upgrade`），双层检测：
    ① 本项目新 Release（GitHub，主路径，提示浏览器下载，数据可沿用）；
    ② 上游 dsh 新版（npm，npmmirror 优先回退官方源，需项目适配后才会提供升级）。
  - 维护者可 `upgrade -DshVersion <v>` 强制升级：自动校验 `PeerFix` / `PEERS` 与目标版本
    一致（不一致直接阻断，退出码 4）；升级过程写 journal → `.cache/app` 改名备份 →
    重装 → 自检（版本 + 随机空闲端口 HTTP 探测 + 无模块缺失）→ 成功清理 / 失败自动回滚。
  - 升级只动 `.cache/`，**`data/dsh/`（配置/密钥/会话）自始至终零改动**。
  - 断电/中断自动裁决恢复：下次启动时以「app 能跑且版本与 flag 一致」为真值锚点，
    幂等处理残留（`.cache/app.bak-upgrade` + `.cache/upgrade.state`）。
- `scripts/upgrade-windows.ps1` / `scripts/upgrade-unix.sh`：检查更新 / 升级 / 回滚脚本（退出码 0-6）。
- `HARNESS_VERSION` 文件与 `.ready.flag` 的 `harness=` 行：记录程序版本，供检查更新比对。

### 修复

- **`scripts/setup-unix.sh` Linux/macOS 全新安装必崩**：`NODE_TARBALL` 在全新安装路径被
  引用但从未赋值（`set -u` 直接退出）。已补赋值与 `mkdir -p`。
- **`upgrade-windows.ps1` 在 Windows PowerShell 5.1 下无法解析**：文件缺 UTF-8 BOM
  （PS 5.1 按 ANSI/GBK 读取中文导致语法错乱），且误用 PS7 才有的 `??` 运算符。
  均已修复；`build-release.ps1` 同步补 BOM。

### 构建管线

- `release.yml`：打包前写 `HARNESS_VERSION`；`.ready.flag` 增加 `harness=` 行；
  压缩清单纳入两个文件。
- `smoke-test.yml`：新增「就绪标记生成走真实 setup 脚本路径」断言（flag 含 `harness=` 行
  且值正确）+「`upgrade -CheckOnly` 退出码 ∈ {0,1,2}」冒烟。

---

## [1.0.3] — 2026-08-30

### 修复

- **react 版本漂移**：peer 补齐列表里用的是 `react@latest` / `react-dom@latest` /
  `@types/react@latest`，当前会拉到 **react 19.x**，而 `dsh-web-frontend` 依赖的是
  `react@^18.2.0`——跨大版本，前端渲染存在实际风险。现已锁定为 `^18.3.1` /
  `@types/react@^18.3.12`，与 dsh 期望一致。
  - 影响：v1.0.2 及更早包可能装入了 react 19。**建议所有用户更新到 v1.0.3。**

### 构建管线（不影响包内功能，但消除后续升级的隐患）

- **peer 列表单一数据源**：CI 里的 25 个 peer 包此前是硬编码的 `^0.1.1-rc.2`，与安装脚本的
  `$DshVersion` 脱钩——将来升级 dsh 若只改脚本，CI 会装出新主包 + 旧 peer，静默产出坏包。
  现改为**从 `scripts/setup-windows.ps1` 解析 `$PeerFix` 列表**，并校验其中 `dsh-*` 的版本
  必须与 `DSH_VERSION` 一致，不一致即构建失败。
- **补丁基线断言进 CI**：新增构建步骤，断言 `brand-patch` 的改写基线等于本次安装的 dsh 版本。
  以后「升了版本号却没同步补丁」会在**构建阶段**失败，而不是等用户下载后才发现启动崩溃。
- 新增 `scripts/dsh_patch_compat_check.py`：补丁兼容性校验工具（基线判定 + 变更判定 + 基线断言），
  本地与 CI 共用。

---

## [1.0.2] — 2026-08-30

### 修复

- **补丁基线错配（关键）**：`brand-patch` 内 17 个补丁文件此前已按 dsh `0.1.1-rc.2` 改写，
  但两处版本变量仍锁定 `0.1.1-rc.1`。这会导致安装 rc.1 运行时、却覆盖 rc.2 补丁——
  `dsh-llm-deepseek` 引用了 rc.2 才有的 `deadline` / `withFileLock` / `writeFileAtomic` /
  `resolveDshHome` 等导出，**启动必然报 `ERR_MODULE_NOT_FOUND`**。
  现已将 `scripts/setup-windows.ps1` 与 `scripts/setup-unix.sh` 的版本锁定同步为 `0.1.1-rc.2`。
  - 已逐个对 17 个补丁文件做 `patch / rc.1 / rc.2` 三方 diff 验证，
    基线全部为 rc.2（与 rc.2 的差异仅 4~27 行品牌与中文本地化改动），**无需重做任何补丁**。

### 新增

- `docs/RELEASE_README_SYNC.md`：dsh 版本升级时 README 的同步规范。
  明确变更信息来源（上游无 CHANGELOG、不发 GitHub Release，只能取 tag 区间 compare、
  用户文档 diff、npm 元数据）、五类变更判定标准、README 必同步的 5 个区块、
  新旧用法对照写法与验收检查表。
- README：新增「dsh 0.1.1-rc.2 变更要点」（含失效配置项对照与适用边界）、
  「如何升级 dsh 版本（维护者）」；功能特性补充「图片输入（多模态）」。
- `docs/COMPATIBILITY.md`：新增「版本变更追踪」章节，逐条列出 rc.1→rc.2 变更并附 commit 证据。
- 本文件（`CHANGELOG.md`）。

### 变更

- 上游 dsh：`0.1.1-rc.1` → `0.1.1-rc.2`。
  破坏性变更包括 `maxRequestImageBytes` 拆分为 `maxRequestFilesBytes` + `maxInlineRequestImageBytes`、
  权限预设 Settings 命名空间 `permission` → `permissionPresets`、
  图片区域读取（image-region）移除。详见 README 与 COMPATIBILITY。

---

## [1.0.1] — 2026-08-24

### 新增

- **符号链接复制回退补丁**：dsh 在 `data/dsh/profiles/node_modules/` 下创建符号链接失败时，
  自动改为复制真实包目录，使 exFAT / FAT32 也能正常运行核心功能。
- 启动时提示「正在启动服务，浏览器将在就绪后自动打开」。
- 文档与视觉：README Banner（SVG）、GitHub 社交预览图（1280x640）、SEO 徽章与关键词。

### 修复

- 浏览器自动打开探测逻辑改为**连接探测**——原先的 `TcpListener` 绑定探测
  在 Windows 上会把被占用的端口误判为空闲。

### 变更

- **U 盘格式要求放宽**：由「必须 NTFS」改为「推荐 NTFS，exFAT / FAT32 亦可运行」
  （代价是 `profiles` 目录多占约几百 MB 空间）。

---

## [1.0.0] — 2026-08-22

首个公开版本。

- 便携外壳：便携 Node.js + 预置 dsh 依赖，U 盘即插即用，零宿主机污染。
- `DSH_HOME` 重定向到 `data/dsh/`，密钥 / 配置 / 会话随盘。
- 交互式启动器（中文菜单：启动 / 重置 / 退出），首启自动安装。
- 品牌改造（`brand-patch`）：去 DeepSeek 化 + 界面中文本地化。
- 中国网络适配：Node 走 npmmirror、npm 用 `registry.npmmirror.com`，失败自动回退官方源。
- U 盘预置离线安装包，重装不依赖网络。
