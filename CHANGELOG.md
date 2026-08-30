# 更新日志

本项目（USB Harness）自身的版本变更记录。
上游 `deepseek-harness (dsh)` 的逐条变更见
[docs/COMPATIBILITY.md](docs/COMPATIBILITY.md#5-版本变更追踪)。

格式参考 [Keep a Changelog](https://keepachangelog.com/zh-CN/)，
版本号遵循[语义化版本](https://semver.org/lang/zh-CN/)。

---

## [1.0.3] — 2026-08-30

### 修复

- **react 版本漂移**：peer 补齐列表里用的是 `react@latest` / `react-dom@latest` /
  `@types/react@latest`，当前会拉到 **react 19.x**，而 `dsh-web-frontend` 依赖的是
  `react@^18.2.0`——跨大版本，前端渲染存在实际风险。现已锁定为 `^18.3.1` /
  `@types/react@^18.3.12`，与 dsh 期望一致。
  - 影响：v1.0.2 及更早包可能装入了 react 19。**建议所有用户更新到 v1.0.3。**

### 构建管线（不影响包内功能，但消除后续升级的隐患）

- **peer 列表单一数据源**：CI 里的 25 个 peer 包此前是硬编码的 `^0.1.1-rc.2`，与安装脚本的
  `$DshVersion` 脱钩——将来升级 dsh 若只改脚本，CI 会装出新主包 + 旧 peer，静默产出坏包。
  现改为**从 `scripts/setup-windows.ps1` 解析 `$PeerFix` 列表**，并校验其中 `dsh-*` 的版本
  必须与 `DSH_VERSION` 一致，不一致即构建失败。
- **补丁基线断言进 CI**：新增构建步骤，断言 `brand-patch` 的改写基线等于本次安装的 dsh 版本。
  以后「升了版本号却没同步补丁」会在**构建阶段**失败，而不是等用户下载后才发现启动崩溃。
- 新增 `scripts/dsh_patch_compat_check.py`：补丁兼容性校验工具（基线判定 + 变更判定 + 基线断言），
  本地与 CI 共用。

---

## [1.0.2] — 2026-08-30

### 修复

- **补丁基线错配（关键）**：`brand-patch` 内 17 个补丁文件此前已按 dsh `0.1.1-rc.2` 改写，
  但两处版本变量仍锁定 `0.1.1-rc.1`。这会导致安装 rc.1 运行时、却覆盖 rc.2 补丁——
  `dsh-llm-deepseek` 引用了 rc.2 才有的 `deadline` / `withFileLock` / `writeFileAtomic` /
  `resolveDshHome` 等导出，**启动必然报 `ERR_MODULE_NOT_FOUND`**。
  现已将 `scripts/setup-windows.ps1` 与 `scripts/setup-unix.sh` 的版本锁定同步为 `0.1.1-rc.2`。
  - 已逐个对 17 个补丁文件做 `patch / rc.1 / rc.2` 三方 diff 验证，
    基线全部为 rc.2（与 rc.2 的差异仅 4~27 行品牌与中文本地化改动），**无需重做任何补丁**。

### 新增

- `docs/RELEASE_README_SYNC.md`：dsh 版本升级时 README 的同步规范。
  明确变更信息来源（上游无 CHANGELOG、不发 GitHub Release，只能取 tag 区间 compare、
  用户文档 diff、npm 元数据）、五类变更判定标准、README 必同步的 5 个区块、
  新旧用法对照写法与验收检查表。
- README：新增「dsh 0.1.1-rc.2 变更要点」（含失效配置项对照与适用边界）、
  「如何升级 dsh 版本（维护者）」；功能特性补充「图片输入（多模态）」。
- `docs/COMPATIBILITY.md`：新增「版本变更追踪」章节，逐条列出 rc.1→rc.2 变更并附 commit 证据。
- 本文件（`CHANGELOG.md`）。

### 变更

- 上游 dsh：`0.1.1-rc.1` → `0.1.1-rc.2`。
  破坏性变更包括 `maxRequestImageBytes` 拆分为 `maxRequestFilesBytes` + `maxInlineRequestImageBytes`、
  权限预设 Settings 命名空间 `permission` → `permissionPresets`、
  图片区域读取（image-region）移除。详见 README 与 COMPATIBILITY。

---

## [1.0.1] — 2026-08-24

### 新增

- **符号链接复制回退补丁**：dsh 在 `data/dsh/profiles/node_modules/` 下创建符号链接失败时，
  自动改为复制真实包目录，使 exFAT / FAT32 也能正常运行核心功能。
- 启动时提示「正在启动服务，浏览器将在就绪后自动打开」。
- 文档与视觉：README Banner（SVG）、GitHub 社交预览图（1280x640）、SEO 徽章与关键词。

### 修复

- 浏览器自动打开探测逻辑改为**连接探测**——原先的 `TcpListener` 绑定探测
  在 Windows 上会把被占用的端口误判为空闲。

### 变更

- **U 盘格式要求放宽**：由「必须 NTFS」改为「推荐 NTFS，exFAT / FAT32 亦可运行」
  （代价是 `profiles` 目录多占约几百 MB 空间）。

---

## [1.0.0] — 2026-08-22

首个公开版本。

- 便携外壳：便携 Node.js + 预置 dsh 依赖，U 盘即插即用，零宿主机污染。
- `DSH_HOME` 重定向到 `data/dsh/`，密钥 / 配置 / 会话随盘。
- 交互式启动器（中文菜单：启动 / 重置 / 退出），首启自动安装。
- 品牌改造（`brand-patch`）：去 DeepSeek 化 + 界面中文本地化。
- 中国网络适配：Node 走 npmmirror、npm 用 `registry.npmmirror.com`，失败自动回退官方源。
- U 盘预置离线安装包，重装不依赖网络。
