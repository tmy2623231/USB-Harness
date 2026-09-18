# =============================================================================
# launch-windows.ps1 — USB Harness 启动器（Windows）
# 职责：环境校验 → 首启自动安装 → 交互菜单（启动/检查更新/重置/切换模式/退出）
# 用法：由 launch.bat 调用；也可直接：
#   powershell -ExecutionPolicy Bypass -File .\scripts\launch-windows.ps1 [web|cli|setup|reset|status|check-update|upgrade]
# =============================================================================
[CmdletBinding()]
param(
    [string]$Action = ''   # web=直接启动 Web 界面；cli=直接启动 CLI 单次任务；setup=重新配置；
                          # reset=重置；status=查看状态；check-update=检查更新；
                          # upgrade=检查并升级；空=交互菜单（按 config/launch.conf 的模式启动）
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$Root      = Split-Path -Parent $PSScriptRoot
$Arch      = 'windows-x64'   # 注意：运行时目录是 windows-x64，不是 win-x64
$NodeDir   = Join-Path $Root ".cache\runtimes\$Arch\node"
$NodeExe   = Join-Path $NodeDir 'node.exe'
# dsh 的 CLI 入口（bin.js）。优先用便携 node.exe 绝对路径直调它，彻底摆脱 npm 垫片
# 靠 PATH 找 node 的坑（见下方 Invoke-Dsh 注释）；垫片仅作 bin.js 缺失时的回退。
$DshCli    = Join-Path $Root '.cache\app\node_modules\@deepseek-ai\dsh\lib\bin.js'
$DshCmd    = Join-Path $Root '.cache\app\node_modules\.bin\dsh.cmd'
$DshHome   = Join-Path $Root 'data\dsh'
$LogDir    = Join-Path $Root 'data\logs'
$LogFile   = Join-Path $LogDir 'dsh-web.log'
$ErrLog    = Join-Path $LogDir 'dsh-web.err.log'
$ReadyFlag = Join-Path $Root '.ready.flag'
$UpgradeScript = Join-Path $PSScriptRoot 'upgrade-windows.ps1'
# 运行模式持久化位置（config/launch.conf，与 launch.sh 共用同一格式）
$LaunchConf = Join-Path $Root 'config\launch.conf'

# 兜底：把便携 node 目录提到 PATH 最前（对 dsh 内部再派生的子进程同样生效）。
# 注意：这只是兜底——dsh 主进程的 node 解析已不再依赖 PATH（见 Invoke-Dsh）。
$env:Path = "$NodeDir;$env:Path"

New-Item -ItemType Directory -Force -Path $DshHome, $LogDir | Out-Null

# ---------------------------------------------------------------------------
# 工具函数
# ---------------------------------------------------------------------------
function Write-Step($msg)  { Write-Host ''; Write-Host "[启动] $msg" -ForegroundColor Cyan }
function Write-Done($msg)  { Write-Host "[完成] $msg" -ForegroundColor Green }
function Write-WarnMsg($m) { Write-Host "[警告] $m" -ForegroundColor Yellow }

function Test-Port {
    param([int]$Port)
    $listener = $null
    try {
        $listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, $Port)
        $listener.Start()
        return $true
    } catch { return $false }
    finally { if ($null -ne $listener) { $listener.Stop() } }
}

function Get-FreePort {
    param([int]$StartPort = 3080)
    for ($p = $StartPort; $p -lt ($StartPort + 100); $p++) {
        if (Test-Port -Port $p) { return $p }
    }
    throw "在 $StartPort - $($StartPort + 99) 范围内未找到空闲端口"
}

# ---------------------------------------------------------------------------
# 运行模式（web / cli）读写
# 默认 web：文件缺失、为空、值无法识别时一律回落 web —— 保证不改变既有默认行为。
# ---------------------------------------------------------------------------
function Get-LaunchMode {
    if (-not (Test-Path $LaunchConf)) { return 'web' }
    try {
        $line = Get-Content $LaunchConf -ErrorAction SilentlyContinue |
                Where-Object { $_ -match '^\s*mode\s*=' } | Select-Object -First 1
        if (-not $line) { return 'web' }
        $v = ($line -split '=', 2)[1]
        if ($null -eq $v) { return 'web' }
        $v = $v.Trim().Trim('"').Trim("'").ToLower()
        if ($v -eq 'cli') { return 'cli' }
        return 'web'
    } catch { return 'web' }
}

