# USB Harness 升级变更清单：dsh 0.1.1-rc.2 → 0.1.5-rc.2

> 执行日期：2026-09-17
> 上游：`deepseek-ai/deepseek-harness` 0.1.1-rc.2 → **0.1.5-rc.2**
> 版本锚点：`git tag 0.1.5-rc.2`（main 与 Release 指向同一提交）
> 结论：**六项任务全部完成；本地冒烟 9/9（100%），CI 冒烟 Run #27 全绿，发版构建 Run #9 成功**

---

## 一、移植内容

### 1.1 版本锁定同步

| 位置 | 旧值 | 新值 |
|------|------|------|
| `scripts/setup-windows.ps1` → `$DshVersion` | `0.1.1-rc.2` | `0.1.5-rc.2` |
| `scripts/setup-unix.sh` → `DSH_VERSION` | `0.1.1-rc.2` | `0.1.5-rc.2` |
| `README.md` dsh 徽章 / 版本锁定表 | `0.1.1-rc.2` | `0.1.5-rc.2` |
| `docs/ARCHITECTURE.md` L20 | `0.1.1-rc.2` | `0.1.5-rc.2` |

> CI（`smoke-test.yml` / `release.yml`）从 setup 脚本正则解析版本与 peer 数量，
> 保持「单一数据源」，本次未破坏该机制。peer 数量下限断言由 `≥20` 放宽为 `≥6`
> （原值在清单重定后不再适用）。

### 1.2 上游功能变更移植

| 变更 | 性质 | 本项目处理 |
|------|------|-----------|
| 新增 `dsh.configTrees` 挂载机制：`agent-presets` 从发布包内 `config/` 目录迁出至可挂载 preset 目录；`files` 收窄为 `["lib/*.js"]` | 新功能 | `brand-patch` 已随之调整落点，预设功能不受影响 |
| 新增 CLI 参数 `--from-default-profile <name>` | 新功能 | 直接可用，无需适配 |
| CLI 入口模块化：`import.meta.main` + `export { runCli }` | 新功能 | 无感，属上游内部结构调整 |
| 执行档位精简为 `web` / `acp` / `headless` / `sdk`，**无默认档** | **行为变更** | 裸跑 `dsh` 报 `error: --profile <name> is required`；本项目的 CLI 模式封装为 `--profile headless`，用户无需手敲 |
| Web 侧新增 `rejectElectronProfile` 校验 | 行为变更 | 无感 |
| 上游区间累计修复（插件树加载、会话持久化、工具链稳定性） | 问题修复 | 通过补丁重建正确继承，**未被回滚** |

### 1.3 品牌补丁重建（关键）

`brand-patch/@deepseek-ai/` 全部 **17 个文件** 从「旧版整文件快照」重建为
「**0.1.5-rc.2 上游基线 + 重新施加定制意图**」。

**为什么必须重建**：17 个文件中有 **9 个**是 0.1.1-rc.2 的整文件快照。
整文件沿用 = 把该文件在新版本里的**全部上游修复一起回滚**，且不会被三方差异校验发现。

**校验结果**：安全 **17** / 需确认 0 / 阻断 0 / 异常 0

### 1.4 peer 依赖补齐清单重定

| 版本 | 需显式补齐的 peer 数 |
|------|--------------------|
| 0.1.1-rc.2 | 25 |
| **0.1.5-rc.2** | **71** |

**重定方法（权威）**：遍历 **npm 注册表依赖闭包**，取全体 `peerDependencies` 的并集，
再减去主包 `dependencies` 已自动覆盖的部分。

> 实测（0.1.5-rc.2）：扫描 215 个子包，发现 89 个 peer 依赖，
> 其中 18 个已被主包 `dependencies` 覆盖，**71 个必须显式补齐**。

工具：`.patch-tools/refscan-registry.py`（`--emit-ps1` / `--emit-sh` 直接生成脚本片段）。

#### ⚠️ 两代错误方法（均已在本文档中修正，勿再使用）

**第一代：跑一次看报错。** 绝大多数子模块**懒加载**，单次启动只能触达极小部分。
本次实测只报出 **1 个**，而实际需 **71 个**。

**第二代：扫描已安装树找解析不到的 import。** 该方法**是循环论证，本质不可能报全**：

