# =============================================================================
# upgrade-windows.ps1 — 检查更新 / 升级 dsh（Windows）
# 设计要点：
#   - 双层检测：①本项目新 Release（GitHub API，主路径，提示浏览器下载）
#              ②dsh 上游 latest（npmmirror 优先回退官方，需项目适配后才能升级）
#   - data/ 全程零改动；升级失败自动回滚（.cache/app 改名备份 + journal）
#   - 断电/中断残留由 -ReconcileOnly 裁决（launch 启动时调用，幂等无网络）
# 用法：
#   powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\upgrade-windows.ps1 -CheckOnly
#   powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\upgrade-windows.ps1            # 交互式检查+可选升级
#   powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\upgrade-windows.ps1 -DshVersion x.y.z
#   powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\upgrade-windows.ps1 -ReconcileOnly
# 退出码：0=已最新或升级成功  1=有更新（仅 CheckOnly）  2=网络不可达  3=本地版本未知
#         4=peer 未适配被阻断  5=升级失败已回滚  6=磁盘不足已降级中止
# =============================================================================
[CmdletBinding()]
param(
    [switch]$CheckOnly,
    [switch]$ReconcileOnly,
    [string]$DshVersion = '',
    [string]$Root = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not $Root) { $Root = Split-Path -Parent $PSScriptRoot }
$PSDefaultParameterValues['Out-File:Encoding'] = 'ascii'

# ---- 兼容 Windows PowerShell 5.1 的 TLS（GitHub API 必须 Tls12）----
try { [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12 } catch {}

# ---- 常量与路径 ----
$Repo        = 'tmy2623231/USB-Harness'
$FlagFile    = Join-Path $Root '.ready.flag'
$SetupScript = Join-Path $Root 'scripts\setup-windows.ps1'
$AppDir      = Join-Path $Root '.cache\app'
$BakDir      = Join-Path $Root '.cache\app.bak-upgrade'
$Journal     = Join-Path $Root '.cache\upgrade.state'
$NpmCache    = Join-Path $Root '.cache\npm-cache'
$NodeDir     = Join-Path $Root '.cache\runtimes\windows-x64\node'
$NodeExe     = Join-Path $NodeDir 'node.exe'
$NodeNpm     = Join-Path $NodeDir 'npm.cmd'
$DshCmd      = Join-Path $AppDir 'node_modules\.bin\dsh.cmd'
$SelfCheckOut = Join-Path $Root 'data\logs\dsh-selfcheck.log'
$SelfCheckErr = Join-Path $Root 'data\logs\dsh-selfcheck.err.log'

# 与 launch-windows.ps1 同理：dsh.cmd 垫片靠 PATH 找 node，独立运行本脚本时
# 也必须预置便携 node 目录（Get-LocalVersions / Test-DshInstall 都要调 dsh.cmd）。
# 由 launch 调起时父进程已预置，此处再置一遍是幂等的。
$env:Path = "$NodeDir;$env:Path"

function Write-WarnMsg([string]$m) { Write-Host "  [!] $m" -ForegroundColor Yellow }
function Write-Info([string]$m)    { Write-Host "  $m" }
function Write-Ok([string]$m)      { Write-Host "  [OK] $m" -ForegroundColor Green }   # 用 [OK] 而非 ✓，兼容 GBK 控制台

# ---------------------------------------------------------------------------
# 本地版本：dsh 优先跑 --version（实装事实），flag 作后备；harness 读 flag/包根文件
# ---------------------------------------------------------------------------
function Get-LocalVersions {
    $result = @{ dsh = 'unknown'; harness = ''; node = 'unknown' }

    if (Test-Path $DshCmd) {
        $v = & cmd /c "`"$DshCmd`" --version" 2>$null
        if ($v) { $result.dsh = ([string]($v | Select-Object -Last 1)).Trim() }
    }
    if ($result.dsh -eq 'unknown' -or -not $result.dsh) {
        if (Test-Path $FlagFile) {
            $line = (Get-Content $FlagFile -ErrorAction SilentlyContinue) -replace "`r", '' |
                    Where-Object { $_ -like 'dsh=*' } | Select-Object -First 1
            if ($line) { $result.dsh = $line.Substring(4).Trim() }
        }
    }

    if (Test-Path $FlagFile) {
        $line = (Get-Content $FlagFile -ErrorAction SilentlyContinue) -replace "`r", '' |
                Where-Object { $_ -like 'harness=*' } | Select-Object -First 1
        if ($line) { $result.harness = $line.Substring(8).Trim() }
    }
    if (-not $result.harness) {
        $hf = Join-Path $Root 'HARNESS_VERSION'
        if (Test-Path $hf) { $result.harness = ([IO.File]::ReadAllText($hf)).Trim() }
    }

    if (Test-Path $NodeExe) {
        $nv = & $NodeExe -v 2>$null
        if ($nv) { $result.node = ([string]$nv).Trim() }
    }
    return $result
}

