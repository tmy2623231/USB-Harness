# USB Harness — 故障排查

## 症状 → 原因 → 处理

| 症状 | 可能原因 | 处理 |
|------|----------|------|
| 双击 launch.bat 闪退/无窗口 | 执行策略限制、PowerShell 未配置 | 右键「用 PowerShell 运行」；或运行 `powershell -ExecutionPolicy Bypass -File .\scripts\launch-windows.ps1` |
| `node: not found` / 找不到 node | 便携 Node 未就绪 | 运行 `.\scripts\setup-windows.ps1` |
| `node 不是内部或外部命令`（启动器状态/检查更新时） | 系统 PATH 无 node，而 dsh.cmd 垫片靠 PATH 找 node | 已由启动器自动修复（启动器会把便携 node 提到 PATH 最前）。若仍出现，确认 `.cache\runtimes\windows-x64\node\node.exe` 存在，必要时重跑 setup |
| 打开 Web 报「Failed to load plugins. Object.hasOwn is not a function」 | dsh 跑在**旧系统 node**（<16.9，无 `Object.hasOwn`）上 | **务必通过 launch.bat / launch.sh 启动**——启动器强制用便携 node 22.x；不要在命令行直接敲 `dsh` 命令（会命中系统 node）。若系统装过 node-setup.msi 且很旧，建议卸载或至少不要让它抢 PATH |
| `dsh: not found` / `.bin\dsh` 缺失 | dsh 未安装 | 运行 `.\scripts\setup-windows.ps1` |
| 报「requires Node ^22.19.0 || >=24」 | Node 版本不符（如 23） | 确认用 `.cache/runtimes/.../node.exe`（22.23.2），勿用系统 Node 23 |
| 端口 3080 被占用，启动失败 | 其他程序占用 | `launch-windows.ps1 web` 会自动换端口；或设置环境变量后重启 |
| 插件列表大量显示「未启动/禁用」 | **dsh 架构设计，非故障** | agent 工具（tool-fs/tool-web/tool-todo 等）已从 host 平面移到 preset 层，会话启动时由默认 `standard` preset 挂载提供，功能正常；强行在 host 平面启用会重复注册冲突，勿动 |
| 配置的模型 401 / unknown model | API Key 错误 / 网关未暴露模型索引 | 核对 `baseURL` 与 key；网关无 `/models` 索引时手动填写模型 id |
| 浏览器打开空白/连不上 | 服务未起、只监听 loopback | 确认访问 `http://127.0.0.1:<port>`（不是局域网 IP）；看 `data/logs/` |
| `dsh plugin` 装插件报符号链接错误 | exFAT/FAT32 不支持符号链接（仅影响插件安装；核心运行已通过复制回退解决） | 改用 NTFS 或本地磁盘；见 DEPLOYMENT.md |
| 启动极慢 | USB 2.0 / 杀软实时扫描 | 换 USB 3.0/SSD；目录加入杀软排除 |
| 从 U 盘被拒绝执行 | 组策略禁止可移动介质运行 | 复制到本地磁盘运行；或 IT 放行 |
| 报路径过长（260 字符） | U 盘挂在深路径 | 放到盘符根目录；开启长路径支持 |

## 快速定位

```powershell
# 1) 确认便携 Node 与 dsh 就绪
& .\.cache\runtimes\windows-x64\node\node.exe -v
& .\.cache\app\node_modules\.bin\dsh.cmd --version

# 2) 查看 web 子命令可用参数
$env:DSH_HOME = "$PWD\data\dsh"
& .\.cache\app\node_modules\.bin\dsh.cmd web --help

# 3) 打印合并后的配置（排查配置问题）
& .\.cache\app\node_modules\.bin\dsh.cmd web --dump-config
```

## 日志位置

- 启动日志：`data/logs/dsh-web.log`
- dsh 会话/事件流：`data/dsh/sessions/`、`data/dsh/storages/`

## 仍无法解决

- dsh 官方反馈：GitHub Discussions（`deepseek-ai/deepseek-harness/discussions`）
- 请同时提供：`node -v`、`dsh --version`、`dsh web --dump-config`（已脱敏）、
  `data/logs/dsh-web.log` 末尾片段。