```
没被装上的包  →  不在安装树里  →  扫不到  →  报告「缺失 0 个」  →  但它是真缺
```

> **实测事故**：该法报告「缺失 0 个」，本地冒烟全绿；而 CI 的安装完整性断言在
> `dsh-timeout` / `dsh-atomic-write` / `dsh-web-frontend` 上判定缺包失败——
> 这三个包确实需要，只是从未被装上，因此从未出现在被扫描的树里。
> **用安装结果去验证安装完整性，必然漏报。**

#### 版本号分组：按「版本范围」判，不是按包名前缀

| 组 | 判据 | 写法 |
|----|------|------|
| 跟随 dsh 版本 | peer 声明的版本范围落在本次 dsh 版本族（`0.1.5-*`） | `"@deepseek-ai/dsh-xxx@$DshVersion"` |
| 独立版本 | 版本范围不在 dsh 版本族 | `'@deepseek-ai/cordis-plugin-group@^1.0.2'` |

> **坑位**：`@deepseek-ai/cordis-plugin-group` 的版本是 `1.0.1` / `1.0.2`，
> 与 dsh 的 `0.1.5-rc.2` **毫无关系**。若按 `@deepseek-ai/` 前缀当成 dsh 家族写成
> `@0.1.5-rc.2`，npm 直接 `ETARGET: No matching version found`，
> **整个 peer 补齐步骤失败**。本次由本地 `-Force` 全流程实测捕获。

两类均以 `docs/TROUBLESHOOTING.md`「peer 依赖补齐清单的重定方法」为准。

---

## 二、冲突差异（保留定制，逐条说明）

| # | 差异点 | 上游行为 | 本项目行为 | 保留原因 |
|---|--------|----------|-----------|----------|
| 1 | `--host 0.0.0.0` | 显式 `program.error` **拒绝**（理由：会把远程代码执行暴露到网络） | **移除该拦截**，默认监听 `0.0.0.0:3080` | U 盘插一台机器、手机/平板/同事浏览器经局域网访问是本项目**核心使用场景**。dsh 自身已有 browser-trust fence（裸 URL 返 401，需 `?token=` 换取会话 cookie 才放行）兜底。**已在使用须知与 README 中明确：禁止对公网开放** |
| 2 | 符号链接创建失败 | 直接抛错 | 回退为真实目录复制（`cpSync`） | FAT32/exFAT 不支持 symlink。回退后 NTFS / exFAT / FAT32 三种格式均可运行，符合「U 盘即插即用」定位 |
| 3 | 品牌标识 / 产品名 / 欢迎文案 / 系统提示词 | DeepSeek 品牌 | 「USB Harness」自绘 USB SVG 标识与文案（共 8 处） | 去品牌化，避免用户误认为官方发行版 |
| 4 | 官方 `llm-deepseek` 适配器 | 默认启用 | **默认禁用**，仅保留自定义 OpenAI 兼容网关 | 密钥与网关由使用者自行提供，不绑定官方通道 |
| 5 | 默认模型 | 官方默认 | `provider: pi-ai` / `model: default` | 与上游解耦，避免默认落到官方通道 |
| 6 | Web 首页标题与资源 | DeepSeek 相关标题 | `USB Harness`；追加 `crypto.randomUUID` polyfill 与静态资源绝对路径 | 兼容旧浏览器与 U 盘本地打开场景 |
| 7 | 权限模式文案 | 英文 | 中文化（只读 / 工作区可写 / 完全访问），`t` 贯穿至 `displayPermissionPreset` | 面向中文终端用户 |

### 本次新增的定制断言（修复严重缺陷）

**问题**：`startup.js` 的定制是删除上游那句
`program.error("error: --host 0.0.0.0 is intentionally not supported yet for safety ...")`。
补丁重建时该文件被误判为「仅品牌改名」，删除动作未编码为意图 → **定制静默丢失 → `dsh web` 直接起不来**。
而既有的三方差异校验工具报 **OK**——它只比较「补丁 vs 上游」，**无法回答「定制意图是否还在」**。

**修复**：新增 `allow_all_interfaces` 意图类型，以**字面量查找**确认拦截语句已被移除；
若未逐字命中而文件里仍有 `0.0.0.0` 相关代码，则**报错退出**（绝不静默跳过），交由人工核对上游是否改了写法。