# ---------------------------------------------------------------------------
# 上游最新版本：GitHub Release 与 npm dist-tags 两个源独立探测，失败互不拖累
# ---------------------------------------------------------------------------
function Get-LatestVersions {
    $result = @{ harness = ''; dsh = ''; errors = @() }

    try {
        $r = Invoke-RestMethod -Uri "https://api.github.com/repos/$Repo/releases/latest" -TimeoutSec 10
        if ($r.tag_name) { $result.harness = [string]$r.tag_name }
    } catch {
        $result.errors += "GitHub Release 检测失败: $($_.Exception.Message)"
    }

    if (Test-Path $NodeNpm) {
        $viewArgs = @('view', '@deepseek-ai/dsh', 'version', '--cache', $NpmCache)
        $v = & $NodeNpm @viewArgs --registry=https://registry.npmmirror.com 2>$null
        if (-not $v) {
            $v = & $NodeNpm @viewArgs 2>$null   # 中国源失败回退官方源
        }
        if ($v) { $result.dsh = ([string]($v | Select-Object -Last 1)).Trim() }
        else { $result.errors += 'npm 版本检测失败（npmmirror 与官方源均未返回）' }
    } else {
        $result.errors += '便携 Node 不存在，跳过 npm 版本检测'
    }
    return $result
}

# ---------------------------------------------------------------------------
# 更新报告（纯输出，三行结论）
# ---------------------------------------------------------------------------
function Show-UpdateReport($local, $latest) {
    Write-Host ''
    Write-Host '========== 版本检查 ==========' -ForegroundColor Cyan

    if ($latest.harness) {
        if ($local.harness -and ($local.harness -eq $latest.harness)) {
            Write-Ok ("程序版本: {0}（已是最新）" -f $local.harness)
        } elseif (-not $local.harness) {
            Write-WarnMsg ("程序版本: 未记录（旧版包）。最新完整包: {0}，建议从 Releases 页下载更新" -f $latest.harness)
        } else {
            Write-WarnMsg ("程序版本: {0} → 有新版本 {1}！请到 Releases 页下载完整包（数据可沿用）" -f $local.harness, $latest.harness)
        }
    } else {
        Write-WarnMsg '程序版本: 无法连接 GitHub，已跳过该项检查'
    }

    if ($latest.dsh) {
        if ($local.dsh -eq $latest.dsh) {
            Write-Ok ("dsh 版本 : {0}（已是最新）" -f $local.dsh)
        } elseif ($local.dsh -eq 'unknown') {
            Write-WarnMsg ("dsh 版本 : 未知（环境不完整）。上游最新: {0}" -f $latest.dsh)
        } else {
            Write-WarnMsg ("dsh 版本 : {0} → 上游有新版本 {1}（需本项目适配后才会在此提供升级）" -f $local.dsh, $latest.dsh)
        }
    } else {
        Write-WarnMsg 'dsh 版本 : 无法连接 npm 源，已跳过该项检查'
    }
    Write-Host '==============================' -ForegroundColor Cyan
}

