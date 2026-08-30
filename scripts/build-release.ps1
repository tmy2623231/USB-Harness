# =============================================================================
# build-release.ps1 — 构建「含运行时」的完整发布包
# 职责：复制源文件 → 安装便携 Node + dsh + 品牌补丁 → 清理 → 压缩为 zip
# 用法：powershell -ExecutionPolicy Bypass -File .\scripts\build-release.ps1
#       powershell -ExecutionPolicy Bypass -File .\scripts\build-release.ps1 -OutFile "D:\out.zip"
# 产物：USB-Harness-with-runtime.zip（可直接上传 GitHub Releases）
# =============================================================================
[CmdletBinding()]
param(
    [string]$OutFile    = 'USB-Harness-with-runtime.zip',
    [string]$WorkDir    = '',                       # 构建临时目录；留空用系统临时目录
    [switch]$KeepWorkDir                            # 保留构建目录便于排查
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$RepoRoot = Split-Path -Parent $PSScriptRoot

if (-not $WorkDir) {
    $WorkDir = Join-Path ([System.IO.Path]::GetTempPath()) ("usb-harness-build-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
}
$BuildRoot = Join-Path $WorkDir 'USB-Harness'

Write-Host ''
Write-Host '============================================' -ForegroundColor Cyan
Write-Host '   USB Harness 发布包构建' -ForegroundColor Cyan
Write-Host '============================================' -ForegroundColor Cyan
Write-Host "构建目录 : $BuildRoot"
Write-Host "输出文件 : $OutFile"
Write-Host ''

# ---------------------------------------------------------------------------
# 1) 复制源文件（排除 .git、.cache、data）
# ---------------------------------------------------------------------------
Write-Host '[1/4] 复制源文件 ...' -ForegroundColor Yellow
New-Item -ItemType Directory -Force -Path $BuildRoot | Out-Null
$copyItems = @('launch.bat', 'launch.sh', 'LICENSE', 'README.md', 'CHANGELOG.md',
               'brand-patch', 'config', 'docs', 'scripts', '.gitattributes', '.gitignore')
foreach ($item in $copyItems) {
    $src = Join-Path $RepoRoot $item
    if (Test-Path $src) {
        Copy-Item $src $BuildRoot -Recurse -Force
        Write-Host "      + $item"
    }
}

# ---------------------------------------------------------------------------
# 2) 安装运行时（便携 Node + dsh + 品牌补丁）
# ---------------------------------------------------------------------------
Write-Host '[2/4] 安装便携运行时（Node + dsh + 品牌补丁）...' -ForegroundColor Yellow
Write-Host '      首次约 3-10 分钟，取决于网络与 npm 依赖树解析速度。'
Push-Location $BuildRoot
try {
    & (Join-Path $BuildRoot 'scripts\setup-windows.ps1') -Force
    if ($LASTEXITCODE -ne 0) { throw "setup 失败，退出码 $LASTEXITCODE" }
} finally {
    Pop-Location
}

# ---------------------------------------------------------------------------
# 3) 清理：删除运行期产物，避免把本机数据打进包
# ---------------------------------------------------------------------------
Write-Host '[3/4] 清理运行期产物 ...' -ForegroundColor Yellow
$cleanList = @(
    (Join-Path $BuildRoot 'data\dsh\.credentials.yaml'),   # 凭据：绝不能入包
    (Join-Path $BuildRoot 'data\dsh\settings.yaml'),       # 本机配置
    (Join-Path $BuildRoot 'data\dsh\sessions'),
    (Join-Path $BuildRoot 'data\dsh\storages'),
    (Join-Path $BuildRoot 'data\dsh\profiles'),
    (Join-Path $BuildRoot 'data\logs'),
    (Join-Path $BuildRoot '.cache\npm-cache'),             # npm 缓存（体积大户，非必需）
    (Join-Path $BuildRoot '.cache\runtimes\_extract')
)
foreach ($p in $cleanList) {
    if (Test-Path $p) {
        Remove-Item $p -Recurse -Force -ErrorAction SilentlyContinue
        Write-Host "      - $(Split-Path $p -Leaf)"
    }
}
# 保留空的 data/dsh 与 data/logs 目录结构
New-Item -ItemType Directory -Force -Path (Join-Path $BuildRoot 'data\dsh'), (Join-Path $BuildRoot 'data\logs') | Out-Null

# ---------------------------------------------------------------------------
# 4) 压缩
# ---------------------------------------------------------------------------
Write-Host '[4/4] 压缩为 zip ...' -ForegroundColor Yellow
$zipPath = if ([System.IO.Path]::IsPathRooted($OutFile)) { $OutFile } else { Join-Path $RepoRoot $OutFile }
if (Test-Path $zipPath) { Remove-Item $zipPath -Force }
Compress-Archive -Path (Join-Path $BuildRoot '*') -DestinationPath $zipPath -CompressionLevel Optimal -Force

$sizeMB = [math]::Round((Get-Item $zipPath).Length / 1MB, 1)
Write-Host ''
Write-Host '============================================' -ForegroundColor Green
Write-Host '   构建完成！' -ForegroundColor Green
Write-Host '============================================' -ForegroundColor Green
Write-Host "产物: $zipPath"
Write-Host "大小: $sizeMB MB"
Write-Host ''
Write-Host '上传前建议核对：'
Write-Host '  1. 包内 .ready.flag 记录的 dsh 版本与 brand-patch 基线一致'
Write-Host '  2. data/dsh 为空（不含任何凭据与本机配置）'
Write-Host '  3. 解压后双击 launch.bat 能正常启动'
Write-Host ''

if (-not $KeepWorkDir) {
    Remove-Item $WorkDir -Recurse -Force -ErrorAction SilentlyContinue
    Write-Host "已清理构建目录: $WorkDir"
} else {
    Write-Host "保留构建目录: $WorkDir"
}
