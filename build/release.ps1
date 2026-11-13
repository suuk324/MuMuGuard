#Requires -Version 5.1
<#
  release.ps1
  一键出包：合并模块 → 编译 exe → 生成源码包 → 计算 SHA256

  用法：
    .\build\release.ps1                  # 用 VERSION 文件里的版本号
    .\build\release.ps1 -Version 1.0.1   # 指定版本并写回 VERSION
    .\build\release.ps1 -SkipTests       # 跳过单元测试（不推荐）
#>
param(
    [string]$Version,
    [switch]$SkipTests,
    [switch]$OpenFolder
)

$ErrorActionPreference = 'Stop'

$root = Split-Path $PSScriptRoot -Parent
$outDir = Join-Path $root '_build'
$distDir = Join-Path $root '_dist'

Write-Host ''
Write-Host '=== MuMuGuard 发布打包 ===' -ForegroundColor Cyan

# ---------- 1. 版本号 ----------
$verFile = Join-Path $root 'VERSION'
if ($Version) {
    Set-Content -Path $verFile -Value $Version -Encoding ASCII -NoNewline
} elseif (Test-Path $verFile) {
    $Version = (Get-Content $verFile -Raw).Trim()
} else {
    $Version = '1.0.0'
    Set-Content -Path $verFile -Value $Version -Encoding ASCII -NoNewline
}
Write-Host "版本: $Version"

# 同步到脚本内的兜底版本
$mainPath = Join-Path $root 'MuMuGuardApp.ps1'
$mainText = [System.IO.File]::ReadAllText($mainPath, [System.Text.Encoding]::UTF8)
$mainText = [regex]::Replace($mainText, "\`$script:appVersion = '[\d\.]+'", "`$script:appVersion = '$Version'")
[System.IO.File]::WriteAllText($mainPath, $mainText, (New-Object System.Text.UTF8Encoding $true))

# ---------- 2. 编码与语法 ----------
Write-Host ''
Write-Host '--- 检查编码与语法 ---' -ForegroundColor Cyan
$chk = Join-Path $root 'Check-BOM.ps1'
if (Test-Path $chk) {
    & powershell -NoProfile -ExecutionPolicy Bypass -File $chk | Out-Null
    if ($LASTEXITCODE -ne 0) { throw '编码或语法检查未通过' }
    Write-Host '  OK'
}

# ---------- 3. 单元测试 ----------
if (-not $SkipTests) {
    Write-Host ''
    Write-Host '--- 单元测试 ---' -ForegroundColor Cyan
    $tests = Join-Path $root 'tests\Run-Tests.ps1'
    if (Test-Path $tests) {
        $out = & powershell -NoProfile -ExecutionPolicy Bypass -File $tests
        $out | Select-Object -Last 1 | ForEach-Object { Write-Host "  $_" }
        if ($LASTEXITCODE -ne 0) { throw '单元测试未通过' }
    }
}

# ---------- 4. 合并 ----------
Write-Host ''
Write-Host '--- 合并模块 ---' -ForegroundColor Cyan
$bundle = & (Join-Path $root 'build\bundle.ps1') -OutDir $outDir
Write-Host "  $bundle"

# ---------- 5. 编译 exe ----------
Write-Host ''
Write-Host '--- 编译 exe ---' -ForegroundColor Cyan
if (-not (Get-Module -ListAvailable -Name ps2exe)) {
    Write-Host '  安装 ps2exe…'
    Install-Module ps2exe -Scope CurrentUser -Force -AllowClobber -ErrorAction Stop
}
Import-Module ps2exe -Force

if (-not (Test-Path $distDir)) { New-Item -ItemType Directory -Path $distDir -Force | Out-Null }
$exeName = "MuMuGuard_v$Version.exe"
$exePath = Join-Path $distDir $exeName

$icon = Join-Path $root 'MuMuGuard.ico'
$args = @{
    InputFile        = $bundle
    OutputFile       = $exePath
    NoConsole        = $true
    STA              = $true
    RequireAdmin     = $false
    Title            = 'MuMuGuard'
    Description      = 'MuMu 模拟器看护面板'
    Product          = 'MuMuGuard'
    Company          = 'Titen'
    Copyright        = "(c) $(Get-Date -Format yyyy) Titen"
    Version          = $(if ($Version -match '^\d+\.\d+\.\d+$') { $Version } else { '1.0.0.0' })
}
if (Test-Path $icon) { $args['IconFile'] = $icon }
Invoke-PS2EXE @args

if (-not (Test-Path $exePath)) { throw 'exe 未生成' }
$exeSize = [math]::Round((Get-Item $exePath).Length / 1KB, 1)
Write-Host "  $exeName ($exeSize KB)"

# ---------- 6. 源码包 ----------
Write-Host ''
Write-Host '--- 打包源码 ---' -ForegroundColor Cyan
$srcZip = Join-Path $distDir "MuMuGuard_源码_v$Version.zip"
if (Test-Path $srcZip) { Remove-Item $srcZip -Force }

$stage = Join-Path $outDir 'srcstage'
if (Test-Path $stage) { Remove-Item $stage -Recurse -Force }
New-Item -ItemType Directory -Path $stage -Force | Out-Null

$include = @('MuMuGuardApp.ps1', 'Waker.ps1', 'Restart-Instance.ps1', 'Update-Helper.ps1',
             'Check-BOM.ps1', '启动面板.vbs', 'run_guard.vbs', 'MuMuGuard.ico', 'blank.ico',
             'README.md', 'LICENSE', 'VERSION')
foreach ($f in $include) {
    $p = Join-Path $root $f
    if (Test-Path $p) { Copy-Item $p $stage -Force }
}
foreach ($d in @('lib', 'tests', 'build')) {
    $p = Join-Path $root $d
    if (Test-Path $p) { Copy-Item $p (Join-Path $stage $d) -Recurse -Force }
}
Compress-Archive -Path (Join-Path $stage '*') -DestinationPath $srcZip -Force
Write-Host "  $(Split-Path $srcZip -Leaf) ($([math]::Round((Get-Item $srcZip).Length/1KB,1)) KB)"

# ---------- 7. SHA256 ----------
Write-Host ''
Write-Host '--- 校验文件 ---' -ForegroundColor Cyan
$hash = (Get-FileHash $exePath -Algorithm SHA256).Hash.ToLower()
$shaFile = Join-Path $distDir "$exeName.sha256"
Set-Content -Path $shaFile -Value ("{0}  {1}" -f $hash, $exeName) -Encoding ASCII
Write-Host "  $hash"

# ---------- 8. 汇总 ----------
Write-Host ''
Write-Host '=== 完成 ===' -ForegroundColor Green
Get-ChildItem $distDir | Select-Object Name, @{n = '大小'; e = { '{0:N1} KB' -f ($_.Length / 1KB) } } |
    Format-Table -AutoSize | Out-String | Write-Host

Write-Host '下一步：把 exe 和 .sha256 上传到 GitHub Release' -ForegroundColor Yellow
Write-Host ("  标签: v$Version") -ForegroundColor Yellow
Write-Host ''

if ($OpenFolder) { Start-Process explorer.exe -ArgumentList $distDir }