## USB Harness 0.1.1-rc.2 — 完整包（含运行时，下载即用）

> **版本体系切换**：本项目版本号改为跟随适配的 dsh 版本。本包适配 dsh `0.1.1-rc.2`，
> 故版本号即 `0.1.1-rc.2`（v1.0.x 旧编号已弃用）。

### 变更

- 版本号 = 适配的 dsh 版本；Release tag / 包内 `HARNESS_VERSION` 统一为 dsh 版本号。
- 内容与 v1.0.5 相同（含 dsh 垫片 node 解析修复），仅版本标记改为新体系。
- 构建管线新增硬校验：tag 必须等于 setup 锁定的 dsh 版本，打错 tag 直接构建失败。

### 修复（继承自 v1.0.5）

- dsh 的 `.bin` 垫片靠 PATH 找 node：启动器所有入口统一把便携 node 22.23.2 提到 PATH 最前，
  不再受系统 node 影响（`node 不是内部或外部命令` / `Object.hasOwn is not a function` 均修复）。
- 请始终通过 launch.bat / launch.sh 启动；不要在命令行直接敲 `dsh`。

### 升级方式

1. 下载 `USB-Harness-with-runtime.zip`，解压即可用
2. 若要保留原有数据：把旧目录里的 `data/dsh/` 复制到新目录同名位置

> 完整变更见 [CHANGELOG.md](https://github.com/tmy2623231/USB-Harness/blob/main/CHANGELOG.md)。