function Get-LaunchModeLabel {
    param([string]$Mode)
    if ($Mode -eq 'cli') { return 'CLI（单次任务 task）' }
    return 'Web（图形界面）'
}

# 环境就绪？（便携 Node 与 dsh 入口都在；bin.js 缺失时接受垫片回退）
function Test-Ready {
    return ((Test-Path $NodeExe) -and ((Test-Path $DshCli) -or (Test-Path $DshCmd)))
}

# 统一调用 dsh：
#   - 首选：& $NodeExe $DshCli —— 便携 node 的绝对路径直调 CLI 入口。dsh.cmd 垫片
#     （#!/usr/bin/env node 的 Windows 版）靠 PATH 找 node：干净机器报「node 不是内部
#     或外部命令」，装了旧系统 node（<16.9，无 Object.hasOwn）的机器会命中老版本，
#     导致插件树加载失败（Failed to load plugins. Object.hasOwn is not a function）。
#     直调后这两类问题从根上消失。
#   - 回退：$DshCmd 垫片（仅当 bin.js 缺失的极老目录结构）。
function Invoke-Dsh {
    param([Parameter(ValueFromRemainingArguments = $true)][string[]]$DshArgs)
    if (Test-Path $DshCli) { & $NodeExe $DshCli @DshArgs }
    else                   { & $DshCmd @DshArgs }
}

# 运行首次配置（不加 -Force = 只补丁/修复，不重新下载；-Force = 完全重装需下载）
function Invoke-Setup {
    param([switch]$Force)
    $setup = Join-Path $PSScriptRoot 'setup-windows.ps1'
    if ($Force) { & powershell -NoProfile -ExecutionPolicy Bypass -File $setup -Force }
    else        { & powershell -NoProfile -ExecutionPolicy Bypass -File $setup }
    if ($LASTEXITCODE -ne 0) { throw "配置失败（退出码 $LASTEXITCODE）" }
}

# 读取本包版本（程序版本）：优先 .ready.flag 的 harness= 行，缺失回退 HARNESS_VERSION
# 文件（Release 打包写入）；两者皆无 = 旧版包结构，返回空串。
function Get-HarnessVersion {
    $v = ''
    if (Test-Path $ReadyFlag) {
        $hLine = (Get-Content $ReadyFlag -ErrorAction SilentlyContinue) -replace "`r", '' |
                 Where-Object { $_ -like 'harness=*' } | Select-Object -First 1
        if ($hLine) { $v = $hLine.Substring(8).Trim() }
    }
    if (-not $v) {
        $hf = Join-Path $Root 'HARNESS_VERSION'
        if (Test-Path $hf) { $v = ([IO.File]::ReadAllText($hf)).Trim() }
    }
    return $v
}

