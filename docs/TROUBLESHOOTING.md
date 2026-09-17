# USB Harness — 故障排查

## 症状 → 原因 → 处理

| 症状 | 可能原因 | 处理 |
|------|----------|------|
| 双击 launch.bat 闪退/无窗口 | 执行策略限制、PowerShell 未配置 | 右键「用 PowerShell 运行」；或运行 `powershell -ExecutionPolicy Bypass -File .\scripts\launch-windows.ps1` |
| `node: not found` / 找不到 node | 便携 Node 未就绪 | 运行 `.\scripts\setup-windows.ps1` |
| `node 不是内部或外部命令`（启动器状态/检查更新时） | 系统 PATH 无 node，而 dsh.cmd 垫片靠 PATH 找 node | **`0.1.1-rc.2.1` 起已根治**：启动器用便携 node 绝对路径直调 dsh CLI 入口（`lib/bin.js`），不再经过垫片。若仍出现，确认 `.cache\app\node_modules\@deepseek-ai\dsh\lib\bin.js` 与 `.cache\runtimes\windows-x64\node\node.exe` 存在，必要时重跑 setup |
| 打开 Web 报「Failed to load plugins. Object.hasOwn is not a function」 | 旧版本号（≤0.1.1-rc.2）下 dsh 被垫片带到**旧系统 node**（<16.9，无 `Object.hasOwn`）上 | **`0.1.1-rc.2.1` 起已根治**（同上，直调便携 node）。若在用旧包，请下载新版；临时可用：通过 launch.bat / launch.sh 启动（会把便携 node 提到 PATH 最前），不要在命令行直接敲 `dsh` 命令 |
| 启动报 `ERR_MODULE_NOT_FOUND: Cannot find package '@deepseek-ai/dsh-xxx'` | **dsh 的 peer 依赖缺陷**：子包把彼此声明为 `peerDependencies`，主包 bundle 未包含，`--legacy-peer-deps` 会跳过它们 | 补齐清单是**逐版本实测**的，不是固定值（0.1.1-rc.2 为 25 个，0.1.5-rc.2 为 26 个）。不要手工拼清单——按下方「peer 依赖补齐清单的重定方法」重定后写回 `scripts/setup-windows.ps1` 的 `$PeerFix` 与 `scripts/setup-unix.sh` 的 `PEERS`，再重跑 setup |
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
> 的 `PEERS` 需要重定。**该清单必须逐版本实测，不能照抄上一版**。

### 为什么不能靠「跑一次看缺哪个」

绝大多数 `@deepseek-ai/*` 子模块是**懒加载**的——只有走到对应功能才会 `import`。
单次 `dsh --version` 或启动一次 Web，只能触达极小一部分。

> 实测对比：本次升级中，「跑一次看报错」的方法**只报出 1 个**缺失包，
> 而静态说明符扫描报出 **26 个**。漏报的 25 个会在用户用到对应功能时才炸。

### 正确做法：静态说明符扫描

对安装树里**全部** `.js` / `.mjs` / `.cjs` 文件，提取所有 `@deepseek-ai/*` 的 import 说明符，
逐个尝试解析；**凡解析不到的，即为必须补齐的缺失项**。

```js
// refscan.mjs —— 与 node_modules 同级的任意位置执行
import { createRequire } from 'node:module'
import { readdirSync, readFileSync, statSync } from 'node:fs'
import { join } from 'node:path'

const MODS = process.argv[2]                    // .../.cache/app/node_modules
const SPEC = /(?:from\s*|import\s*\(\s*|require\s*\(\s*)["'](@deepseek-ai\/[^"'\/]+)(?:\/[^"']*)?["']/g

function walk(dir, out = []) {
  for (const e of readdirSync(dir, { withFileTypes: true })) {
    const p = join(dir, e.name)
    if (e.isDirectory()) walk(p, out)
    else if (/\.(js|mjs|cjs)$/.test(e.name)) out.push(p)
  }
  return out
}

const files = walk(join(MODS, '@deepseek-ai'))
const seen = new Map()                          // spec -> 首次出现它的文件

for (const f of files) {
  const text = readFileSync(f, 'utf8')
  for (const m of text.matchAll(SPEC)) if (!seen.has(m[1])) seen.set(m[1], f)
}

const missing = []
for (const [spec, from] of seen) {
  const req = createRequire(from)
  try { req.resolve(spec + '/package.json') } catch { missing.push(spec) }
}

console.log(`说明符 ${seen.size} 个；缺失 ${missing.length} 个`)
for (const s of missing.sort()) console.log('  ' + s)
```

执行：

```bash
node refscan.mjs "<包根>/.cache/app/node_modules"
```

- 输出「缺失 0 个」→ 清单已完整。
- 输出若干缺失包 → 逐个补进 `$PeerFix` / `PEERS`（用 `$DshVersion` / `$DSH_VERSION` 拼版本串），
  重装后再跑一次，直到缺失为 0。

### 版本号与硬校验

- `dsh-*` 子包一律用锁定的 dsh 版本（`@deepseek-ai/dsh-xxx@$DshVersion`）。
- **第三方包**（`react`、`bufferutil` 等）版本独立于 dsh，不要跟着 dsh 版本改。
  注意 `react` 必须锁 `18.x`：`dsh-web-frontend` 依赖 `react@^18.2.0`，写 `latest` 会拉到 19.x（跨大版本不兼容）。
- CI（`.github/workflows/smoke-test.yml` / `release.yml`）会从 setup 脚本里**正则解析** peer 数量
  做下限校验，保证「单一数据源」。修改清单后该数量会同步变化，阈值已放宽到 ≥6，正常增删不会误报。

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
