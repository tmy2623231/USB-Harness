# 更新日志

本项目（USB Harness）自身的版本变更记录。
上游 `deepseek-harness (dsh)` 的逐条变更见
[docs/COMPATIBILITY.md](docs/COMPATIBILITY.md#5-版本变更追踪)。

格式参考 [Keep a Changelog](https://keepachangelog.com/zh-CN/)，
版本号遵循[语义化版本](https://semver.org/lang/zh-CN/)。

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