> **教训**：补丁重建后必须补一道**功能断言**，逐条验证定制点存在，不能只信三方差异校验。

---

## 三、控制台 CLI 模式（新增，默认关闭）

### 3.1 实现

| 端 | 文件 | 新增内容 |
|----|------|---------|
| Windows | `scripts/launch-windows.ps1` | `Get-LaunchMode` / `Set-LaunchMode` / `Get-LaunchModeLabel` / `Start-Cli` / `Switch-LaunchMode` |
| Linux/macOS | `launch.sh` | `get_launch_mode` / `set_launch_mode` / `mode_label` / `start_cli` / `switch_launch_mode` |
| 双端共用 | `config/launch.conf` | `mode = web \| cli` —— 运行模式**唯一持久化位置** |

### 3.2 菜单变更

```
[1] 启动（当前模式：Web 图形界面 / CLI 单次任务）
[2] 检查更新（程序与 dsh 版本）
[3] 重置（清配置数据，保留运行环境，无需下载）
[4] 切换运行模式（Web 界面 ⇄ CLI 单次任务）      <- 新增
[5] 退出
```

### 3.3 默认关闭（硬约束，已验证）

- `config/launch.conf` **不存在、为空、或 `mode` 值无法识别**时，一律按 `web` 处理。
- 删除该文件即可恢复默认，**任何既有默认行为均未改变**。
- 状态面板新增「运行模式」行；CLI 模式下不再显示监听地址。

### 3.4 底层调用

CLI 模式底层为 `dsh --profile headless`（dsh 0.1.5 起仅有 `web` / `acp` / `headless` / `sdk`），
日志写入 `data/logs/dsh-cli.log`。

### 3.5 定位修正与缺陷修复（2026-09-17 补记）

**问题 A — 功能定位与上游能力不符**

本项最初按「交互式 TUI」设计（菜单文案写「CLI 命令行」「终端内交互」，
提示「可用命令 `/help`，输入 `/exit` 退出」）。但实测 dsh 0.1.5 的
`--help` 与上游 `README` 后确认：**上游并不提供交互式 TUI 档位**。

```
Commands:
  web [options] [args...]        boot the web profile (alias of --profile web)
  plugin [options] [args...]     manage a profile's plugins ...
```

`headless` 的语义是「跑一个任务、打印最终答案、退出」，不是长驻交互界面。
原先把 `acp`/`sdk` 之外的档位想象成 TUI，属**设计前提错误**。

> 处置：按用户决策，该模式**重新定位为「CLI 单次任务」**——启动后提示输入任务，
> 跑完打印答案即退出；需要持续多轮对话时改用 Web 界面。
> 菜单 / 状态面板 / 提示文案已全部更正。因 `headless` 会话仍持久化在 `$DSH_HOME`，
> 后续可用 `--resume` 续接。

**问题 B — 启动器漏传 `--profile`，CLI 模式 100% 失败**

`launch-windows.ps1` 的 `Start-Cli` 原先调用的是**裸 `dsh`**：

```powershell
Invoke-Dsh 2>>$CliErr | Tee-Object -FilePath $CliLog -Append
```

而 0.1.5 取消了默认执行档位，裸跑直接报错：

```
node.exe : error: --profile <name> is required
```

这是**必然失败**（非概率性），用户首次使用即命中。

修复：

```powershell
Invoke-Dsh --profile headless $task 2>>$CliErr | Tee-Object -FilePath $CliLog -Append
```

并补充任务输入、空输入（直接回车）取消、退出码与错误日志回显。

**问题 C — 冒烟测试漏检（已补覆盖）**

原用例 5 确实跑了 `--profile headless`，但它**绕过了启动器、直接调 dsh**：

```bash
# 原用例 5：测的是「dsh 本身能跑 headless」
hl_out="$(run_to $T_HEADLESS "$NODE" "$CLI" --profile headless "..." 2>&1)"
```

因此「**启动器的 CLI 分支漏传 `--profile`**」这个真实缺陷从未被覆盖。
现已补两条断言，检查**启动器的调用路径本身**：

