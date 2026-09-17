## USB Harness 0.1.5-rc.2.2 — 完整包（含运行时，下载即用）

> 适配 dsh `0.1.5-rc.2`，版本号跟随适配的 dsh 版本；`.2` 为包装热修复号，**不涉及上游变更**。
>
> **如果你已下载 `0.1.5-rc.2.1`，请务必换成本版**——`.1` 的 Web 界面打不开。

### 本版修复：Web 页面 "Failed to load plugins"（严重）

打开 Web 页面时显示：

```
Failed to load plugins
@deepseek-ai/dsh-client-ui-permission-presets
failed to apply loader entry 204619: (…): t is not defined
```

**原因**：一个品牌定制文件（权限预设的浏览器端模块）在改造时漏声明了一个
函数形参，导致浏览器加载插件时抛 `ReferenceError`。**修复**：补上该形参。

> 该缺陷**只影响 Web 界面**；CLI / 单次任务路径不加载这个模块，所以看起来是好的。
> 换成本版后 Web 界面即可正常打开。

### 上一版（`.1`）修复了什么：Windows 上 CLI 单次任务 100% 失败

若你在更早的包里切到 CLI 模式并启动，会立即看到：

```
node.exe : error: --profile <name> is required
```

**原因**：该模式的启动逻辑调用的是裸 `dsh`，而 dsh 0.1.5 起取消了默认执行档位，
裸跑必然报错。**修复**：改为显式传 `--profile headless`。

同时明确该模式的定位——dsh 0.1.5 **不提供交互式 TUI**，可用档位只有
`web` / `headless` / `acp` / `sdk`，因此本模式重定位为「**CLI 单次任务**」：
输入一个任务，跑完一次会话后打印答案并退出。想要多轮对话请用 Web 界面。

### ⚠️ 首次使用必须自己配一次模型

**本包不内置任何模型凭据**（有意为之），所以第一次打开必须：

> **设置 → 模型 → 添加自定义提供方** → 填 API 地址 / 密钥 → 获取可用模型 → 保存

在此之前，你会看到下面这些**正常**提示，不要误判成崩溃：

| 提示 | 含义 |
|------|------|
| `dsh: NO_ADAPTER: no adapter registered for provider "pi-ai"` | 插件树已加载成功，只是没配模型 |
| Web 对话报模型不可用 | 同上，去设置里配好即可 |
| 控制台红字 `error:`（PowerShell 渲染 stderr） | 多数是警告被渲染成红字，非故障 |

**判断口径**：Web 首页能打开、插件能加载 = 程序没问题，只差模型配置。
**真正要警惕的是浏览器出现 `Failed to load plugins`**——那才是程序缺陷。

### 上游对齐：dsh 0.1.1-rc.2 → 0.1.5-rc.2

- **全部 17 个品牌补丁已按新版本重建**（不是整文件沿用旧补丁），
  定制点（去品牌化、中文字案、`0.0.0.0` 放行、FAT32/exFAT 复制回退）全部保留，
  同时不会回滚上游在本区间的修复。
- **补齐清单重定为 26 个 peer 包**（0.1.1-rc.2 下为 25 个）：
  dsh 的子包把彼此声明为 `peerDependencies`，主包 bundle 未包含，
  而 `--legacy-peer-deps` 会跳过它们，导致启动报 `ERR_MODULE_NOT_FOUND`。
  本次用「扫描安装树全部 import 说明符逐个解析」的方式重定，实测 95 个说明符全部可解析。
- **执行档位适配**：dsh 0.1.5 起只有 `web` / `acp` / `headless` / `sdk` 四种 profile，
  裸跑 `dsh` 会直接报错要求显式指定——启动器已封装，无需手敲。

### 运行模式切换（默认仍为 Web 界面）

- 启动器菜单新增 **[4] 切换运行模式**，可在 **Web 界面** 与 **CLI 单次任务** 间切换。
- 模式持久化在 `config/launch.conf` 的 `mode` 字段，Windows 与 Linux/macOS 共用。
  **该文件不存在、为空或值无法识别时一律按 Web 界面处理**，删除即可恢复默认，
  不影响任何既有行为。
- CLI 单次任务模式底层为 `dsh --profile headless`，日志写入 `data/logs/dsh-cli.log`。

### 升级方式

1. 下载 `USB-Harness-with-runtime.zip`，解压即可用
2. 若要保留原有数据：把旧目录里的 `data/dsh/` 复制到新目录同名位置
   （`config/launch.conf` 若已配置过运行模式，也一并复制）

### 安全提示

本项目为 U 盘 / 局域网共享场景**有意放行** `--host 0.0.0.0`（上游默认拒绝）。
请务必只在可信内网使用，**不要对公网开放**。

> 打开 Web 页面若提示 `authentication required`，说明地址里少了 `?token=` 参数——
> 请完整复制启动器打印的那条带 token 的地址。
>
> 完整变更见 [CHANGELOG.md](https://github.com/tmy2623231/USB-Harness/blob/main/CHANGELOG.md)。
