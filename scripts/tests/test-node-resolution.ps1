# =============================================================================
# test-node-resolution.ps1 — 回归测试（RT）：dsh 启动不再依赖 PATH 找 node
#
# 背景（历史线上事故）：
#   dsh.cmd / dsh 垫片（#!/usr/bin/env node 的 Windows 版）靠 PATH 找 node：
#     - 干净机器（无系统 node）    -> 「node 不是内部或外部命令」
#     - 装有旧系统 node（<16.9，无 Object.hasOwn）-> 插件树加载失败
#       （Failed to load plugins. Object.hasOwn is not a function）
#   线上证据：launch-windows.ps1 第 75 行 $dshVer = & $DshCmd --version 曾整屏报红。
# 修复：launch-windows.ps1 / upgrade-windows.ps1 一律用便携 node.exe 绝对路径
#   直调 CLI 入口（.cache\app\node_modules\@deepseek-ai\dsh\lib\bin.js），
#   不再经过依赖 PATH 的 npm 垫片（垫片仅作 bin.js 缺失时的回退）。
#
# 本测试做法（全离线、确定性、秒级）：
#   在 $env:TEMP 搭一个最小沙箱：
#     - 便携 node = 真实 node.exe（本机 / CI runner 自带，复制进沙箱）
#     - 便携 dsh  = stub bin.js（--version 输出 0.1.1-rt）
#     - 旧系统 node = node.cmd（打印 v14.0.0，模拟无 Object.hasOwn 的旧版）
#   A. PATH 无任何 node       -> launch status 必须仍解析到便携 node
#   B. PATH 前置旧 node.cmd   -> 必须仍解析到便携 node（不被带偏）
#   负对照：用垫片 dsh.cmd + B 的 PATH -> 必然命中 v14.0.0（证明环境/测试有效，
#   若有人把启动器改回调用垫片，本测试会立即变红）。
#
# 用法：powershell -NoProfile -ExecutionPolicy Bypass -File scripts/tests/test-node-resolution.ps1
# 退出码：0 = 通过；1 = 失败
# =============================================================================
$ErrorActionPreference = 'Stop'
$script:failed = $false

function Assert($cond, $msg) {
    if ($cond) { Write-Host "[PASS] $msg" -ForegroundColor Green }
    else {
        Write-Host "[FAIL] $msg" -ForegroundColor Red
        # 失败细节打进 ::error:: annotation（公共仓库可经 check-run API 匿名读取）
        Write-Host "::error::$msg"
        $script:failed = $true
    }
}