# ---------------------------------------------------------------------------
# peer 一致性守门：PeerFix 中 dsh-* 的版本串必须与目标版本严格相等
# ---------------------------------------------------------------------------
function Test-PeerMatch([string]$target) {
    if (-not (Test-Path $SetupScript)) { Write-WarnMsg '找不到 setup-windows.ps1'; return $false }
    $ps1 = [IO.File]::ReadAllText($SetupScript)
    $m = [regex]::Match($ps1, '\$PeerFix\s*=\s*@\((.*?)\n\s*\)',
          [System.Text.RegularExpressions.RegexOptions]::Singleline)
    if (-not $m.Success) { Write-WarnMsg '无法从 setup-windows.ps1 解析 PeerFix 列表'; return $false }
    $peers = @([regex]::Matches($m.Groups[1].Value, "'([^']+)'") |
               ForEach-Object { $_.Groups[1].Value } | Where-Object { $_ -match '[@^]' })
    if ($peers.Count -lt 20) { Write-WarnMsg "peer 解析数量异常: $($peers.Count)"; return $false }

    $bad = @($peers | Where-Object { $_ -match '^@deepseek-ai/dsh-.*@\^(.+)$' -and $Matches[1] -ne $target })
    if ($bad.Count -gt 0) {
        Write-WarnMsg ("peer 列表与 dsh@$target 不一致，强制升级已阻断：")
        $bad | ForEach-Object { Write-Info "  - $_" }
        Write-Info '  上游 dsh 已发新版但本项目尚未适配。请等待本项目发布适配版 Release（菜单 [2] 会提示），'
        Write-Info '  或由维护者更新 setup-windows.ps1 的 PeerFix 版本串后再试。'
        return $false
    }
    return $true
}

# ---------------------------------------------------------------------------
# 升级后自检：①dsh --version == 目标  ②HTTP 探测 + 无模块缺失错误
# ---------------------------------------------------------------------------
function Test-DshInstall([string]$expect) {
    $v = & cmd /c "`"$DshCmd`" --version" 2>$null
    $got = if ($v) { ([string]($v | Select-Object -Last 1)).Trim() } else { '' }
    if ($got -ne $expect) {
        Write-WarnMsg "dsh --version 返回 '$got'，期望 '$expect'"
        return $false
    }
    Write-Ok "dsh --version = $got"

    # HTTP 探测：随机空闲口 3900-3999，避开用户可能正在跑的 3080
    $port = 0
    foreach ($p in (3900..3999)) {
        if (-not (Get-NetTCPConnection -LocalPort $p -ErrorAction SilentlyContinue)) { $port = $p; break }
    }
    if ($port -gt 0) {
        $env:DSH_HOME = Join-Path $Root 'data\dsh'
        $env:Path = "$NodeDir;$(Split-Path $DshCmd);$env:Path"
        $proc = $null
        try {
            $proc = Start-Process -FilePath $DshCmd `
                -ArgumentList 'web', "--port=$port", '--host', '127.0.0.1', '--no-open' `
                -PassThru -NoNewWindow `
                -RedirectStandardOutput $SelfCheckOut -RedirectStandardError $SelfCheckErr
            $ok = $false
            for ($i = 0; $i -lt 20; $i++) {
                Start-Sleep -Seconds 1
                if ($proc.HasExited) { break }
                try {
                    $r = Invoke-WebRequest "http://127.0.0.1:$port" -UseBasicParsing -TimeoutSec 2
                    if ($r.StatusCode -eq 200) { $ok = $true; break }
                } catch {}
            }
            if ($ok) { Write-Ok "启动自检通过（HTTP 200 @127.0.0.1:$port）" }
            else { Write-WarnMsg 'HTTP 探测未就绪（不阻断，已记录日志）' }
        } catch {
            Write-WarnMsg "HTTP 探测异常（不阻断）: $($_.Exception.Message)"
        } finally {
            if ($proc -and -not $proc.HasExited) {
                # dsh.cmd 是 cmd 垫片，必须杀整棵进程树，否则 node 子进程残留占端口
                & taskkill /PID $proc.Id /T /F 2>$null | Out-Null
            }
        }
        $badLog = @($SelfCheckOut, $SelfCheckErr) | ForEach-Object {
            if (Test-Path $_) { Select-String -Path $_ -Pattern 'ERR_MODULE_NOT_FOUND|Cannot find module' -Quiet }
        } | Where-Object { $_ }
        if ($badLog) {
            Write-WarnMsg '自检日志含模块缺失错误'
            return $false
        }
    } else {
        Write-WarnMsg '3900-3999 端口全被占用，跳过 HTTP 探测（不阻断）'
    }
    return $true
}