# 显示状态
function Show-Status {
    Write-Host ''
    Write-Host '--------------------------------------------' -ForegroundColor Cyan
    Write-Host '  USB Harness 状态' -ForegroundColor Cyan
    Write-Host '--------------------------------------------' -ForegroundColor Cyan
    if (Test-Ready) {
        $nodeVer = & $NodeExe -v
        $dshVer  = Invoke-Dsh --version 2>$null | Select-Object -Last 1
        Write-Host "  便携 Node : $nodeVer" -ForegroundColor Green
        Write-Host "  dsh 版本  : $dshVer"
        $harnessVer = Get-HarnessVersion
        if ($harnessVer) { Write-Host "  程序版本  : $harnessVer" -ForegroundColor Green }
        else { Write-Host '  程序版本  : 未记录（旧版包）' -ForegroundColor DarkGray }
        Write-Host "  数据目录  : $DshHome"
        $mode = Get-LaunchMode
        Write-Host "  默认模式  : $(Get-LaunchModeLabel $mode)（菜单直接选，无需切换）"
        if ($mode -eq 'web') {
            Write-Host '  监听地址  : http://0.0.0.0:3080（本机 + 局域网）'
        } else {
            Write-Host '  监听地址  : 不适用（单次任务模式不监听端口）' -ForegroundColor DarkGray
        }
        if (Test-Path $ReadyFlag) { Write-Host '  就绪标记  : 已就绪' -ForegroundColor Green }
        else { Write-Host '  就绪标记  : 缺失（将自动重新配置）' -ForegroundColor Yellow }
    } else {
        Write-Host '  环境      : 未安装（首次使用需联网下载）' -ForegroundColor Yellow
    }
    Write-Host '--------------------------------------------' -ForegroundColor Cyan
    Write-Host ''
}

# 启动 Web 界面（长驻进程，Ctrl+C 停止后返回菜单）
function Start-Web {
    $usePort = 3080
    if (-not (Test-Port -Port 3080)) {
        Write-WarnMsg '3080 已被占用，自动选择空闲端口 ...'
        $usePort = Get-FreePort -StartPort 3081
    }
    Write-Step "启动 Web 界面（http://127.0.0.1:$usePort）"
    Write-Host "  本机访问:   http://127.0.0.1:$usePort" -ForegroundColor Green
    Write-Host "  局域网访问: http://<本机IP>:$usePort" -ForegroundColor Green
    Write-Host "  提示: 功能完整请用本机地址 127.0.0.1（局域网 IP 访问时部分功能受限）" -ForegroundColor DarkGray
    Write-Host "  正在启动服务，请稍候… 浏览器将在服务就绪后自动打开" -ForegroundColor DarkGray
    Write-Host "  按 Ctrl+C 停止服务" -ForegroundColor DarkGray
    Write-Host ''

    $env:DSH_HOME = $DshHome
    $env:Path = "$NodeDir;$env:Path"
    # USB Harness: dsh 自动打开的是 http://0.0.0.0:port（浏览器不可访问），
    # 故加 --no-open，由这里轮询端口「可连接」后再打开正确的 http://127.0.0.1:port。
    # 注意：不能用 TcpListener 绑定探测——Windows 允许特定 IP 与通配 0.0.0.0 绑定共存，
    # 会永远误判为"空闲"而不打开浏览器；必须用连接探测（能连上 = 服务就绪）。
    Start-Job -ArgumentList $usePort -ScriptBlock {
        param($p)
        $ready = $false
        for ($i = 0; $i -lt 120; $i++) {
            Start-Sleep -Milliseconds 500
            $client = New-Object System.Net.Sockets.TcpClient
            try {
                $iar = $client.BeginConnect('127.0.0.1', $p, $null, $null)
                if ($iar.AsyncWaitHandle.WaitOne(1500)) {
                    $client.EndConnect($iar)
                    $ready = $true
                    break
                }
            } catch { } finally { $client.Close() }
        }
        if ($ready) { Start-Process "http://127.0.0.1:$p" }
        else { Write-Host "端口 $p 未在 60 秒内就绪，请手动打开 http://127.0.0.1:$p" -ForegroundColor Yellow }
    } | Out-Null
    # 不用 2>&1 | Tee-Object：PowerShell 会把 dsh 的每行 stderr 包成 ErrorRecord 并以整屏
    # 红色块显示，真正的错误信息反而被淹没（历史上 Object.hasOwn 报错就是这样被藏起来的）。
    # 改为 stdout 走 Tee（实时回显+记日志）、stderr 落 err.log；退出码非 0 时打印 err.log
    # 尾部，让失败原因直接可见。
    Remove-Item $ErrLog -Force -ErrorAction SilentlyContinue
    Invoke-Dsh web --port "$usePort" --host 0.0.0.0 --no-open 2>>$ErrLog | Tee-Object -FilePath $LogFile -Append
    $exit = $LASTEXITCODE
    if ($exit -ne 0 -and (Test-Path $ErrLog)) {
        Write-Host ''
        Write-Host "[错误] dsh 退出码 $exit。错误详情（$ErrLog）：" -ForegroundColor Red
        Get-Content $ErrLog -Tail 30 | ForEach-Object { Write-Host "  $_" -ForegroundColor Red }
    }
    Write-Host ''
    Write-Host "dsh 已退出（代码 $exit）。按回车键返回菜单 ..." -ForegroundColor DarkGray
    Read-Host
}

