## USB Harness v1.0.5 — 完整包（含运行时，下载即用）

> 修复：启动器状态 / 检查更新报「node 不是内部或外部命令」，以及旧系统 node 导致的 Web
> 「Failed to load plugins. Object.hasOwn is not a function」。

### 修复

- **根因**：dsh 的 `.bin` 垫片（`dsh.cmd`）靠 PATH 找 node，而启动器此前只有「启动 Web」
  这一步预置了便携 node 的 PATH——`Show-Status`、检查更新、升级脚本都没预置。
  - 干净机器（无系统 node）→ 状态页报 `node 不是内部或外部命令`；
  - 装着旧系统 node（<16.9）的机器 → dsh 跑到旧 node 上，Web 插件加载失败
    （`Object.hasOwn is not a function`）。
- **现在**：所有入口（launch.bat / launch.sh / 检查更新 / 升级）统一把便携 node 22.23.2
  提到 PATH 最前，dsh 永远跑在便携 node 上，与系统装没装 node 无关。
- **提醒**：请始终通过 launch.bat / launch.sh 启动；不要在命令行直接敲 `dsh` 命令
  （会命中系统 node）。

### 升级方式

1. 下载 `USB-Harness-with-runtime.zip`，解压即可用
2. 若要保留原有数据：把旧目录里的 `data/dsh/` 复制到新目录同名位置

> 完整变更见 [CHANGELOG.md](https://github.com/tmy2623231/USB-Harness/blob/main/CHANGELOG.md)。
