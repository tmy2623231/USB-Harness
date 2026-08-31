## USB Harness 0.1.1-rc.2.1 — 完整包（含运行时，下载即用）

> 适配 dsh `0.1.1-rc.2`，版本号为 dsh 版本 + 包装补丁号（`.1` = 本项目独立热修复）。

### 修复（根治 node 解析问题）

- **不再经过 dsh 的 npm 垫片**：`dsh.cmd` / `.bin/dsh` 靠 PATH 找 node，曾导致两类事故——
  - 干净机器（无系统 node）：`node 不是内部或外部命令`
  - 装有旧系统 node（<16.9，无 `Object.hasOwn`）：Web 打开报 `Failed to load plugins. Object.hasOwn is not a function`
- **根治**：启动器 / 升级脚本一律用**便携 node 的绝对路径**直调 CLI 入口
  （`.cache/app/node_modules/@deepseek-ai/dsh/lib/bin.js`），与系统是否装了 node、多旧**完全无关**。
- Web 启动失败时不再被 PowerShell 红块淹没：stderr 落 `data/logs/dsh-web.err.log`，
  退出码非 0 时直接打印错误尾部，一眼看到真实原因。

### 回归测试（RT）

- 新增 `scripts/tests/test-node-resolution.ps1 / .sh`：在「PATH 无 node」与「PATH 只有旧 node」
  两种环境下断言启动器仍解析到便携 node，并带负对照（垫片必然被带偏 / 报错）；
  已接入 CI（Windows 步骤 + 新增 Linux job）。任何人改回垫片调用，CI 立即红。

### 升级方式

1. 下载 `USB-Harness-with-runtime.zip`，解压即可用
2. 若要保留原有数据：把旧目录里的 `data/dsh/` 复制到新目录同名位置

> 完整变更见 [CHANGELOG.md](https://github.com/tmy2623231/USB-Harness/blob/main/CHANGELOG.md)。