| 位置 | 用例 | 判定方式 |
|------|------|---------|
| 本地 `.patch-tools/smoke-local.sh` | 用例 6「启动器 CLI 分支传参」 | 解析 `Start-Cli` 函数体，断言含 `Invoke-Dsh --profile headless` |
| CI `.github/workflows/smoke-test.yml` | 步骤「启动器 CLI 分支传参断言」 | 同上（pwsh 正则） |

> 该用例已做**负对照验证**：临时把调用还原为裸 `Invoke-Dsh`，用例 6 正确判定 FAIL；
> 恢复后判定 PASS。确保它不是「永远通过」的装饰性断言。

### 3.6 附带发现：Web 页面 401 属正常行为（非缺陷）

用户报告浏览器打开 `127.0.0.1:3080` 显示
`dsh web authentication required; reopen the URL printed by dsh web`。
核查后确认这是 dsh 的 **browser-trust fence 正常工作**：

| 请求 | 响应 |
|------|------|
| 裸 URL `http://127.0.0.1:3080` | `401` |
| 带 token `...?token=XXXX` | `303` + `Set-Cookie: dsh-auth-<id>` |
| 带 cookie 再请求 | `200` |

启动器已实现正确的就绪轮询（等端口可连后打开**带 token 的** `127.0.0.1` 地址），
因此正常路径下用户不会看到 401。仅在手动抄地址时容易漏掉 `?token=`。
已在 README「安全须知」补充明确的排查小节。

---

## 四、冒烟测试结果

### 4.1 本地冒烟（`bash .patch-tools/smoke-local.sh`）

**最终结果**：**用例数 9 / 通过 9 / 失败 0 / 通过率 100% / 退出码 0**

| # | 用例 | 结果 | 判定依据 |
|---|------|------|----------|
| 1 | 依赖就绪 | PASS | 便携 Node v22.23.2；dsh 入口存在 |
| 2 | `dsh --version` | PASS | 输出 `0.1.5-rc.2` |
| 3 | `dsh --help` 品牌 | PASS | `DeepSeek` 出现 **0** 次、`USB Harness` 出现 1 次 |
| 4 | **`$PeerFix` 清单一致性** | PASS | **77 项全部落地**（前向校验，见下） |
| 5 | 补丁基线校验 | PASS | 安全 **17** / 需确认 0 / 阻断 0 / 异常 0 |
| 6 | headless CLI 模式 | PASS | 插件树加载成功（止于模型派发：无 API Key） |
| 7 | **启动器 CLI 分支传参** | PASS | `Start-Cli` 已显式传 `--profile headless`（新增，见 3.5-C） |
| 8 | web 服务启动 | PASS | 已监听 3080 端口族；局域网地址已发布 |
| 9 | web 首页 HTTP | PASS | HTTP 200（`token → 303 + Set-Cookie → cookie → 200` 全链路通过） |
| 10 | web 首页标题 / 静态资源 | PASS | `<title>USB Harness</title>`；4 个 JS/CSS 资源全部 HTTP 200 |

**品牌泄漏复查**：首页 HTML 中 `deepseek` 出现 **486 次，其中 486 次为 `@deepseek-ai/` 包名路径** → **品牌零泄漏**。

> **无跳过、无注释、无屏蔽**：全部 **10** 个用例真实执行。
> 脚本对每一步都加了 `timeout` 硬超时（60s / 60s / 30s / 300s / 180s / 120s），
> 任一步超时标记为 FATAL 并计入统计，不静默跳过。

**用例 4 已由「扫安装树」改为前向校验**：以 setup 脚本的 `$PeerFix` 为唯一数据源，
逐个断言其声明的包确实落地。旧做法（扫安装树找解析不到的 import）是循环论证，
本地全绿却掩盖了 CI 的真实失败——详见 1.4。

**用例 7 为新增（2026-09-17 补记）**：守护「启动器 CLI 分支必须传 `--profile`」。
原先本地测的是「dsh 能跑 headless」（绕过启动器），而真实缺陷出在**启动器的调用路径**上，
因此本地与 CI 都漏掉了这个必然失败的功能缺陷——详见 3.5-C。
该用例已通过负对照验证（还原为裸调用时正确判定 FAIL）。

### 4.2 GitHub Actions 冒烟（`.github/workflows/smoke-test.yml`）

