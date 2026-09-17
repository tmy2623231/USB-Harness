# .patch-tools — 上游版本升级工具

跟进上游 `deepseek-ai/deepseek-harness`（dsh）新版本时使用的工具。
**不是运行时组件**，不参与安装、打包与 CI 构建。

完整升级流程见 [docs/RELEASE_README_SYNC.md](../docs/RELEASE_README_SYNC.md)。

---

## rebuild-patch.py — 品牌补丁重建

把 `brand-patch/` 的每个文件从「旧版上游文件的整文件快照」重建为
「**新版上游基线 + 重新施加定制意图**」。

### 为什么必须重建，不能整文件沿用

`brand-patch/` 里的文件本质是「某版本上游文件的整文件副本 + 定制改动」。
升级时若直接沿用上一版的补丁产物，等于把该文件在**新版本里的全部上游修复一起回滚**。

> 实测：本仓库 17 个补丁文件里，曾有 **9 个**属于这种整文件快照。
> 沿用它们会静默回滚上游修复，且**不会被三方差异校验发现**。

### 用法

```bash
python .patch-tools/rebuild-patch.py \
  --base   0.1.1-rc.2 \
  --target 0.1.5-rc.2 \
  --diff                # 只看 diff，不落盘
```

```bash
python .patch-tools/rebuild-patch.py \
  --base   0.1.1-rc.2 \
  --target 0.1.5-rc.2 \
  --write               # 写回 brand-patch/
```

### 定制意图类型

定制不是靠「逐行 diff 猜测」，而是显式声明为**意图**，逐个在新基线上施加。
**任何意图找不到锚点都会报错退出**，绝不静默跳过——静默跳过正是定制丢失的根源。

| 意图 | 语义 | 失败行为 |
|------|------|----------|
| `sub` | 字面量替换（品牌改名、文案改写等） | 目标串不存在 → 报错 |
| `anchor` | 在指定锚点插入代码块 | 锚点找不到 → 报错 |
| `block_or_fail` | 整块替换（导入语句等结构性改动） | 结构不匹配 → 报错 |
| `yaml_usb_base` | `cordis.patch.yml` 的配置改动 | 键位不匹配 → 报错 |
| `allow_all_interfaces` | 移除上游对 `--host 0.0.0.0` 的拦截 | 未逐字命中且文件里仍有 `0.0.0.0` → **报错**（上游改了写法，需人工核对） |
| `usb_brand_icon` | 自绘 USB SVG 标识替换官方 logo | — |
| `permission_preset_i18n` | 权限模式文案中文化 | — |
| `onboarding_custom_provider` | 引导页改写为添加自定义提供方 | — |
| `web_index_html` / `web_manifest` / `web_favicon` | Web 首页 / manifest / 图标 | — |

### 校验不通过怎么办

| 报错 | 含义 | 动作 |
|------|------|------|
| `anchor not found` / 目标串不存在 | 上游改了这段代码的写法 | 打开新旧两版上游文件比对，更新意图里的字面量锚点 |
| `allow_all_interfaces: ... 的 0.0.0.0 拦截未能移除` | 上游重写了拦截语句 | 人工读 `dsh-web-app/lib/startup.js`，找到新的拦截写法并更新断言 |

---

## refscan.mjs — 重定 peer 依赖补齐清单

确定 `scripts/setup-windows.ps1` 的 `$PeerFix` 与 `scripts/setup-unix.sh` 的 `PEERS`
里应该写哪些包。

### 为什么清单必须逐版本重定

dsh 的多个子包把彼此声明为 `peerDependencies`，而主包 bundle 未包含它们；
`--legacy-peer-deps` 会跳过这些 peer → 启动报 `ERR_MODULE_NOT_FOUND`。
**缺失集合随版本变化**：`0.1.1-rc.2` 下为 25 个，`0.1.5-rc.2` 下为 26 个。

### 为什么不能靠「跑一次看缺哪个」

绝大多数 `@deepseek-ai/*` 子模块是**懒加载**的，只有走到对应功能才会 `import`。

> 实测：单次启动只报出 **1 个**缺失包，静态说明符扫描报出 **26 个**。
> 漏报的 25 个会在用户用到对应功能时才炸。

### 用法

```bash
node .patch-tools/refscan.mjs "<包根>/.cache/app/node_modules" 0.1.5-rc.2
```

> **路径必须用 Windows 形式**（`D:/...`）。`node.exe` 是原生 Windows 程序，
> 传 Git Bash 的 POSIX 形式（`/d/...`）会静默失败（只打印一行 node 版本号，无报错正文）。

输出示例：

```
扫描文件 730 个
@deepseek-ai/* 说明符 95 个；缺失 0 个
=> 清单完整，无需补齐
```

退出码 `0` = 清单完整；`1` = 存在缺失项（末尾会打印可直接粘贴的数组片段）。

---

## smoke-local.sh — 本地冒烟测试

升级后的端到端验证。**必须全绿才能发版**，任何失败都不得跳过、注释或屏蔽。

### 设计要点

1. **每一步都有 `timeout` 包裹**，绝不允许无限等待
2. **每步开始/结束都打时间戳**，进度实时可见
3. 所有网络/服务操作都带 `--max-time` / `--connect-timeout`
4. 结果汇总为 **用例数 / 通过数 / 通过率**
5. 任何一步超时都**不静默跳过**，标记为 FAIL/TIMEOUT 并计入统计

### 用法

```bash
bash .patch-tools/smoke-local.sh           # 全部 9 个用例
bash .patch-tools/smoke-local.sh --quick   # 跳过 web 相关用例（快速回归）
```

### 用例清单

| # | 用例 | 判定依据 |
|---|------|----------|
| 1 | 依赖就绪 | 便携 Node 版本、dsh 入口存在 |
| 2 | `dsh --version` | 输出等于锁定的 dsh 版本 |
| 3 | `dsh --help` 品牌 | `DeepSeek` 出现 0 次、`USB Harness` 出现 ≥1 次 |
| 4 | 模块解析 | 全部 `@deepseek-ai/*` 说明符可解析，失败 0 |
| 5 | 补丁基线校验 | 安全 17 / 需确认 0 / 阻断 0 / 异常 0 |
| 6 | headless CLI 模式 | 插件树加载成功 |
| 7 | web 服务启动 | 服务端打印出含 token 的 URL 行 |
| 8 | web 首页 HTTP | `token → 303 + Set-Cookie → cookie → 200` |
| 9 | web 首页标题 / 静态资源 | `<title>USB Harness</title>`；JS/CSS 资源全部 200 |

### 两个环境陷阱（排障时首先怀疑）

1. **`/usr/bin` 可能不在 PATH**（Git Bash 环境）→ `grep`/`head`/`sed`/`ps`/`dirname`
   全部找不到，脚本管道静默无输出。脚本已在开头兜底
   `export PATH="/usr/bin:/bin:$PATH"`。

2. **POSIX 路径不能传给原生 Windows 程序** → `node.exe /d/...` 静默退出且只打印
   `Node.js vX.Y.Z`（无报错正文）；`curl.exe -o /d/...` 静默写不出文件（返回 `000`）。
   脚本同时维护 `ROOT`（POSIX，给 bash 用）与 `ROOT_W`（`pwd -W` 得到的 `D:/...`，给原生程序用）。

> 另注：WorkBuddy 的 safe-delete 垫片会拦截 `fs.rm`，破坏 dsh 的 `.lock` 清理。
> 脚本在测试进程里已 `unset CODEBUDDY_SAFE_DELETE_BULK_STATE_DIR` 等变量规避。
