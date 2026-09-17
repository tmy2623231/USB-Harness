# =============================================================================
# setup-windows.ps1 — USB Harness 首次配置（Windows）
# 职责：下载便携 Node.js → 安装 @deepseek-ai/dsh → 应用品牌补丁 → 初始化数据目录
# 用法：powershell -ExecutionPolicy Bypass -File .\scripts\setup-windows.ps1 [-Force]
#       （launch.bat 首次运行时会自动调用本脚本）
# =============================================================================
[CmdletBinding()]
param(
    [string]$NodeVersion = '22.23.2',           # 锁定 22.x LTS（满足 dsh ^22.19 || >=24）
    [string]$DshVersion  = '0.1.5-rc.2',        # 锁定 dsh 版本（补丁基线必须与此一致）
    [switch]$Force,                             # 强制重装
    [string]$Root        = ''                   # 项目根目录；留空则按 $PSScriptRoot 推断
)

# 注意：param 默认值里不能用 $PSScriptRoot（子进程 -File 调用时为空串会报错），
# 必须在脚本体内解析。
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if (-not $Root) { $Root = Split-Path -Parent $PSScriptRoot }

$Arch         = 'windows-x64'   # 本地运行时目录名（.cache\runtimes\windows-x64\node）
$DownloadArch = 'win-x64'       # nodejs.org / npmmirror 下载文件名用的是 win-x64
$NodeDir     = Join-Path $Root ".cache\runtimes\$Arch\node"
$NodeExe     = Join-Path $NodeDir 'node.exe'
$NodeNpm     = Join-Path $NodeDir 'npm.cmd'
$AppPrefix   = Join-Path $Root '.cache\app'
$DshCmd      = Join-Path $AppPrefix 'node_modules\.bin\dsh.cmd'
$DshHome     = Join-Path $Root 'data\dsh'
$LogDir      = Join-Path $Root 'data\logs'
$ReadyFlag   = Join-Path $Root '.ready.flag'
$NpmCache    = Join-Path $Root '.cache\npm-cache'   # npm 缓存随盘，零宿主机污染
$DownloadsDir = Join-Path $Root '.cache\downloads'   # U 盘预置安装包（离线可用）
$NodeZipName = "node-v$NodeVersion-$DownloadArch.zip"
$NodeZipLocal = Join-Path $DownloadsDir $NodeZipName

New-Item -ItemType Directory -Force -Path $NodeDir, $AppPrefix, $DshHome, $LogDir, $NpmCache, $DownloadsDir | Out-Null

# ---------------------------------------------------------------------------
# 下载：优先 curl.exe（进度好），失败回退 Invoke-WebRequest
# ---------------------------------------------------------------------------
function Invoke-Download {
    param([string]$Url, [string]$OutFile)
    $curl = Get-Command curl.exe -ErrorAction SilentlyContinue
    if ($curl) {
        & curl.exe -L --fail --retry 3 -o $OutFile $Url
        if ($LASTEXITCODE -ne 0) { throw "curl 下载失败: $Url" }
    } else {
        Invoke-WebRequest -Uri $Url -OutFile $OutFile -UseBasicParsing
    }
}

# ---------------------------------------------------------------------------
# npm 安装：优先中国镜像（npmmirror），失败回退官方源
# ---------------------------------------------------------------------------
function Invoke-NpmInstall {
    param([string[]]$ArgsList)
    & $NodeNpm install --prefix $AppPrefix @ArgsList --no-audit --no-fund --fetch-retries=5 --legacy-peer-deps --cache $NpmCache --registry=https://registry.npmmirror.com
    if ($LASTEXITCODE -ne 0) {
        Write-Warning '      中国镜像失败，回退官方 npm 源 ...'
        & $NodeNpm install --prefix $AppPrefix @ArgsList --no-audit --no-fund --fetch-retries=5 --legacy-peer-deps --cache $NpmCache
        if ($LASTEXITCODE -ne 0) { throw "npm 安装失败，退出码 $LASTEXITCODE" }
    }
}

