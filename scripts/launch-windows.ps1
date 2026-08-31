# =============================================================================
# launch-windows.ps1 — USB Harness 启动器（Windows）
# 职责：环境校验 → 首启自动安装 → 交互菜单（启动/检查更新/配置/重置/状态/退出）
# 用法：由 launch.bat 调用；也可直接：
#   powershell -ExecutionPolicy Bypass -File .\scripts\launch-windows.ps1 [web|setup|reset|status|check-update|upgrade]
# =============================================================================
[CmdletBinding()]
param(
    [string]$Action = ''   # web=直接启动；setup=重新配置；reset=重置；status=查看状态；
                          # check-update=检查更新；upgrade=检查并升级；空=交互菜单
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
        $harnessVer = ''
        if (Test-Path $ReadyFlag) {
            $hLine = (Get-Content $ReadyFlag -ErrorAction SilentlyContinue) -replace "`r", '' |
                     Where-Object { $_ -like 'harness=*' } | Select-Object -First 1
            if ($hLine) { $harnessVer = $hLine.Substring(8).Trim() }
        }
        if (-not $harnessVer) {
            $hf = Join-Path $Root 'HARNESS_VERSION'
            if (Test-Path $hf) { $harnessVer = ([IO.File]::ReadAllText($hf)).Trim() }
        }
        if ($harnessVer) { Write-Host "  程序版本  : $harnessVer" -ForegroundColor Green }
        else { Write-Host '  程序版本  : 未记录（旧版包）' -ForegroundColor DarkGray }
        Write-Host "  数据目录  : $DshHome"
        Write-Host "  监听地址  : http://0.0.0.0:3080（本机 + 局域网）"
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
switch ($Action.ToLower()) {
    'web'    { Start-Web; exit 0 }
    'setup'  { Invoke-Setup -Force; exit 0 }
    'reset'  { Invoke-Reset; exit 0 }
    'status' { Show-Status; exit 0 }
    'check-update' { & powershell -NoProfile -ExecutionPolicy Bypass -File $UpgradeScript -CheckOnly; exit $LASTEXITCODE }
    'upgrade'      { & powershell -NoProfile -ExecutionPolicy Bypass -File $UpgradeScript; exit $LASTEXITCODE }
}

# 交互菜单
while ($true) {
    Show-Status
    Write-Host '  [1] 启动 Web 界面' -ForegroundColor White
    Write-Host '  [2] 检查更新（程序与 dsh 版本）' -ForegroundColor White
    Write-Host '  [3] 重置（清配置数据，保留运行环境，无需下载）' -ForegroundColor White
    Write-Host '  [4] 退出' -ForegroundColor Gray
    Write-Host ''
    $choice = Read-Host '  请选择'
    switch ($choice.Trim()) {
        '1' { Start-Web }
        '2' { & powershell -NoProfile -ExecutionPolicy Bypass -File $UpgradeScript -CheckOnly }
        '3' { Invoke-Reset }
        '4' { exit 0 }
        default { Write-WarnMsg "无效选择：$choice" }
    }
}