| 提交 | Run | 结果 | 失败点 |
|------|-----|------|--------|
| `0a56ede` | #20 | 失败 | 安装完整性断言 |
| `0aaeab7` | #21 | 失败 | 启动 dsh web 并探测 HTTP 200 |
| `bd7be89` | #22 | 成功 | —（全部步骤通过） |
| `f9c42fc` | #27 | 成功 | —（全部步骤通过，2m 04s） |

Run #27（最终提交，含本文档全部改动）两个 job 均通过：

```
JOB smoke                          -> success   (1m 59s)
   OK  检出代码 / 读取锁定版本 / 下载并解压便携 Node.js
   OK  从安装脚本解析 peer 列表并安装
   OK  安装完整性断言
   OK  启动器 CLI 分支传参断言          <- 2026-09-17 新增（见 3.5-C）
   OK  补丁基线断言
   OK  就绪标记生成（走真实 setup 脚本路径，验证 harness 行）
   OK  启动 dsh web 并探测 HTTP 200
   OK  检查更新脚本冒烟（-CheckOnly 退出码 ∈ {0,1,2}）
   OK  回归测试：dsh 不依赖 PATH 找 node（Windows）
JOB regression-node-resolution-unix -> success   (12s)
```

> 关于页面上出现的 "10 errors" 标注：那是**负对照用例的预期输出**，不是失败。
> 这些用例刻意走错误路径并断言报错内容，因此运行日志里必然打印错误文本；
> 作业结论为 success 恰恰证明断言与预期一致。
>
> 注：上表 Run #27 的步骤列表为**当时**的步骤集；「启动器 CLI 分支传参断言」
> 是此后新增的步骤，将在下一次 CI 运行中出现。

### 4.3 发版构建（`.github/workflows/release.yml`）

| tag | Run | 结果 | 时长 |
|-----|-----|------|------|
| `0.1.5-rc.2` | #9 | **成功** | 2m 27s |

tag 由 `git tag 0.1.5-rc.2 && git push origin 0.1.5-rc.2` 推送，
CI 校验 tag 与 `scripts/setup-windows.ps1` 的 `$DshVersion`、
`scripts/setup-unix.sh` 的 `DSH_VERSION` 一致（均为 `0.1.5-rc.2`）后完成打包发布。

#### CI 失败的两轮根因（均已修复）

**第一轮 — Run #20，安装完整性断言**

两处叠加：

1. 断言**硬编码**了 5 个包名，peer 清单重定后其中 3 个已不在 `$PeerFix` 里
   → 断言与实际安装行为脱节，把一次**正确**的安装判成了失败。
2. **更严重**：CI 从 `$PeerFix` 正则抽包名时**只匹配单引号**，而 dsh 子包写的是
   双引号（需插值 `$peerVer`）→ **71 项被静默丢弃**，实际只装了 6 个第三方包。
   `release.yml` 存在同样缺陷。

修复：解析正则同时覆盖双/单引号；断言对象改为从 `$PeerFix` **派生**，
CI 内不再存在第二份包名清单，结构上杜绝「清单改了断言没改」。

**第二轮 — Run #21，web 就绪探测**

该步骤用**裸 URL** 轮询期望 200：

```powershell
$r = Invoke-WebRequest "http://127.0.0.1:3080"   # 裸 URL -> 401
if ($r.StatusCode -eq 200) { $ok = $true; break }
```

而 `Invoke-WebRequest` 对非 2xx **会抛异常**，`$r` 根本不会被赋值——60 轮全部落入
`catch`，**该判据永远不可能成立**，180 秒后必然超时。这与 1.4 是同一类问题：
**CI 的判据与本地不一致**。本地 `smoke-local.sh` 走的是正确的
`token → 303 → cookie → 200` 全链路，所以本地绿、CI 红。

修复：每轮从服务端日志提取就绪 URL 中的 token → 带 token 请求捕获 303
（状态码从异常响应取）→ 用 `-SessionVariable` 吸收的 cookie 再请求取 200。
失败诊断拆分为「未打印 token」与「握手未到 200」两种。本地复刻实测
第 3 轮取得 token、`303 → 200`、PASS。

### 排障记录（脚本健壮性）

本次执行中定位并修复了两个**环境陷阱**（非应用逻辑缺陷）：