Write-Host ''
Write-Host '============================================' -ForegroundColor Cyan
Write-Host '   USB Harness 首次配置' -ForegroundColor Cyan
Write-Host '============================================' -ForegroundColor Cyan
Write-Host "项目根目录 : $Root"
Write-Host "便携 Node   : $NodeVersion"
Write-Host "dsh 版本    : $DshVersion"
Write-Host ''

# ---------------------------------------------------------------------------
# 1) 便携 Node.js
# ---------------------------------------------------------------------------
if ((Test-Path $NodeExe) -and -not $Force) {
    Write-Host '[1/3] 便携 Node 已存在，跳过（如需重装加 -Force）。' -ForegroundColor Green
} else {
    Write-Host "[1/3] 准备便携 Node.js $NodeVersion ($Arch) ..."
    # 优先使用 U 盘预置包（离线安装，中国网络无需联网）
    if (Test-Path $NodeZipLocal) {
        Write-Host "      使用 U 盘预置安装包: $NodeZipLocal" -ForegroundColor Green
    } else {
        Write-Host '      下载便携 Node.js（中国镜像 npmmirror 优先）...'
        $urls = @(
            "https://npmmirror.com/mirrors/node/v$NodeVersion/$NodeZipName",
            "https://nodejs.org/dist/v$NodeVersion/$NodeZipName"
        )
        $downloaded = $false
        foreach ($u in $urls) {
            try {
                Invoke-Download -Url $u -OutFile $NodeZipLocal
                $downloaded = $true
                break
            } catch {
                Write-Warning "      下载失败，尝试下一个源 ..."
            }
        }
        if (-not $downloaded) {
            throw "Node.js 下载失败。可手动下载 $NodeZipName 放到 .cache\downloads\ 后重试（离线安装）。"
        }
    }
    $zipFile = $NodeZipLocal

    Write-Host "      解压到 $NodeDir ..."
    $extractTmp = Join-Path $Root '.cache\runtimes\_extract'
    if (Test-Path $extractTmp) { Remove-Item -Recurse -Force $extractTmp }
    Expand-Archive -Path $zipFile -DestinationPath $extractTmp -Force
    $inner = Join-Path $extractTmp "node-v$NodeVersion-$DownloadArch"
    if (Test-Path $NodeDir) { Remove-Item -Recurse -Force $NodeDir }
    Move-Item -Path $inner -Destination $NodeDir
    Remove-Item -Recurse -Force $extractTmp -ErrorAction SilentlyContinue
    Write-Host "      便携 Node 就绪: $NodeExe" -ForegroundColor Green
    & $NodeExe -v
}

