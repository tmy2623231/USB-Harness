# USB Harness — 故障排查

## 症状 → 原因 → 处理

| 症状 | 可能原因 | 处理 |
|------|----------|------|
| 双击 launch.bat 闪退/无窗口 | 执行策略限制、PowerShell 未配置 | 右键「用 PowerShell 运行」；或运行 `powershell -ExecutionPolicy Bypass -File .\scripts\launch-windows.ps1` |
| `node: not found` / 找不到 node | 便携 Node 未就绪 | 运行 `.\scripts\setup-windows.ps1` |
| `node 不是内部或外部命令`（启动器状态/检查更新时） | 系统 PATH 无 node，而 dsh.cmd 垫片靠 PATH 找 node | **`0.1.1-rc.2.1` 起已根治**：启动器用便携 node 绝对路径直调 dsh CLI 入口（`lib/bin.js`），不再经过垫片。若仍出现，确认 `.cache\app\node_modules\@deepseek-ai\dsh\lib\bin.js` 与 `.cache\runtimes\windows-x64\node\node.exe` 存在，必要时重跑 setup |
| 打开 Web 报「Failed to load plugins. Object.hasOwn is not a function」 | 旧版本号（≤0.1.1-rc.2）下 dsh 被垫片带到**旧系统 node**（<16.9，无 `Object.hasOwn`）上 | **`0.1.1-rc.2.1` 起已根治**（同上，直调便携 node）。若在用旧包，请下载新版；临时可用：通过 launch.bat / launch.sh 启动（会把便携 node 提到 PATH 最前），不要在命令行直接敲 `dsh` 命令 |
| 启动报 `ERR_MODULE_NOT_FOUND: Cannot find package '@deepseek-ai/dsh-xxx'` | **dsh 的 peer 依赖缺陷**：子包把彼此声明为 `peerDependencies`，主包 bundle 未包含，`--legacy-peer-deps` 会跳过它们 | 补齐清单是**逐版本重算**的，不是固定值（0.1.1-rc.2 为 25 个，0.1.5-rc.2 为 71 个）。不要手工拼清单——用 `python .patch-tools/refscan-registry.py --dsh-version <ver> --emit-ps1` 重算后写回 `scripts/setup-windows.ps1` 的 `$PeerFix` 与 `scripts/setup-unix.sh` 的 `PEERS`，再重跑 setup。**切勿用「扫安装树看缺哪个」的办法**，那是循环论证、会报「缺失 0 个」的假阳性（详见下节） |
| 裸跑 `dsh` 报 `error: --profile <name> is required` | 0.1.5 起 dsh 精简了执行档位，**没有**默认档 | 显式指定 profile（`web` / `acp` / `headless` / `sdk`）。本项目的「命令行模式」即 `dsh --profile headless`，用启动器菜单 `[4]` 切换即可，无需手敲 |
| 打开 Web 只显示 `401` | dsh 的 browser-trust fence：裸 URL 不携带 token | 正常行为。带服务端启动时打印的 `?token=xxx` 访问，会 `303` 重定向并种下会话 cookie，之后即为 `200`。用 `launch.bat` / `launch.sh` 启动会自动带上完整带 token 的地址 |
| 启动报 `--host 0.0.0.0 is intentionally not supported` | `brand-patch` 对 `dsh-web-app/lib/startup.js` 的定制未生效（补丁基线错配） | 说明补丁没打到新版本上。按 [RELEASE_README_SYNC.md](./RELEASE_README_SYNC.md#6-brand-patch-基线校验不可跳过) 重做补丁；本项目**有意**放行 `0.0.0.0`（U 盘 / 局域网共享场景），该报错在本项目中不应出现 |
| `dsh: not found` / `.bin\dsh` 缺失 | dsh 未安装 | 运行 `.\scripts\setup-windows.ps1` |
| 报「requires Node ^22.19.0 || >=24」 | Node 版本不符（如 23） | 确认用 `.cache/runtimes/.../node.exe`（22.23.2），勿用系统 Node 23 |
| 端口 3080 被占用，启动失败 | 其他程序占用 | `launch-windows.ps1 web` 会自动换端口；或设置环境变量后重启 |
| 插件列表大量显示「未启动/禁用」 | **dsh 架构设计，非故障** | agent 工具（tool-fs/tool-web/tool-todo 等）已从 host 平面移到 preset 层，会话启动时由默认 `standard` preset 挂载提供，功能正常；强行在 host 平面启用会重复注册冲突，勿动 |
| 配置的模型 401 / unknown model | API Key 错误 / 网关未暴露模型索引 | 核对 `baseURL` 与 key；网关无 `/models` 索引时手动填写模型 id |
| 浏览器打开空白/连不上 | 服务未起、只监听 loopback | 确认访问 `http://127.0.0.1:<port>`（不是局域网 IP）；看 `data/logs/` |
| `dsh plugin` 装插件报符号链接错误 | exFAT/FAT32 不支持符号链接（仅影响插件安装；核心运行已通过复制回退解决） | 改用 NTFS 或本地磁盘；见 DEPLOYMENT.md |
| 启动极慢 | USB 2.0 / 杀软实时扫描 | 换 USB 3.0/SSD；目录加入杀软排除 |
| 从 U 盘被拒绝执行 | 组策略禁止可移动介质运行 | 复制到本地磁盘运行；或 IT 放行 |
| 报路径过长（260 字符） | U 盘挂在深路径 | 放到盘符根目录；开启长路径支持 |

## peer 依赖补齐清单的重定方法

> 触发场景：升级 dsh 版本后，`scripts/setup-windows.ps1` 的 `$PeerFix` / `scripts/setup-unix.sh`
> 的 `PEERS` 需要重定。**该清单必须逐版本重算，不能照抄上一版**。
>
> 权威工具：`.patch-tools/refscan-registry.py`

### 先说什么方法**不管用**（两代错误方法）

**第一代：跑一次看报错。** 绝大多数 `@deepseek-ai/*` 子模块是**懒加载**的——只有走到对应
功能才会 `import`。单次 `dsh --version` 或启动一次 Web 只能触达极小一部分，漏报的包会在
用户用到对应功能时才炸。实测只报出 1 个，而实际需要 71 个。

**第二代：扫描已安装树找解析不到的 import**（旧 `refscan.mjs` 的做法，该文件已删除）。
这个方法**是循环论证，本质上不可能报全**：

```
没被装上的包  →  不会出现在安装树里  →  扫不到  →  报告「缺失 0 个」  →  但它是真缺
```

> 实测事故：该法报告「缺失 0 个」，CI 却在 `dsh-timeout` / `dsh-atomic-write` /
> `dsh-web-frontend` 上判定缺包失败——这三个包确实需要，只是从未被装上，
> 因此从未出现在被扫描的树里。**用安装结果去验证安装完整性，是自证。**

### 正确做法：遍历 npm 注册表依赖闭包

dsh 的打包缺陷本质是：**子包把彼此声明为 `peerDependencies`，但主包的 `dependencies`
未包含它们**。而 `--legacy-peer-deps` 会跳过全部 peer 解析。于是这些 peer 既不在主包
依赖树里，也不会被 npm 自动装上 → 运行期 `ERR_MODULE_NOT_FOUND`。

所以要补的集合 = **整个依赖闭包中所有 `peerDependencies` 的并集**
减去「已在主包 `dependencies` 里、会被 npm 自动装上的」。

> 注意：这个集合**与安装树无关**，只由注册表元数据决定。所以它不受
> 「装没装上」的干扰，是真正的前置推导。

```bash
# 查看完整推导结果（含每个 peer 的引用方）
python .patch-tools/refscan-registry.py --dsh-version 0.1.5-rc.2

# 直接生成可替换进 setup 脚本的片段
python .patch-tools/refscan-registry.py --dsh-version 0.1.5-rc.2 --emit-ps1   # → $PeerFix
python .patch-tools/refscan-registry.py --dsh-version 0.1.5-rc.2 --emit-sh    # → PEERS
```

脚本执行流程：

1. 从 `@deepseek-ai/dsh@<ver>` 出发，读其 `dependencies`（该集合算「已自动覆盖」）；
2. 沿 `dependencies` 递归展开闭包（深度上限 4 防爆炸），对途经的每个
   `@deepseek-ai/*` 子包读取其 `peerDependencies`，并入候选集；
3. `need = 候选集 − 已自动覆盖`，即为必须显式补齐的清单。

> 实测数据（0.1.5-rc.2）：扫描 215 个子包，发现 89 个 peer 依赖，
> 其中 18 个已被主包 `dependencies` 覆盖，**71 个必须显式补齐**。

### 版本号分组：按「版本范围」判，不是按包名前缀

推导出的清单要分成两组写进脚本：

| 组 | 判据 | 写法 |
|----|------|------|
| 跟随 dsh 版本 | peer 声明里的版本范围落在本次 dsh 版本族（`0.1.5-*`） | `"@deepseek-ai/dsh-xxx@$DshVersion"` |
| 独立版本 | 版本范围不在 dsh 版本族 | `'xxx@^1.0.2'`（保留其自身范围） |

> **坑位：不能只看 `@deepseek-ai/` 前缀。**
> 反例——`@deepseek-ai/cordis-plugin-group` 的版本号是 `1.0.1` / `1.0.2`，
> 与 dsh 的 `0.1.5-rc.2` 毫无关系。若按前缀当成 dsh 家族去装
> `@deepseek-ai/cordis-plugin-group@0.1.5-rc.2`，npm 直接报
> `ETARGET: No matching version found`，**整个 peer 补齐步骤失败**。
> 脚本的 `is_dsh_family()` 用版本范围判据做这个分类，`--emit-*` 会自动分好组。

- **第三方包**（`react`、`bufferutil` 等）版本独立于 dsh，不要跟着 dsh 版本改。
  注意 `react` 必须锁 `18.x`：`dsh-web-frontend` 依赖 `react@^18.2.0`，写 `latest` 会拉到 19.x（跨大版本不兼容）。
- **单一数据源**：CI（`.github/workflows/smoke-test.yml` / `release.yml`）直接从 setup 脚本
  正则解析 `$PeerFix`，用于两处——① 生成实际安装的包列表，② 生成完整性断言的对象。
  **CI 里不存在第二份硬编码包名清单。**
  > 历史事故：断言曾硬编码 5 个包名（`dsh-timeout` / `dsh-atomic-write` / `dsh-shell` /
  > `dsh-spill` / `dsh-web-frontend`），清单重定后其中 3 个已不在 `$PeerFix` 里，
  > 于是断言与安装行为脱节、把一次**正确**的安装判成了失败。
  > 改为派生后，这类「清单改了但断言没改」的失效模式在结构上不可能再出现。
- `$PeerFix` 内 dsh 子包用**双引号**（需插值 `$peerVer`）、第三方包用**单引号**。
  CI 的解析正则同时匹配两种，只匹配单引号会漏掉全部子包——这也是上述事故的成因之一。

---

## 快速定位

```powershell
# 1) 确认便携 Node 与 dsh 就绪
& .\.cache\runtimes\windows-x64\node\node.exe -v
& .\.cache\app\node_modules\.bin\dsh.cmd --version

# 2) 查看 web 子命令可用参数
$env:DSH_HOME = "$PWD\data\dsh"
& .\.cache\app\node_modules\.bin\dsh.cmd web --help

# 3) 打印合并后的配置（排查配置问题）
& .\.cache\app\node_modules\.bin\dsh.cmd web --dump-config
```

## 日志位置

- 启动日志：`data/logs/dsh-web.log`
- dsh 会话/事件流：`data/dsh/sessions/`、`data/dsh/storages/`

## 仍无法解决

- dsh 官方反馈：GitHub Discussions（`deepseek-ai/deepseek-harness/discussions`）
- 请同时提供：`node -v`、`dsh --version`、`dsh web --dump-config`（已脱敏）、
  `data/logs/dsh-web.log` 末尾片段。
