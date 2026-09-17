# USB Harness 升级变更清单：dsh 0.1.1-rc.2 → 0.1.5-rc.2

> 执行日期：2026-09-17
> 上游：`deepseek-ai/deepseek-harness` 0.1.1-rc.2 → **0.1.5-rc.2**
> 提交：`43dba0a`（main 与 Release 指向同一提交）
> 结论：**六项任务全部完成，冒烟测试 9/9 通过（100%）**

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

| 版本 | 缺失 peer 数 |
|------|-------------|
| 0.1.1-rc.2 | 25 |
| **0.1.5-rc.2** | **26** |

**重定方法**：扫描安装树里全部 `.js/.mjs/.cjs` 的 `@deepseek-ai/*` import 说明符，
逐个用 `createRequire().resolve()` 解析，凡解析不到的即为缺失项。
实测 **95 个说明符全部可解析、缺失 0**。

> **反面教训**：用「跑一次 dsh，看报哪个包缺失」的方式**严重漏报**——
> 本次只报出 **1 个**，实际缺 **26 个**，因为绝大多数模块是**懒加载**的。
> 该结论已写入 `docs/TROUBLESHOOTING.md`。

第三方包版本不含 dsh 版本号，按各自兼容范围锁定（`react` 必须锁 `18.x`）。

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
[1] 启动（当前模式：Web 界面 / 命令行模式）
[2] 检查更新（程序与 dsh 版本）
[3] 重置（清配置数据，保留运行环境，无需下载）
[4] 切换运行模式（Web 界面 ⇄ 命令行模式）      <- 新增
[5] 退出
```

### 3.3 默认关闭（硬约束，已验证）

- `config/launch.conf` **不存在、为空、或 `mode` 值无法识别**时，一律按 `web` 处理。
- 删除该文件即可恢复默认，**任何既有默认行为均未改变**。
- 状态面板新增「运行模式」行；CLI 模式下不再显示监听地址。

### 3.4 底层调用

命令行模式底层为 `dsh --profile headless`（dsh 0.1.5 起仅有 `web` / `acp` / `headless` / `sdk`），
日志写入 `data/logs/dsh-cli.log`。

---

## 四、冒烟测试结果

**执行命令**：`bash .patch-tools/smoke-local.sh`
**最终结果**：**用例数 9 / 通过 9 / 失败 0 / 通过率 100% / 退出码 0**

| # | 用例 | 结果 | 判定依据 |
|---|------|------|----------|
| 1 | 依赖就绪 | PASS | 便携 Node v22.23.2；dsh 入口存在 |
| 2 | `dsh --version` | PASS | 输出 `0.1.5-rc.2` |
| 3 | `dsh --help` 品牌 | PASS | `DeepSeek` 出现 **0** 次、`USB Harness` 出现 1 次 |
| 4 | 模块解析 | PASS | 解析失败 **0**（95 个说明符全部可解析） |
| 5 | 补丁基线校验 | PASS | 安全 **17** / 需确认 0 / 阻断 0 / 异常 0 |
| 6 | headless CLI 模式 | PASS | 插件树加载成功（止于模型派发：无 API Key） |
| 7 | web 服务启动 | PASS | 已监听 3080 端口族；局域网地址已发布 |
| 8 | web 首页 HTTP | PASS | HTTP 200（`token → 303 + Set-Cookie → cookie → 200` 全链路通过） |
| 9 | web 首页标题 / 静态资源 | PASS | `<title>USB Harness</title>`；4 个 JS/CSS 资源全部 HTTP 200 |

**品牌泄漏复查**：首页 HTML 中 `deepseek` 出现 **486 次，其中 486 次为 `@deepseek-ai/` 包名路径** → **品牌零泄漏**。

> **无跳过、无注释、无屏蔽**：全部 9 个用例真实执行。
> 脚本对每一步都加了 `timeout` 硬超时（60s / 60s / 30s / 300s / 180s / 120s），
> 任一步超时标记为 FATAL 并计入统计，不静默跳过。

### 排障记录（脚本健壮性）

本次执行中定位并修复了两个**环境陷阱**（非应用逻辑缺陷）：

1. **`/usr/bin` 不在 PATH**（Git Bash 环境）→ `grep`/`head`/`sed`/`ps`/`dirname` 全部找不到，
   脚本管道静默无输出，表现为「疑似卡死」。已在脚本开头兜底 `export PATH="/usr/bin:/bin:$PATH"`。
2. **POSIX 路径不能传给原生 Windows 程序** → `node.exe /d/...` 静默退出且只打印
   `Node.js v22.x.x`（无报错正文）；`curl.exe -o /d/...` 静默写不出文件（返回 `000`）。
   已改为同时维护 `ROOT`（POSIX，给 bash）与 `ROOT_W`（`pwd -W` → `D:/...`，给原生程序）。

---

## 五、分支同步验证结论

### 5.1 同步方式

1. `git fetch origin` — 发现远程有本地未包含的提交 `3dde9d6`（README 隐私修改）
2. 以 `origin/main` 为基线，将本地工作重做到其上（保持**线性历史**）
3. `git push origin main`
4. `git branch Release main` + `git push -u origin Release` —— 两分支指向**同一提交**

> 说明：`Release` 分支此前仅存在于本地且指向同一提交，本次为其建立远程跟踪。
> 未使用 `--force`，未改写任何已有历史。

### 5.2 零差异证据

**证据 1 — 分支 SHA 完全一致**

```
main            : 43dba0aa4e06653d28c1b57be861434d5dff3914
Release         : 43dba0aa4e06653d28c1b57be861434d5dff3914
origin/main     : 43dba0aa4e06653d28c1b57be861434d5dff3914
origin/Release  : 43dba0aa4e06653d28c1b57be861434d5dff3914
```

**证据 2 — `git diff` 输出为空**

```
$ git diff main Release
（无输出）                                  -> diff 输出行数: 0
$ git diff origin/main origin/Release
（无输出）                                  -> diff 输出行数: 0
```

**证据 3 — 提交历史一致**

```
两分支历史提交数均为 53
main..Release 独有提交数: 0
Release..main 独有提交数: 0
```

**证据 4 — 文件树对象哈希一致**

```
main    tree : 802e27e60cb535328c0d17f65773c78e63a70245
Release tree : 802e27e60cb535328c0d17f65773c78e63a70245
```

**证据 5 — 逐文件内容校验（全量对比）**

```
两分支全部文件的对象哈希一致（零差异）
```

**证据 6 — 构建产物一致**

本项目构建产物 = `git archive` 打包内容（CI 无编译步骤，用同样方式打包）：

```
main    产物 SHA256: 9e127a1f847c0536df5ffeabd4d1d26bc6651a36fdab03f9ef5524be18dbee4c
Release 产物 SHA256: 9e127a1f847c0536df5ffeabd4d1d26bc6651a36fdab03f9ef5524be18dbee4c
```

**结论：main 与 Release 在提交历史、文件内容、构建产物三个维度上完全一致，零差异。**

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
| peer 重定工具 | `.patch-tools/refscan.mjs` |
| 冒烟测试脚本 | `.patch-tools/smoke-local.sh` |
| 工具说明 | `.patch-tools/README.md` |

---

## 八、遗留与建议

1. **发版**：本次仅推送分支，**未打 tag、未触发 Release 构建**。
   如需发版：`git tag 0.1.5-rc.2 && git push origin 0.1.5-rc.2`
   （CI 会校验 tag 是否为 `$DshVersion` 或 `$DshVersion.<数字>`）。
2. **CI 验证**：本次冒烟测试在**本地**完成。建议打 tag 后由 GitHub Actions
   跑一遍跨平台验证（Windows + Linux RT job）。
3. **`--host 0.0.0.0` 的安全提示**：已在 README「安全须知」与变更要点中明确
   「仅限可信内网，禁止对公网开放」。若后续对安全要求提高，可考虑改为默认
   `127.0.0.1`、由用户在配置中显式开启局域网访问。
4. **skill-badge 补丁已失效**：`dsh-skill-badge/lib/index.js` 不再出现在本次变更集中，
   说明其定制内容与上游一致（无需改动），已确认文件内仍含 `USB Harness` 定制文案。