# ---------------------------------------------------------------------------
# 2) 安装 @deepseek-ai/dsh
# ---------------------------------------------------------------------------
if ((Test-Path $DshCmd) -and -not $Force) {
    Write-Host '[2/3] dsh 已安装，跳过（如需重装加 -Force）。' -ForegroundColor Green
} else {
    Write-Host "[2/3] 用便携 npm 安装 @deepseek-ai/dsh@$DshVersion ..." -ForegroundColor Yellow
    Write-Host '      这会下载完整依赖树，首次约 3-8 分钟，请耐心等待。'
    Write-Host '      使用 --legacy-peer-deps 规避 npm 解析卡死；中国镜像（npmmirror）优先。'
    $env:Path = "$NodeDir;$env:Path"
    Invoke-NpmInstall -ArgsList @("@deepseek-ai/dsh@$DshVersion")
    Write-Host "      dsh 安装完成: $DshCmd" -ForegroundColor Green

    # 已知坑位：多个 dsh 子包把彼此声明为 peerDependencies，主包 bundle 未包含，
    # --legacy-peer-deps 会跳过它们，导致启动报 ERR_MODULE_NOT_FOUND。这里显式补齐。
    #
    # 清单来源（权威方法，勿手工推算）：
    #   python .patch-tools/refscan-registry.py --dsh-version <ver> --emit-ps1
    # 该方法遍历 npm 注册表依赖闭包，取全体 peerDependencies 的并集，
    # 再减去主包 dependencies 已自动覆盖的部分。
    # 切勿改用「扫描已安装树找解析不到的 import」的老办法——那是循环论证：
    # 没装上的包本就不在安装树里，扫不到就会误报「缺失 0 个」。
    Write-Host '      补齐 dsh 缺失的 peer 依赖包（已知 71 个）...' -ForegroundColor Yellow
    $peerVer = $DshVersion
    $PeerFix = @(
        # --- 仅以 peerDependencies 声明、主包未纳入依赖树的子包（版本跟随 dsh） ---
        "@deepseek-ai/dsh-agent@$peerVer", "@deepseek-ai/dsh-agent-default-model@$peerVer",
        "@deepseek-ai/dsh-agent-presets@$peerVer", "@deepseek-ai/dsh-anonymous-user-id@$peerVer",
        "@deepseek-ai/dsh-api-gateway@$peerVer", "@deepseek-ai/dsh-atomic-write@$peerVer",
        "@deepseek-ai/dsh-attachment@$peerVer", "@deepseek-ai/dsh-authorization@$peerVer",
        "@deepseek-ai/dsh-bash-local@$peerVer", "@deepseek-ai/dsh-brand@$peerVer",
        "@deepseek-ai/dsh-client-connection@$peerVer", "@deepseek-ai/dsh-client-file-upload@$peerVer",
        "@deepseek-ai/dsh-client-ui-directory-picker-browse@$peerVer", "@deepseek-ai/dsh-client-ui-directory-picker-native@$peerVer",
        "@deepseek-ai/dsh-code-runtime@$peerVer", "@deepseek-ai/dsh-command-feedback@$peerVer",
        "@deepseek-ai/dsh-commands@$peerVer", "@deepseek-ai/dsh-compaction@$peerVer",
        "@deepseek-ai/dsh-cordis-host-runner@$peerVer", "@deepseek-ai/dsh-credentials@$peerVer",
        "@deepseek-ai/dsh-deepseek-llm-api-extensions@$peerVer", "@deepseek-ai/dsh-file-reference@$peerVer",
        "@deepseek-ai/dsh-fs@$peerVer", "@deepseek-ai/dsh-hook-protocol@$peerVer",
        "@deepseek-ai/dsh-host-directory-picker@$peerVer", "@deepseek-ai/dsh-host-directory-picker-browse@$peerVer",
        "@deepseek-ai/dsh-host-directory-picker-native@$peerVer", "@deepseek-ai/dsh-host-webserver@$peerVer",
        "@deepseek-ai/dsh-invariants@$peerVer", "@deepseek-ai/dsh-jobs@$peerVer",
        "@deepseek-ai/dsh-llm@$peerVer", "@deepseek-ai/dsh-llm-deepseek@$peerVer",
        "@deepseek-ai/dsh-llm-retry@$peerVer", "@deepseek-ai/dsh-message-feedback@$peerVer",
        "@deepseek-ai/dsh-native-command@$peerVer", "@deepseek-ai/dsh-output-retention@$peerVer",
        "@deepseek-ai/dsh-permission-presets@$peerVer", "@deepseek-ai/dsh-sandbox@$peerVer",
        "@deepseek-ai/dsh-sandbox-policy@$peerVer", "@deepseek-ai/dsh-scope@$peerVer",
        "@deepseek-ai/dsh-sdk-protocol@$peerVer", "@deepseek-ai/dsh-session@$peerVer",
        "@deepseek-ai/dsh-session-persistence@$peerVer", "@deepseek-ai/dsh-session-projection-cache@$peerVer",
        "@deepseek-ai/dsh-session-query@$peerVer", "@deepseek-ai/dsh-session-telemetry@$peerVer",
        "@deepseek-ai/dsh-session-title@$peerVer", "@deepseek-ai/dsh-session-title-llm@$peerVer",
        "@deepseek-ai/dsh-settings@$peerVer", "@deepseek-ai/dsh-shell@$peerVer",
        "@deepseek-ai/dsh-shell-env@$peerVer", "@deepseek-ai/dsh-spill@$peerVer",
        "@deepseek-ai/dsh-storage@$peerVer", "@deepseek-ai/dsh-storage-domain@$peerVer",
        "@deepseek-ai/dsh-subagent@$peerVer", "@deepseek-ai/dsh-subagent-in-process-driver@$peerVer",
        "@deepseek-ai/dsh-subprocess@$peerVer", "@deepseek-ai/dsh-system-prompt@$peerVer",
        "@deepseek-ai/dsh-timeout@$peerVer", "@deepseek-ai/dsh-tools@$peerVer",
        "@deepseek-ai/dsh-typert-protocol@$peerVer", "@deepseek-ai/dsh-typert-registry@$peerVer",
        "@deepseek-ai/dsh-user-approval@$peerVer", "@deepseek-ai/dsh-user-questions@$peerVer",
        "@deepseek-ai/dsh-util-time@$peerVer", "@deepseek-ai/dsh-util-values@$peerVer",
        "@deepseek-ai/dsh-util-workspace-path@$peerVer", "@deepseek-ai/dsh-web@$peerVer",
        "@deepseek-ai/dsh-workflow@$peerVer", "@deepseek-ai/dsh-workspace@$peerVer",
        # --- 主包依赖树里已存在，但版本号独立于 dsh 的第三方包 ---
        # 注意 cordis-plugin-group 版本是 1.0.x，与 dsh 版本无关；写成 @$peerVer 会 ETARGET
        '@deepseek-ai/cordis-plugin-group@^1.0.2', '@cfworker/json-schema@^4.1.1',
        # react 必须锁 18.x：dsh-web-frontend 依赖 react@^18.2.0，用 latest 会拉到 19.x（跨大版本不兼容）
        'react@^18.3.1', 'react-dom@^18.3.1',
        'bufferutil@^4.0.1', 'utf-8-validate@^5.0.2',
        '@types/react@^18.3.12'
    )
    Invoke-NpmInstall -ArgsList $PeerFix
    Write-Host '      peer 依赖补齐完成。' -ForegroundColor Green
}