$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$tmp = Join-Path $env:TEMP ("uhb-rt-" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path $tmp | Out-Null

try {
    # ---- 沙箱布局 ----
    $scriptDir = Join-Path $tmp 'scripts'
    New-Item -ItemType Directory -Force -Path $scriptDir | Out-Null
    Copy-Item (Join-Path $repoRoot 'scripts\launch-windows.ps1') $scriptDir
    Copy-Item (Join-Path $repoRoot 'scripts\upgrade-windows.ps1') $scriptDir

    $nodeDir = Join-Path $tmp '.cache\runtimes\windows-x64\node'
    $dshPkg  = Join-Path $tmp '.cache\app\node_modules\@deepseek-ai\dsh'
    $binDir  = Join-Path $tmp '.cache\app\node_modules\.bin'
    $dshCli  = Join-Path $dshPkg 'lib\bin.js'
    New-Item -ItemType Directory -Force -Path $nodeDir, (Join-Path $dshPkg 'lib'), $binDir | Out-Null

    # 便携 node = 真实 node.exe（CI runner 预装）
    $realNode = (Get-Command node.exe -ErrorAction SilentlyContinue).Source
    if (-not $realNode) { throw '找不到真实 node.exe（测试需本机或 CI runner 预装 Node）' }
    Copy-Item $realNode (Join-Path $nodeDir 'node.exe')

    # 便携 dsh CLI = stub bin.js
    $stubJs = @'
if (process.argv.includes("--version")) { console.log("0.1.1-rt"); process.exit(0); }
console.error("stub: unexpected args " + process.argv.slice(2).join(" "));
process.exit(42);
'@
    [IO.File]::WriteAllText($dshCli, $stubJs.Replace("`r`n", "`n"))

    # 旧系统 node = node.cmd（打印 v14.0.0，忽略参数）
    $oldNodeDir = Join-Path $tmp 'sysnode-old'
    New-Item -ItemType Directory -Force -Path $oldNodeDir | Out-Null
    [IO.File]::WriteAllText((Join-Path $oldNodeDir 'node.cmd'), "@echo off`r`necho v14.0.0`r`n")

    # 垫片 dsh.cmd（负对照）：模拟 npm 生成的垫片，靠 PATH 找 node
    [IO.File]::WriteAllText((Join-Path $binDir 'dsh.cmd'),
        "@ECHO off`r`nSETLOCAL`r`nSET `"_prog=node`"`r`n`"%_prog%`" `"%~dp0..\@deepseek-ai\dsh\lib\bin.js`" %*`r`n")

    # 受控 PATH 需含 powershell.exe 所在目录（launch 内部会再调 powershell -ReconcileOnly）
    $basePath = "$env:SystemRoot\System32\WindowsPowerShell\v1.0;$env:SystemRoot\System32;$env:SystemRoot"
    $emptyDir = Join-Path $tmp 'emptydir'
    New-Item -ItemType Directory -Force -Path $emptyDir | Out-Null

    # ---- 受控子进程执行器（自定义 PATH，不继承本进程 PATH）----
    # 已知：windows-latest runner 上 spawn powershell.exe 偶发 0xC0000142（DLL 初始化
    # 失败），会抛异常而非正常退出——捕获并重试 3 次，避免环境抖动误杀测试。
    function Invoke-WithPath([string]$path, [string]$file, [string]$arguments) {
        for ($t = 1; $t -le 3; $t++) {
            try {
                $psi = New-Object System.Diagnostics.ProcessStartInfo
                $psi.FileName = $file
                $psi.Arguments = $arguments
                $psi.UseShellExecute = $false
                $psi.RedirectStandardOutput = $true
                $psi.RedirectStandardError = $true
                $psi.Environment['Path'] = $path
                $p = [System.Diagnostics.Process]::Start($psi)
                $stdout = $p.StandardOutput.ReadToEnd()
                $stderr = $p.StandardError.ReadToEnd()
                $p.WaitForExit()
                return @{ Exit = $p.ExitCode; Out = $stdout; Err = $stderr }
            } catch {
                Write-Host "  [warn] 子进程启动失败（第 $t 次）: $($_.Exception.Message)" -ForegroundColor DarkYellow
                Start-Sleep -Seconds 2
            }
        }
        throw "子进程连续 3 次启动失败: $file $arguments"
    }

    # ---- 场景 A：PATH 无任何 node ----
    Write-Host ''
    Write-Host '== 场景 A：PATH 无任何 node ==' -ForegroundColor Cyan
    $rA = Invoke-WithPath "$emptyDir;$basePath" 'powershell.exe' `
        "-NoProfile -ExecutionPolicy Bypass -File `"$scriptDir\launch-windows.ps1`" status"
    Assert ($rA.Exit -eq 0) ("A) 退出码=0（实际 $($rA.Exit)）")
    Assert ($rA.Out -match '便携 Node\s*:\s*v\d') 'A) 便携 Node 显示真实版本'
    Assert ($rA.Out -match 'dsh 版本\s*:\s*0\.1\.1-rt') 'A) dsh 版本显示 0.1.1-rt'
    Assert ($rA.Out -notmatch '不是内部或外部命令|not recognized as an internal') 'A) stdout 无 node 找不到类报错'
    Assert ($rA.Err -notmatch '不是内部或外部命令|not recognized as an internal') 'A) stderr 无 node 找不到类报错'

    # ---- 场景 B：旧系统 node 前置（垫片必被带偏，直调不受影响）----
    Write-Host ''
    Write-Host '== 场景 B：PATH 前置旧 node.cmd(v14.0.0) ==' -ForegroundColor Cyan
    $rB = Invoke-WithPath "$oldNodeDir;$basePath" 'powershell.exe' `
        "-NoProfile -ExecutionPolicy Bypass -File `"$scriptDir\launch-windows.ps1`" status"
    Assert ($rB.Exit -eq 0) ("B) 退出码=0（实际 $($rB.Exit)）")
    Assert ($rB.Out -match '便携 Node\s*:\s*v\d') 'B) 便携 Node 为真实版本'
    Assert ($rB.Out -notmatch 'v14\.0\.0') 'B) 未命中旧系统 node v14.0.0'
    Assert ($rB.Out -match 'dsh 版本\s*:\s*0\.1\.1-rt') 'B) dsh 版本仍为 0.1.1-rt'

    # ---- 负对照：垫片 dsh.cmd + 旧 node PATH -> 必然命中 v14.0.0 ----
    Write-Host ''
    Write-Host '== 负对照1：垫片 dsh.cmd + 旧 node PATH（应命中 v14.0.0）==' -ForegroundColor Cyan
    $rN = Invoke-WithPath "$oldNodeDir;$basePath" 'cmd.exe' "/c `"$binDir\dsh.cmd`" --version"
    $negOut = ($rN.Out -split "`r?`n" | Where-Object { $_ -match 'v\d' } | Select-Object -Last 1)
    Assert ($negOut -match 'v14\.0\.0') ("负对照1: 垫片被旧 node 带偏（实际 '$negOut'）——证明测试环境有效")

    # ---- 负对照2：垫片 dsh.cmd + 无 node PATH -> 必然报 node 找不到 ----
    # 注意：windows-latest runner 为英文系统，cmd 报错是 "not recognized as an
    # internal or external command"，中文系统才是「不是内部或外部命令」，两者都匹配。
    Write-Host ''
    Write-Host '== 负对照2：垫片 dsh.cmd + 无 node PATH（应报 node 找不到）==' -ForegroundColor Cyan
    $rN2 = Invoke-WithPath "$emptyDir;$basePath" 'cmd.exe' "/c `"$binDir\dsh.cmd`" --version"
    Assert ($rN2.Err -match '不是内部或外部命令|not recognized as an internal') "负对照2: 垫片在无 node 环境下报错（实际: $($rN2.Err.Trim())）——证明两个历史失败模式均由垫片 PATH 解析引起"

    Write-Host ''
    if ($script:failed) { Write-Host '[RT] 失败' -ForegroundColor Red; exit 1 }
    Write-Host '[RT] 全部通过' -ForegroundColor Green
    exit 0
}
finally {
    Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
}