# 启动 dsh 单次任务模式（headless profile）
#
# 【重要变更 — dsh 0.1.5 起】
# 0.1.5 取消了「无默认执行档位」的行为：裸跑 `dsh` 会直接报
#   error: --profile <name> is required
# 且上游**不再提供开箱即用的交互式终端对话档位**，可用的只有 web / headless / acp / sdk。
# 因此原先「不带子命令进入交互式 TUI」的设计前提已不存在，改为使用 headless：
#   dsh --profile headless "<task>"  ->  跑一个全新会话，打印最终答案后退出
#
# 【文案对齐 — 与上游 dsh 用词一致】
# 上游 `dsh --profile headless --help` 原文：
#   Usage: dsh --profile headless [options] [task...]
#   Arguments: task   the task text; multiple words are joined by spaces
#   Answer one task, stream reasoning to stderr, print the final assistant message, and exit.
# 因此本启动器统一用「任务 / task」表述，并显式给出等价的原生命令，方便用户脱离
# 菜单直接调用 dsh（也是本模式最可靠的验证方式）。
#
# 与 Start-Web 共用同一份环境变量（DSH_HOME / PATH），模型配置与会话数据完全一致。
function Start-Cli {
    Write-Step '启动 dsh 单次任务模式（task / headless profile）'
    Write-Host '  说明: 输入一个任务（task），dsh 跑完一次会话后打印最终答案并退出' -ForegroundColor DarkGray
    Write-Host '  等价命令: dsh --profile headless "<task>"' -ForegroundColor DarkGray
    Write-Host '  提示: 本模式不监听端口，浏览器访问不可用' -ForegroundColor DarkGray
    Write-Host '  想持续对话/图形界面: 返回菜单后选 [1] 启动 Web 界面即可，无需切换' -ForegroundColor DarkGray
    Write-Host ''

    $env:DSH_HOME = $DshHome
    $env:Path = "$NodeDir;$env:Path"
    $CliLog = Join-Path $LogDir 'dsh-cli.log'
    $CliErr = Join-Path $LogDir 'dsh-cli.err.log'

    Write-Host '请输入任务内容 / task（直接回车取消）:' -ForegroundColor Cyan
    $task = Read-Host 'task'
    if (-not $task -or -not $task.Trim()) {
        Write-Host '  已取消，未执行任何任务。' -ForegroundColor DarkGray
        Start-Sleep -Milliseconds 800
        return
    }

    Write-Host ''
    Write-Host "  [task] $task" -ForegroundColor DarkGray
    Write-Host ''
    Remove-Item $CliErr -Force -ErrorAction SilentlyContinue

    # ---------------------------------------------------------------------
    # 【为什么这里不能用 `Invoke-Dsh ... 2>>$CliErr | Tee-Object`】
    #
    # headless 档位把「推理过程」写到 **stderr**（上游原话："stream reasoning to
    # stderr, print the final assistant message, and exit"）。而 PowerShell 的原生
    # 命令管道会把子进程的每一行 stderr 包成 ErrorRecord 渲染成红字，形如：
    #
    #     node.exe : dsh: reasoning:
    #     + CategoryInfo : NotSpecified: (dsh: reasoning::String) [], RemoteException
    #     + FullyQualifiedErrorId : NativeCommandError
    #
    # 后果有两个，都很难受：
    #   1. 满屏红字把**真正的答案**（在 stdout）淹没 —— 用户以为程序崩了；
    #   2. 实测 `2>>$CliErr` 还会让 err.log **写成 0 字节**，日志也失效。
    #
    # 因此改用 .NET Process 直接读两条流：stdout 是答案（正常色回显），
    # stderr 是推理过程（暗灰回显 + 落日志），两条流各归各位、互不污染。
    # 实测：stdout 6 字节 `1+1=2` / stderr 184 字节 `dsh: reasoning: …`，干净分离。
    # ---------------------------------------------------------------------
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $NodeExe
    $psi.Arguments = '"' + $DshCli + '" --profile headless "' + $task + '"'
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.StandardOutputEncoding = [Text.Encoding]::UTF8
    $psi.StandardErrorEncoding = [Text.Encoding]::UTF8
    $psi.CreateNoWindow = $true

    $proc = New-Object System.Diagnostics.Process
    $proc.StartInfo = $psi
    $proc.Start() | Out-Null

    # 必须并发读两条流：若串行读，写满 pipe 缓冲区（约 4KB）就会互相死锁。
    $outTask = $proc.StandardOutput.ReadToEndAsync()
    $errTask = $proc.StandardError.ReadToEndAsync()

    # 等待期间给个呼吸提示（大模型首字可能要几秒到几十秒）
    $waited = 0
    while (-not $proc.WaitForExit(1000)) {
        $waited++
        if ($waited -eq 3) {
            Write-Host '  dsh 正在思考…（推理过程属于正常输出，不是报错）' -ForegroundColor DarkGray
        }
    }
    $stdout = $outTask.Result
    $stderr = $errTask.Result
    $exit = $proc.ExitCode

    # 推理过程落日志（便于事后排查），但只在终端用暗灰轻提示，不刷红字
    if ($stderr.Trim()) {
        Add-Content -Path $CliErr -Value $stderr -Encoding UTF8
    }
    if ($stdout.Trim()) {
        Add-Content -Path $CliLog -Value $stdout -Encoding UTF8
    }

    Write-Host ''
    if ($stdout.Trim()) {
        Write-Host '  ===== 最终答案 =====' -ForegroundColor Cyan
        Write-Host ''
        $stdout.TrimEnd() -split "`r?`n" | ForEach-Object { Write-Host "  $_" }
        Write-Host ''
        Write-Host "  （推理过程已写入 $CliErr）" -ForegroundColor DarkGray
    } else {
        Write-Host '  （本次没有产生最终答案）' -ForegroundColor Yellow
        if ($stderr.Trim()) {
            Write-Host "  详细信息：$CliErr" -ForegroundColor DarkGray
        }
    }

    if ($exit -ne 0) {
        Write-Host ''
        Write-Host "[错误] dsh headless 退出码 $exit。" -ForegroundColor Red
        if ($stderr.Trim()) {
            Write-Host '  错误详情：' -ForegroundColor Red
            $stderr.TrimEnd() -split "`r?`n" | Select-Object -Last 30 | ForEach-Object { Write-Host "    $_" -ForegroundColor Red }
        }
        if ($stderr -match 'NO_ADAPTER') {
            Write-Host ''
            Write-Host '  [提示] NO_ADAPTER 表示「插件树已加载成功，但没有可用的模型」。' -ForegroundColor Yellow
            Write-Host '         请返回菜单选 [1] 启动 Web 界面，在 设置 → 模型 里配置一个提供方后再试。' -ForegroundColor Yellow
        }
    }
    Write-Host ''
    Write-Host "dsh 已退出（代码 $exit）。按回车键返回菜单 ..." -ForegroundColor DarkGray
    Read-Host
}

