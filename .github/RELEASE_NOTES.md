## USB Harness v1.0.2 — 完整包（含运行时，下载即用）

> **使用 v1.0.1 及更早版本的用户请务必更新**：旧包存在一处会导致**启动必然失败**的问题。

### 修复

**补丁基线错配（关键）**

`brand-patch` 里的 17 个补丁文件此前已按 dsh `0.1.1-rc.2` 重写，但安装脚本的版本变量仍锁在
`0.1.1-rc.1`。结果是：装上 rc.1 的运行时，却被 rc.2 的补丁覆盖——`dsh-llm-deepseek` 引用了
rc.2 才有的 `deadline` / `withFileLock` / `writeFileAtomic` / `resolveDshHome` 等导出，
**启动时必然报 `ERR_MODULE_NOT_FOUND`**。

现已把 `scripts/setup-windows.ps1` 与 `scripts/setup-unix.sh` 的版本锁定同步为 `0.1.1-rc.2`。

- 已对 17 个补丁文件逐个做 `patch / rc.1 / rc.2` 三方 diff 验证：基线全部为 rc.2，
  与 rc.2 的差异仅 4~27 行品牌与中文本地化改动，**无需重做任何补丁**。

### 上游升级

dsh `0.1.1-rc.1` → `0.1.1-rc.2`，主要变化：

| 类别 | 内容 |
|------|------|
| 新功能 | 统一图片请求管线，`read_image` 走规范化存储 + Files 回退；新增 `maxRequestFilesBytes`（128 MiB）、`maxImagesPerRequest`（600）、`maxInlineRequestImageBytes`（20 MiB）等配额项 |
| 行为变更 | `read_image` 执行时校验当前路由模型；返回值新增缩放后尺寸与坐标比例 |
| **破坏性** | `maxRequestImageBytes` 拆分为 `maxRequestFilesBytes` + `maxInlineRequestImageBytes`；权限预设命名空间 `permission` → `permissionPresets`、事件名 `permission/preset` → `permissionPresets/preset` |
| 废弃 | 图片区域读取（image-region / region reads）已移除 |
| 修复 | Files 解析失败自动回退内联、Files 与流超时解耦、WebP 透明通道兼容等 |

### 新增

- `docs/RELEASE_README_SYNC.md`：dsh 升级时 README 的同步规范
- `CHANGELOG.md`：本项目版本更新日志
- README：rc.2 变更要点、失效配置项对照、维护者升级指引、图片输入（多模态）能力说明
- `docs/COMPATIBILITY.md`：新增「版本变更追踪」章节，逐条变更附 commit 证据

### 升级方式

1. 下载 `USB-Harness-with-runtime.zip`，解压即可用（无需重新配置）
2. 若要保留原有数据：把旧目录里的 `data/dsh/` 复制到新目录同名位置

> 完整变更见 [CHANGELOG.md](https://github.com/tmy2623231/USB-Harness/blob/main/CHANGELOG.md)。
