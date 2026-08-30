# 发布同步规范：dsh 版本升级时 README 的更新流程

> 适用范围：**USB-Harness 跟进上游 `deepseek-ai/deepseek-harness`（dsh）新版本**时，
> 对 `README.md`（及关联文档）的同步更新。
>
> 目标：任何一次 dsh 版本升级，README 都能如实反映该版本的能力、用法与限制，
> 用户照着 README 操作不会踩到已失效的旧用法。

---

## 1. 变更信息来源（重要：dsh 没有 CHANGELOG）

上游仓库**无 `CHANGELOG.md`，也不发 GitHub Release**（走 npm 分发）。因此变更必须自行比对，
按可信度从高到低：

| 优先级 | 来源 | 获取方式 | 说明 |
|--------|------|----------|------|
| 1 | **tag 区间 compare** | `https://api.github.com/repos/deepseek-ai/deepseek-harness/compare/dsh-v<旧>...dsh-v<新>` | 返回 commits 列表 + 带 patch 的 files 列表，最完整 |
| 2 | **用户文档 diff** | compare 结果中筛 `docs/*.md`、`packages/*/README.md` 的 patch | 用户可见的行为/配置变化基本都在这里 |
| 3 | **npm 包元数据** | `https://registry.npmjs.org/@deepseek-ai/dsh/<版本>` | 看 `dependencies` / `engines` / `bin` 变化 |
| 4 | **包内容三方 diff** | `patch / 旧版 / 新版` 逐文件比对 | 判定 `brand-patch` 是否要重做（见第 6 节） |
| 5 | 上游 README / docs 正文 | 直接读 `main` 分支上的文件 | 辅助理解，不作为变更依据 |

**禁止**凭版本号字面推测变更内容；**禁止**把内部笔记（`.agents/notes/`）的增删当作用户可见变更。

### 确认"当前锁定版本"与"待升级版本"

```bash
# 本项目锁定的版本（两个脚本各一处）
grep -n "DshVersion\s*=" scripts/setup-windows.ps1
grep -n "DSH_VERSION" scripts/setup-unix.sh

# 上游可安装的最新版本（注意：Git tag 有 ≠ npm 有）
curl -sL "https://registry.npmjs.org/-/package/@deepseek-ai/dsh/dist-tags"
curl -sL "https://api.github.com/repos/deepseek-ai/deepseek-harness/tags?per_page=10"
```

判定规则：`dist-tags.latest` 指向的版本才是可安全升级的目标。
**Git tag 上存在但 npm 上没有的版本（如 alpha）不追**——需 clone 源码本地构建，且带破坏性变更。

---

## 2. 变更分类标准

从 compare 结果中提取变更，必须归入以下五类之一，无法归类的不放进 README：

| 类别 | 判定依据 | 典型 commit 前缀 / 信号 | README 中的表述 |
|------|----------|------------------------|-----------------|
| **新功能** | 新增能力、新增配置项、新增工具/命令 | `feat(...)`、配置目录出现新字段 | 说明"新增了什么、怎么用" |
| **行为变更** | 原有功能行为改变，但旧用法大多仍能跑 | `refactor(...)`、文档措辞变化、返回值结构调整 | 说明"变了什么、用户要做什么" |
| **破坏性变更** | 旧用法直接失效 | 配置项改名/删除、命名空间改名、工具移除、`BREAKING` | **必须**给旧用法标注 + 替代方案 |
| **问题修复** | 缺陷修复 | `fix(...)` | 简述修复了什么（用户可感知层面） |
| **废弃项** | 已标记废弃或已移除 | `remove`、`deprecated`、`retired` | 明确标注已废弃/已移除 + 替代路径 |

### 识别破坏性变更的三个硬信号

1. compare 的 `files` 中 `status` 为 `removed` 或 `renamed`（排除 `.agents/notes/` 内部笔记）
2. 文档 patch 中出现配置项/命名空间/事件名的新旧对（`-旧` `+新`）
3. commit 信息含 `remove` / `retired` / `rename` / `BREAKING`

---

## 3. README 必须同步的区块

按上游变更，逐项检查下表。无对应变更的区块保持原样，**不得删除仍然有效的内容**。

| 区块 | 同步内容 | 触发条件 |
|------|----------|----------|
| **功能特性** | 新增能力一句话 + 限制的收紧/放宽 | 有新功能，或某能力被移除 |
| **安装与升级指引** | 升级步骤、是否需要 `-Force` 重装、补丁是否需要重做 | 每次版本变更都要检查 |
| **支持的版本号与依赖要求** | 「版本锁定」表的 dsh 版本、Node 版本要求 | 每次版本变更（必改） |
| **命令 / 参数 / 配置项用法与示例** | 新增或改名的命令、参数、配置项，补全用法 + 完整示例 | 有新增/改名/移除的命令、参数、配置项 |
| **版本兼容性说明** | 本次变更要点表（新功能 / 行为变更 / 破坏性变更 / 问题修复 / 废弃项） | 每次版本变更（必改） |

