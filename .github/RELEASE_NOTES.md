## USB Harness v1.0.4 — 完整包（含运行时，下载即用）

> 新增启动器「检查更新 / 升级」功能；修复 Unix 全新安装必崩 bug。

### 新增：检查更新 / 升级

- 启动菜单新增 `[2] 检查更新`（直通 `launch.bat check-update` / `bash launch.sh check-update`），
  同时检测**本项目新版本**（GitHub Releases，主路径）与**上游 dsh 新版**（npm）。
- 项目有新版本 → 提示到 Releases 页下载完整包，**数据可沿用**；
  dsh 上游有新版 → 提示等待本项目适配版发布。
- 维护者升级：`launch.bat upgrade` 或 `scripts/upgrade-windows.ps1 -DshVersion <v>`，
  自动完成「备份 → 重装 → 自检 → 失败自动回滚」。

### 数据安全

- 升级只动 `.cache/` 运行环境，**`data/dsh/`（配置、密钥、会话）零改动**。
- 升级中断电/中断，下次启动自动裁决恢复。

### 修复

- `scripts/setup-unix.sh` Linux/macOS 全新安装必崩 bug（`NODE_TARBALL` 未赋值）。
- `upgrade-windows.ps1` 在 Windows PowerShell 5.1 下无法解析（缺 UTF-8 BOM + PS7 专属 `??` 运算符）。

### 升级方式

1. 下载 `USB-Harness-with-runtime.zip`，解压即可用
2. 若要保留原有数据：把旧目录里的 `data/dsh/` 复制到新目录同名位置

> 完整变更见 [CHANGELOG.md](https://github.com/tmy2623231/USB-Harness/blob/main/CHANGELOG.md)。
