## USB Harness v1.0.3 — 完整包（含运行时，下载即用）

> **建议所有用户更新**：修复了前端依赖版本漂移，并补齐了构建期的防错校验。

### 修复

**react 版本漂移**

peer 依赖补齐列表原先使用 `react@latest` / `react-dom@latest` / `@types/react@latest`。
随着 react 19 发布，这会把 **react 19.x** 装进来，而 dsh 的 `dsh-web-frontend` 依赖的是
`react@^18.2.0`——跨大版本，前端渲染存在实际风险。

现已锁定为 `react@^18.3.1` / `react-dom@^18.3.1` / `@types/react@^18.3.12`，与 dsh 期望一致。

- 影响范围：v1.0.2 及更早版本的包可能装入了 react 19。

### 构建管线加固（不改动包内功能）

这几项是给**后续升级**准备的防错机制，避免重蹈本次「补丁基线错配」的覆辙：

| 改动 | 解决的问题 |
|------|-----------|
| peer 列表从 `scripts/setup-windows.ps1` 解析 | 消除 CI 与安装脚本两处维护；升级 dsh 时不会再出现「新主包 + 旧 peer」的混合版本 |
| peer 版本与 `DSH_VERSION` 一致性校验 | 版本不一致直接构建失败，不静默产出坏包 |
| 补丁基线断言进 CI | 「升了版本号却没同步 `brand-patch`」会在**构建阶段**失败，而不是等用户下载后才发现启动崩溃 |
| 新增 `scripts/dsh_patch_compat_check.py` | 补丁兼容性校验工具，本地与 CI 共用，支持 `--expect-base` 断言 |

### 升级方式

1. 下载 `USB-Harness-with-runtime.zip`，解压即可用
2. 若要保留原有数据：把旧目录里的 `data/dsh/` 复制到新目录同名位置

> 完整变更见 [CHANGELOG.md](https://github.com/tmy2623231/USB-Harness/blob/main/CHANGELOG.md)。