### 新旧用法对照的写法

旧用法失效时，**必须**同时给出三者：旧写法 → 新写法 → 迁移动作。示例：

```markdown
| 旧用法 | 新用法 | 迁移动作 |
|--------|--------|----------|
| `maxRequestImageBytes: 20971520` | `maxRequestFilesBytes: 134217728` + `maxInlineRequestImageBytes: 20971520` | 在 `settings.yaml` 中按新名改写，旧名不再生效 |
```

---

## 4. 写作约束

1. **结构**：沿用现有章节顺序与标题层级（`##` 分节、`###` 子节），新增内容就近插入，不另起一套结构。
2. **语言风格**：简体中文；表格优先；陈述句；沿用现有 emoji 标题（🎯🚀💾✨ 等）；不新增装饰性符号。
3. **不删有效内容**：只有确认已被上游移除的能力才标注"已移除"并给替代方案，其余一律保留。
4. **用户视角**：只写本项目用户能用到的部分。上游某项能力若在本项目默认配置下不生效
   （例如官方 DeepSeek 适配器被 `brand-patch` 禁用），必须标注适用边界。
5. **详细技术细节下沉**：README 放结论与迁移动作，逐条完整清单放 `docs/COMPATIBILITY.md`，README 用链接指向。

---

## 5. 操作步骤

1. **定版本**：确认当前锁定版本与目标版本（npm `dist-tags.latest`）。
2. **取变更**：调用 compare API，拿到 commits 与 files（含 patch）。
3. **分类**：按第 2 节归入五类，逐条记录"变更点 → 用户影响 → 需要的动作"。
4. **判补丁**：按第 6 节校验 `brand-patch` 基线，决定沿用还是重做。
5. **改版本**：同步 `scripts/setup-windows.ps1`、`scripts/setup-unix.sh` 的版本变量（**补丁基线必须与版本号一致**）。
6. **改 README**：按第 3 节逐区块更新，遵守第 4 节约束。
7. **改关联文档**：`docs/COMPATIBILITY.md`（验证表 + 完整变更清单）、`docs/ARCHITECTURE.md`（若涉及架构决策）。
8. **自检**：`bash -n scripts/setup-unix.sh`；ps1 语法解析；全文搜旧版本号确认无残留引用。
9. **出清单**：按第 7 节输出改动清单。

---

## 6. brand-patch 基线校验（不可跳过）

`brand-patch` 内的文件是针对**具体 dsh 版本**改写的。版本号与补丁基线不一致会导致
「装 A 版、打 B 版补丁」——补丁引用了新版才有的导出，启动直接 `ERR_MODULE_NOT_FOUND`。

使用 `dsh_patch_compat_check.py` 做 `patch / 旧版 / 新版` 三方对比：

```bash
python dsh_patch_compat_check.py \
  --patch "<仓库>/brand-patch/@deepseek-ai" \
  --base 0.1.1-rc.1 --target 0.1.1-rc.2
```

判定：

| 结果 | 含义 | 动作 |
|------|------|------|
| 全部 OK | 补丁相对新旧两版均无变化，或补丁基线已等于目标版本 | 只改版本号，补丁不动 |
| 存在 CHK | 目标版改过该文件 | 逐个 diff，确认是否覆盖新修复 |
| 存在 BLOCK | 目标版已无此文件 | 必须基于新版重做补丁 |

**版本号与补丁基线必须同时修改**——这是本项目最容易踩的坑，已写入 `docs/COMPATIBILITY.md` 的已知坑位。

---

## 7. 改动清单输出要求

每次同步结束，输出一份清单，**逐条说明 README 的每处修改对应哪一项上游变更**，格式：

```markdown
| # | README 位置 | 修改内容 | 对应上游变更 | 变更类别 |
|---|-------------|----------|--------------|----------|
| 1 | ✨ 功能特性 · 第 N 条 | 新增「图片输入（多模态）」 | `feat(images): unify master and Files request pipeline` | 新功能 |
```

清单须覆盖：新增的内容、修改的内容、标注为失效的旧用法（含替代方案）、以及**明确未改动**的区块及原因。

---

## 8. 验收检查表

- [ ] 两处版本变量已改为目标版本，且与 `brand-patch` 基线一致
- [ ] 五类变更均已分类，无遗漏、无凭空推测
- [ ] 所有破坏性变更都给了旧用法标注 + 替代方案
- [ ] 功能特性、安装升级、版本与依赖、命令/参数示例、兼容性说明五个区块均已检查
- [ ] 现有结构与标题层级未被破坏，仍有效的内容未被删除
- [ ] 脚本语法自检通过，全文无旧版本号残留引用
- [ ] 改动清单已输出，逐条可追溯到上游变更