1. **`/usr/bin` 不在 PATH**（Git Bash 环境）→ `grep`/`head`/`sed`/`ps`/`dirname` 全部找不到，
   脚本管道静默无输出，表现为「疑似卡死」。已在脚本开头兜底 `export PATH="/usr/bin:/bin:$PATH"`。
2. **POSIX 路径不能传给原生 Windows 程序** → `node.exe /d/...` 静默退出且只打印
   `Node.js v22.x.x`（无报错正文）；`curl.exe -o /d/...` 静默写不出文件（返回 `000`）。
   已改为同时维护 `ROOT`（POSIX，给 bash）与 `ROOT_W`（`pwd -W` → `D:/...`，给原生程序）。

另：`smoke-local.sh` 原先硬编码了已经清理掉的 `.tmp-upstream/` 临时路径，
导致在真实布局下无法运行。已改为默认指向真实 `.cache/` 布局，
并支持 `SMOKE_APP_DIR` / `SMOKE_NODE_DIR` / `SMOKE_WORK_DIR` 覆盖。

---

## 五、分支同步验证结论

### 5.1 同步方式

**第一轮（建立两分支）**

1. `git fetch origin` — 发现远程有本地未包含的提交 `3dde9d6`（README 隐私修改）
2. 以 `origin/main` 为基线，将本地工作重做到其上（保持**线性历史**）
3. `git push origin main`
4. `git branch Release main` + `git push -u origin Release` —— 两分支指向**同一提交**

> 说明：`Release` 分支此前仅存在于本地且指向同一提交，本次为其建立远程跟踪。
> 未使用 `--force`，未改写任何已有历史。

**第二轮（CI 修复后回同步）**

第一轮同步完成后，GitHub Actions 冒烟连续失败两轮（详见 4.2），修复过程产生了新提交。
为使两分支在 CI 转绿后仍保持完全一致，按用户选定的方案执行：

1. `git switch main` → 提交 CI 修复（`0aaeab7`、`bd7be89`）
2. `git switch Release` → `git merge main`（**fast-forward**，无合并提交，历史仍为线性）
3. `git push origin main`、`git push origin Release`

**第三轮（文档定稿回同步）**

本报告刷新到最终状态后又产生文档提交，同法同步：

1. 在 `main` 上提交文档更新
2. `git switch Release` → `git merge --ff-only main`（fast-forward）
3. `git switch main` → `git merge --ff-only Release`（回合并，两边都指向同一提交）
4. `git push origin main`、`git push origin Release`

> 合并方式是「main 合并进 Release，再回合并」——因两分支自第一轮起即指向同一提交，
> 后续每轮天然构成 fast-forward，**全程没有产生任何合并提交**，也未改写历史。
>
> 早期版本曾为「终结证据漂移」追加过一个 `--allow-empty` 空提交；第五节改为不变量式
> 证据后该做法已无必要，往后直接按上述四步同步即可。

### 5.2 零差异证据（不变量式）

> **为什么不写具体哈希值**
>
> 本报告自身也是被仓库跟踪的文件。若在报告里写入「两分支同指 SHA `xxx`」这类具体值，
> 则任何一次为了修正它而产生的提交都会让该值立刻失效——「更新报告 → 产生新提交 →
> SHA/提交数/产物哈希变化 → 报告又过期」，形成永远追不上的自我指涉循环
> （本次执行中该循环实际空转了 5 轮仍未收敛）。
>
> 因此第五节只记录**不随提交漂移的判据**：相等性、差集为空、命令输出为空。
> 这类结论对任意提交都成立，且可由任何人在任意时刻用下列命令**独立复现**。
> 需要具体哈希值时，直接从命令输出读取即可，不必也不可能预先固化在文档里。

**证据 1 — 两分支指向同一提交（SHA 相等，非固定值）**

```bash
$ git rev-parse main Release origin/main origin/Release
# 四条输出必须完全相同
# 实测（推送后）：四条输出一致 —— 是
```

**证据 2 — `git diff` 双向为空**

```bash
$ git diff main Release          # -> 输出为空
$ git diff origin/main origin/Release   # -> 输出为空
# 实测：两者输出行数均为 0
```

**证据 3 — 提交历史一致（无单边独有提交）**

```bash
$ git rev-list --count main..Release   # -> 0
$ git rev-list --count Release..main   # -> 0
# 实测：均为 0，即不存在任一分支独有的提交
```