# ---------------------------------------------------------------------------
# 回滚：恢复 bak + 原样还原 flag，data/ 未受任何影响
# ---------------------------------------------------------------------------
function Invoke-Rollback([string]$reason) {
    Write-WarnMsg "升级失败：$reason"
    Write-Host '  正在回滚到旧版本 ...' -ForegroundColor Yellow
    $flagBakB64 = ''
    if (Test-Path $Journal) {
        foreach ($line in (Get-Content $Journal -ErrorAction SilentlyContinue) -replace "`r", '') {
            if ($line -like 'flag_bak_b64=*') { $flagBakB64 = $line.Substring(13) }
        }
    }
    if (Test-Path $BakDir) {
        if (Test-Path $AppDir) { Remove-Item $AppDir -Recurse -Force }
        Move-Item -Path $BakDir -Destination $AppDir -Force
        Write-Ok '已恢复旧版本运行环境'
    }
    if ($flagBakB64) {
        [IO.File]::WriteAllText($FlagFile, [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($flagBakB64)))
        Write-Ok '已还原 .ready.flag'
    }
    Remove-Item $Journal -Force -ErrorAction SilentlyContinue
    Write-Host '  data/（配置/会话/密钥）未受任何影响。' -ForegroundColor Green
    exit 5
}

function Set-JournalStep([string]$step) {
    $lines = (Get-Content $Journal -ErrorAction SilentlyContinue) -replace "`r", ''
    $new = @($lines | Where-Object { $_ -notlike 'step=*' }) + "step=$step"
    [IO.File]::WriteAllText($Journal, ($new -join "`r`n") + "`r`n")
}