# 启动（按「本次」的选择分派；不再读取持久模式，见上方说明）
function Start-Harness {
    param([ValidateSet('web', 'cli')][string]$Mode)
    if ($Mode -eq 'cli') { Start-Cli } else { Start-Web }
}

# 【为什么取消了「切换运行模式」这一项】
# 原先的流程是「[4] 切换模式 → 下次 [1] 启动才生效」，用户要先切换、再启动，
# 绕了一圈还容易忘。本质问题是：**运行模式几乎总是「这一次」的选择**，
# 却用了「先改持久配置、下次生效」的交互去表达它。
# 改为菜单里直接选——选完即执行，不需要先切换、也不需要记住当前处在哪个模式。
# config/launch.conf 仍然保留并继续维护：命令行直启（launch.bat / launch.sh 带参数）
# 需要它作为默认值，且「重置」等流程也依赖该文件存在。
# 注意：这里【不】写回 launch.conf。菜单选择是一次性动作，
# 改持久值会让「上次点了什么」悄悄影响下次不带参数的启动，反而更难预期。

# 重置
function Invoke-Reset {
    $reset = Join-Path $PSScriptRoot 'reset-windows.ps1'
    & powershell -NoProfile -ExecutionPolicy Bypass -File $reset -Root $Root
}

# ---------------------------------------------------------------------------
# 主流程
# ---------------------------------------------------------------------------
Write-Host ''
Write-Host '============================================' -ForegroundColor Cyan
Write-Host '   USB Harness — 便携式 AI 助手' -ForegroundColor Cyan
# 启动横幅直接显示版本号，一眼可见（状态面板里也有）
$bannerVer = Get-HarnessVersion
if ($bannerVer) { Write-Host "   版本      : v$bannerVer" -ForegroundColor Green }
else { Write-Host '   版本      : 未记录（旧版包）' -ForegroundColor DarkGray }
Write-Host '============================================' -ForegroundColor Cyan