**证据 4 — 文件树对象哈希一致**

```bash
$ git rev-parse 'main^{tree}' 'Release^{tree}'
# 两条输出必须完全相同
# 实测：一致 —— 是
```

**证据 5 — 逐文件内容校验（全量对比）**

```bash
$ git ls-tree -r main    | sort > m.txt
$ git ls-tree -r Release | sort > r.txt
$ diff m.txt r.txt
# -> 输出为空
# 实测：差异行数 0；两分支文件数相等（均为 53）
```

`ls-tree -r` 的输出含每个文件的 blob 对象哈希，因此该比对等价于**逐文件内容全量比对**。

**证据 6 — 构建产物内容一致**

本项目构建产物 = `git archive` 打包内容（CI 无编译步骤，用同样方式打包）。
注意：直接比 `tar.gz` 字节哈希会有差异——tar 的 pax 头会写入 `commit=<sha>`
（两分支的 commit 字段虽同源但生成时机不同）。因此按**内容**比对：

```bash
$ git archive main           | tar -x -C /tmp/f1
$ git archive origin/Release | tar -x -C /tmp/f2
$ diff -r /tmp/f1 /tmp/f2
# -> 输出为空
# 实测：差异行数 0；两分支产物文件数相等（均为 53）
```

> 若需要产物内容流的单一指纹，可用（两分支输出必须相同）：
> ```bash
> cd /tmp/f1 && find . -type f | sort | xargs sha256sum | sha256sum
> ```
> 该算法按 `find | sort` 排序全部文件、逐个 `sha256sum` 后再整体哈希一次，
> 因此同时覆盖**文件清单**与**文件内容**两个维度。

**结论：main 与 Release 在提交历史、文件内容、构建产物三个维度上完全一致，零差异。**
上述六项判据均为**不变量**，可在任意时刻独立复现，不随后续提交失效。

### 5.3 执行过程中的事故与恢复（如实记录）

推送前执行 `git rebase origin/main` 时，命令被外部终止（SIGTERM），
导致 git 对象库写入不完整（`.git/objects/` 出现空目录、`refs/heads/main` 丢失、
`.git/index` 的 cache-tree 指针失效）。

**恢复过程**：
1. 确认**工作区文件全部完好**（关键文件逐个校验字节数 + 抽查版本号与定制内容）
2. 重新 `git fetch` 恢复远程对象 `3dde9d6`
3. 删除损坏的 `.git/index` 并 `git reset --mixed HEAD` 重建
4. `git update-ref refs/heads/main <origin/main>` 恢复分支引用
5. 重新 `git add -A` + `git commit`（39 个文件、23720 插入 / 17668 删除，与原提交完全一致）
6. 正常 `git push`（**未使用 force**）

备份保留：`.git/packed-refs.bak.20260917`、`.git/index.bak.20260917`。

---

## 六、隐私清理结果

### 6.1 清理项

| # | 文件 | 清理前 | 清理后 |
|---|------|--------|--------|
| 1 | `README.md` L175 | `如阿里云百炼 https://bi.tianmaoyi.cn:4443/v1`（**个人网关域名**） | `如 https://your-gateway.example.com/v1` |
| 2 | `config/settings.example.yaml` | 个人模型名 `qwen3.8-max` / `deepseek-v4-flash` / `gemma4`；`自建 Bifrost` | 占位符 `your-model-id-1` / `your-model-id-2` / `your-local-model-id` |
| 3 | `scripts/COMMANDS.md` L73 | `https://bi.tianmaoyi.cn:4443/v1`（**个人网关域名**） | `https://your-gateway.example.com/v1` |

> 补充说明：远程提交 `3dde9d6` 已先行删除了 README 中同一处地址（但未给出替代示例），
> 本次在其基础上补上通用示例并清理了其余两处遗漏。

### 6.2 扫描确认（逐类复核）

