## USB Harness 0.1.5-rc.2.1 — 完整包（含运行时，下载即用）

> 适配 dsh `0.1.5-rc.2`，版本号跟随适配的 dsh 版本；`.1` 为包装热修复号，**不涉及上游变更**。

### 本版修复：Windows 上 CLI 单次任务模式 100% 失败

若你在 `0.1.5-rc.2` 的 Windows 包里切到 CLI 模式并启动，会立即看到：

```
node.exe : error: --profile <name> is required
```

**原因**：该模式的启动逻辑调用的是裸 `dsh`，而 dsh 0.1.5 起取消了默认执行档位，
裸跑必然报错。**修复**：改为显式传 `--profile headless`。

同时明确该模式的定位——dsh 0.1.5 **不提供交互式 TUI**，可用档位只有
`web` / `headless` / `acp` / `sdk`，因此本模式重定位为「**CLI 单次任务**」：
输入一个任务，跑完一次会话后打印答案并退出。想要多轮对话请用 Web 界面。

> Web 界面用户不受本缺陷影响，无需为此升级；已在用 CLI 模式的请改用本版。

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