# ---------------------------------------------------------------------------
# 3) 应用品牌补丁（去 DeepSeek 化） + 就绪标记
# ---------------------------------------------------------------------------
$brandSrc = Join-Path $Root 'brand-patch\@deepseek-ai'
$brandDst = Join-Path $AppPrefix 'node_modules\@deepseek-ai'
if (Test-Path $brandSrc) {
    Write-Host '[3/3] 应用 USB Harness 品牌补丁（去 DeepSeek 化）...' -ForegroundColor Yellow
    if (-not (Test-Path $brandDst)) { New-Item -ItemType Directory -Force -Path $brandDst | Out-Null }
    Copy-Item (Join-Path $brandSrc '*') $brandDst -Recurse -Force
    Write-Host '      品牌补丁已应用。' -ForegroundColor Green
} else {
    Write-Warning '未找到 brand-patch，跳过品牌补丁。'
}

New-Item -ItemType Directory -Force -Path $DshHome | Out-Null

# 就绪标记：harness 行仅当包根存在 HARNESS_VERSION（CI 打包写入）时追加，向后兼容旧三行格式；
# 临时文件 + Move-Item 原子写（替代 Out-File 直写，避免写一半断电留半行）
$flagLines = @("node=$NodeVersion", "dsh=$DshVersion")
$harnessFile = Join-Path $Root 'HARNESS_VERSION'
if (Test-Path $harnessFile) {
    $flagLines += "harness=$([IO.File]::ReadAllText($harnessFile).Trim())"
}
$flagLines += "created=$(Get-Date -Format 'o')"
$tmpFlag = "$ReadyFlag.tmp"
[IO.File]::WriteAllText($tmpFlag, ($flagLines -join "`r`n") + "`r`n")
Move-Item -Path $tmpFlag -Destination $ReadyFlag -Force

Write-Host ''
Write-Host '============================================' -ForegroundColor Green
Write-Host '   配置完成！' -ForegroundColor Green
Write-Host '============================================' -ForegroundColor Green
Write-Host "下一步：双击 launch.bat 启动。"
Write-Host "DSH_HOME 将指向: $DshHome"
Write-Host ''