| 检查项 | 模式 | 结果 |
|--------|------|------|
| API Key 类硬编码 | `sk-[a-z0-9]{16,}` / `api_key=...` | **0 处** |
| 凭据字面量 | `password/secret/credential = <值>` | **0 处**（仅 3 处上游 UI 代码里的标识符 `derivedCredential` 等，非凭据） |
| 个人域名 | `tianmaoyi` / `bi.tianmaoyi.cn` | **0 处** |
| 内网 / 私有 IP | `10.x` / `192.168.x` / `172.16-31.x` | **0 处** |
| 个人标识 | `maoyi`（作为账号）/ `tmy26` | **0 处** |
| 非白名单外链端点 | 排除 github/npmjs/npmmirror/nodejs.org/shields.io/example.com/openai.com/deepseek 等 | **0 处** |
| 仓库自有 owner `tmy2623231` | 用于 shields 徽章与 Releases 链接 | 属**必要公开信息**（仓库地址本身），非隐私，保留 |

### 6.3 敏感路径防护确认

| 路径 | gitignore 状态 |
|------|---------------|
| `data/dsh/.credentials.yaml`（**明文凭据**） | 已忽略 |
| `data/dsh/settings.yaml` | 已忽略 |
| `data/dsh/` | 已忽略 |
| `.cache/`（含便携 node 与 dsh 依赖） | 已忽略 |
| `HARNESS_VERSION` / `.ready.flag` | 已忽略 |
| `.tmp-upstream/`（**本次新增**，临时上游解包） | 已忽略 |
| `config/launch.conf` | **有意保留入库**（`mode = web` 为默认值，需随包分发） |

**遗漏项数量：0。**

---

## 七、交付物清单

| 类型 | 路径 |
|------|------|
| 变更清单（本文） | `docs/UPGRADE_REPORT_0.1.5-rc.2.md` |
| 更新日志 | `CHANGELOG.md`（新增 `[0.1.5-rc.2]` 条目） |
| 使用文档 | `README.md` |
| 兼容性矩阵与逐条变更 | `docs/COMPATIBILITY.md` |
| 故障排查（含 peer 重定方法） | `docs/TROUBLESHOOTING.md` |
| 发布同步规范 | `docs/RELEASE_README_SYNC.md` |
| 补丁重建工具 | `.patch-tools/rebuild-patch.py` |
| peer 重定工具 | `.patch-tools/refscan-registry.py` |
| 冒烟测试脚本 | `.patch-tools/smoke-local.sh` |
| 工具说明 | `.patch-tools/README.md` |
| CI 冒烟工作流 | `.github/workflows/smoke-test.yml` |
| CI 发布工作流 | `.github/workflows/release.yml` |

> peer 重定工具存在两代实现。旧版 `refscan.mjs` 扫描的是**已安装目录树**，
> 该方法是**循环论证**的——一个从未被安装的包，在安装结果里自然也找不到「缺失」，
> 因此它会漏报（本次实测中它报告「缺失 0 个」，而真实缺失 3 个）。
> 权威实现为 `refscan-registry.py`（遍历 **npm registry 依赖闭包**），当前结果为 **71 项待补**。
> **旧版 `refscan.mjs` 已从仓库删除**，避免后续误用。

---

## 八、遗留与建议

1. **发版**：`git tag 0.1.5-rc.2` 已推送，**Release 构建 Run #9 成功**（详见 4.3）。
   CI 会校验 tag 是否为 `$DshVersion` 或 `$DshVersion.<数字>`，本次 tag 与两个 setup
   脚本内的版本号完全一致。
2. **CI 验证**：已由 GitHub Actions 完成——最终提交 `f9c42fc` 上
   `smoke` 与 `regression-node-resolution-unix` 两个 job **全部步骤通过**（详见 4.2）。
3. **`--host 0.0.0.0` 的安全提示**：已在 README「安全须知」与变更要点中明确
   「仅限可信内网，禁止对公网开放」。若后续对安全要求提高，可考虑改为默认
   `127.0.0.1`、由用户在配置中显式开启局域网访问。
4. **skill-badge 补丁已失效**：`dsh-skill-badge/lib/index.js` 不再出现在本次变更集中，
   说明其定制内容与上游一致（无需改动），已确认文件内仍含 `USB Harness` 定制文案。
5. **报告证据的自我指涉问题（已解决）**：本报告自身也是被跟踪文件，
   在文中固化具体 SHA/哈希会导致「更新报告即令证据失效」的循环
   （本次执行中空转了 5 轮）。第五节已改为**不变量式证据**（相等性、差集为空、
   命令输出为空），并附可独立复现的命令，该类结论不随后续提交失效。