function Get-DirSizeMB([string]$path) {
    if (-not (Test-Path $path)) { return 0 }
    $sum = (Get-ChildItem $path -Recurse -File -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum
    if (-not $sum) { return 0 }   # 空目录/无文件时 Measure-Object 返回 $null（PS 5.1 无 ?? 运算符）
    return [math]::Round($sum / 1MB, 0)
}

# ---------------------------------------------------------------------------
# 升级主流程：journal → rename 备份 → setup → 自检 → 清理 / 回滚
# ---------------------------------------------------------------------------
function Invoke-Upgrade([string]$target) {
    Write-Host ''
    Write-Host "===== 升级 dsh：当前 → $target =====" -ForegroundColor Cyan

    if (-not (Test-PeerMatch $target)) { exit 4 }
    if (-not (Test-Path $NodeExe))  { Write-WarnMsg '便携 Node 不存在，请先运行 setup'; exit 3 }
    if (-not (Test-Path $FlagFile)) { Write-WarnMsg '.ready.flag 不存在，请先运行 setup'; exit 3 }

    # 磁盘预检：备份与新版并存的峰值 ≈ 2×app；不足 1.2× 则中止（方案乙需用户显式选择）
    $appMB = Get-DirSizeMB $AppDir
    $drive = Get-PSDrive -Name ($Root.Substring(0, 1)) -ErrorAction SilentlyContinue
    if ($drive -and $appMB -gt 0) {
        $freeMB = [math]::Round($drive.Free / 1MB, 0)
        if ($freeMB -lt (1.2 * $appMB)) {
            Write-WarnMsg "磁盘剩余 ${freeMB}MB 不足以安全升级（需 ≥ $([math]::Round(1.2 * $appMB))MB 备份空间）"
            Write-Info '  可清理磁盘后重试，或删除 .cache/app 后重跑 setup（该方式失败无法自动回滚，慎用）。'
            exit 6
        }
    }

    # 检查是否有占用进程（rename 的主要失败模式）
    $busy = Get-Process node -ErrorAction SilentlyContinue
    if ($busy) { Write-WarnMsg '检测到 node 进程在运行，升级可能失败。建议先退出正在运行的 dsh。' }

    $local = Get-LocalVersions
    if ($local.dsh -eq 'unknown' -or -not $local.dsh) { Write-WarnMsg '当前 dsh 版本未知，无法安全升级'; exit 3 }
    if ($local.dsh -eq $target) { Write-Ok "当前已是 $target，无需升级"; exit 0 }

    # ① journal 先行（断电窗口最短的写操作）；flag 全文以 base64 存，规避 CRLF/多行破坏结构
    $flagText = if (Test-Path $FlagFile) { [IO.File]::ReadAllText($FlagFile) } else { '' }
    $journalLines = @(
        "old_dsh=$($local.dsh)",
        "new_dsh=$target",
        'step=journal',
        "flag_bak_b64=$([Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($flagText)))"
    )
    [IO.File]::WriteAllText($Journal, ($journalLines -join "`r`n") + "`r`n")

    # ② 备份：同盘同父目录 rename，O(1)；失败重试 3 次，仍失败则 app 无损中止
    $moved = $false
    for ($i = 1; $i -le 3; $i++) {
        try { Move-Item -Path $AppDir -Destination $BakDir -ErrorAction Stop; $moved = $true; break }
        catch { Write-WarnMsg "备份改名第 $i 次失败（可能被占用）: $($_.Exception.Message)"; Start-Sleep -Seconds 1 }
    }
    if (-not $moved) { Remove-Item $Journal -Force -ErrorAction SilentlyContinue; throw 'app 目录被占用，升级中止（原环境未受影响）' }
    Set-JournalStep 'backup-done'

    # ③ 重装：Node 已在 → [1/3] 自动跳过；app 已改名走 → [2/3][3/3] 必执行并重写 flag
    Write-Host '  安装新版本（依赖大部分命中本地缓存，通常 1-3 分钟）...' -ForegroundColor Yellow
    & powershell -NoProfile -ExecutionPolicy Bypass -File $SetupScript -DshVersion $target -Root $Root
    if ($LASTEXITCODE -ne 0) { Invoke-Rollback "setup 失败（退出码 $LASTEXITCODE）" }
    Set-JournalStep 'installed'

    # ④ 自检（失败 → 自动回滚）
    if (-not (Test-DshInstall $target)) { Invoke-Rollback '升级后自检未通过' }
    Set-JournalStep 'verified'

    # ⑤ 成功：先清 journal 再删 bak（删 bak 失败不影响正确性，残留由下次启动裁决清理）
    Remove-Item $Journal -Force -ErrorAction SilentlyContinue
    Remove-Item $BakDir -Recurse -Force -ErrorAction SilentlyContinue
    Write-Host ''
    Write-Host "UPGRADE_OK dsh=$target"
    exit 0
}

# ---------------------------------------------------------------------------
# 断电/中断残留裁决：以「app 能跑且版本与 flag 一致」为真值锚点，幂等无网络
# ---------------------------------------------------------------------------
function Resolve-UpgradeResidue {
    if (-not (Test-Path $BakDir)) { return }   # 无残留（最常见路径，直接返回）
    Write-WarnMsg '检测到上次升级的残留，正在裁决恢复 ...'
    $flagBakB64 = ''
    if (Test-Path $Journal) {
        foreach ($line in (Get-Content $Journal -ErrorAction SilentlyContinue) -replace "`r", '') {
            if ($line -like 'flag_bak_b64=*') { $flagBakB64 = $line.Substring(13) }
        }
    }

    if (-not (Test-Path $AppDir)) {
        # 时序②：rename 后 setup 前中断 —— app 缺失，bak 完好
        Move-Item -Path $BakDir -Destination $AppDir -Force
        Write-WarnMsg '已恢复旧版本环境（上次升级在安装阶段中断）。'
    }
    else {
        # 时序③④⑤：app 与 bak 并存 —— 以 app 可用性裁决
        $appVer = ''
        if (Test-Path $DshCmd) {
            $v = & cmd /c "`"$DshCmd`" --version" 2>$null
            if ($v) { $appVer = ([string]($v | Select-Object -Last 1)).Trim() }
        }
        $flagDsh = ''
        if (Test-Path $FlagFile) {
            $line = (Get-Content $FlagFile -ErrorAction SilentlyContinue) -replace "`r", '' |
                    Where-Object { $_ -like 'dsh=*' } | Select-Object -First 1
            if ($line) { $flagDsh = $line.Substring(4).Trim() }
        }
        if ($appVer -and $appVer -eq $flagDsh) {
            Remove-Item $BakDir -Recurse -Force -ErrorAction SilentlyContinue
            Write-WarnMsg "上次升级已完成但清理被打断，已保留新版本（$appVer）并清理备份。"
        } else {
            Remove-Item $AppDir -Recurse -Force -ErrorAction SilentlyContinue
            Move-Item -Path $BakDir -Destination $AppDir -Force
            if ($flagBakB64) {
                [IO.File]::WriteAllText($FlagFile, [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($flagBakB64)))
            }
            Write-WarnMsg '上次升级未完成（新环境不完整），已回滚到旧版本。'
        }
    }
    Remove-Item $Journal -Force -ErrorAction SilentlyContinue
}

# ---------------------------------------------------------------------------
# 主流程
# ---------------------------------------------------------------------------
if ($ReconcileOnly) { Resolve-UpgradeResidue; exit 0 }

$localVersions = Get-LocalVersions
$latestVersions = Get-LatestVersions
Show-UpdateReport $localVersions $latestVersions

if ($CheckOnly) {
    # 退出码：2=全网络失败 3=本地未知 1=有更新 0=已最新
    $netFail = ($latestVersions.errors.Count -gt 0) -and (-not $latestVersions.harness) -and (-not $latestVersions.dsh)
    if ($netFail) { exit 2 }
    if ($localVersions.dsh -eq 'unknown' -and -not $localVersions.harness) { exit 3 }
    $hasUpdate = ($latestVersions.harness -and $localVersions.harness -ne $latestVersions.harness) -or
                 ($latestVersions.dsh -and $localVersions.dsh -ne $latestVersions.dsh)
    exit ($(if ($hasUpdate) { 1 } else { 0 }))
}

if ($DshVersion) { Invoke-Upgrade $DshVersion }

# 无参数的交互式路径：仅当上游 dsh 有新版时询问强制升级（PeerFix 已适配才可能真正执行）
if ($latestVersions.dsh -and $localVersions.dsh -ne 'unknown' -and $localVersions.dsh -ne $latestVersions.dsh) {
    Write-Host ''
    $ans = Read-Host "  是否强制升级 dsh 到 $latestVersions.dsh？（升级前会做适配校验，失败自动回滚）[y/N]"
    if ($ans -match '^[yY]') { Invoke-Upgrade $latestVersions.dsh }
} elseif (-not $latestVersions.dsh -and -not $latestVersions.harness) {
    Write-Host ''
    Write-WarnMsg '网络不可用，无法检查更新。可稍后在菜单 [2] 重试。'
    exit 2
} else {
    Write-Host ''
    Write-Ok '一切正常。'
    exit 0
}