# 环境就绪校验，缺失则自动安装
if (-not (Test-Ready)) {
    Write-WarnMsg '未检测到运行环境，首次使用需要联网下载便携 Node 与 dsh（约 3-8 分钟）。'
    Write-Host '是否现在安装？[Y/N]' -ForegroundColor Yellow -NoNewline
    $ans = Read-Host
    if ($ans -match '^[Yy]') {
        Invoke-Setup
    } else {
        Write-Host '已取消安装。'
        exit 0
    }
}

# 升级残留裁决（幂等，无网络）：上次升级中断时自动恢复环境
& powershell -NoProfile -ExecutionPolicy Bypass -File $UpgradeScript -ReconcileOnly

# 命令行动作直通
# web / cli 为显式指定，优先于 config/launch.conf 里记录的当前模式；
# 不带参数（进入交互菜单）时才按记录的模式分派。
switch ($Action.ToLower()) {
    'web'    { Start-Web; exit 0 }
    'cli'    { Start-Cli; exit 0 }
    'setup'  { Invoke-Setup -Force; exit 0 }
    'reset'  { Invoke-Reset; exit 0 }
    'status' { Show-Status; exit 0 }
    'check-update' { & powershell -NoProfile -ExecutionPolicy Bypass -File $UpgradeScript -CheckOnly; exit $LASTEXITCODE }
    'upgrade'      { & powershell -NoProfile -ExecutionPolicy Bypass -File $UpgradeScript; exit $LASTEXITCODE }
}

# 交互菜单
while ($true) {
    Show-Status
    Write-Host '  [1] 启动 Web 界面（图形化，浏览器访问）' -ForegroundColor White
    Write-Host '  [2] 单次任务 CLI（输入一个 task，跑完打印答案后退出）' -ForegroundColor White
    Write-Host '  [3] 检查更新（程序与 dsh 版本）' -ForegroundColor White
    Write-Host '  [4] 重置（清配置数据，保留运行环境，无需下载）' -ForegroundColor White
    Write-Host '  [5] 退出' -ForegroundColor Gray
    Write-Host ''
    $choice = (Read-Host '  请选择').Trim()
    switch ($choice) {
        '1' { Start-Harness -Mode web }
        '2' { Start-Harness -Mode cli }
        '3' { & powershell -NoProfile -ExecutionPolicy Bypass -File $UpgradeScript -CheckOnly }
        '4' { Invoke-Reset }
        '5' { exit 0 }
        ''  { }
        default { Write-WarnMsg "无效选择：$choice" }
    }
}
