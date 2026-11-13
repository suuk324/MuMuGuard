#Requires -Version 5.1
<#
  Update-Helper.ps1
  更新助手：等待主程序退出 → 备份 → 替换 → 重启 → 失败回滚

  由主程序在下载完成后启动，用户不需要直接运行。
#>
param(
    [Parameter(Mandatory = $true)][string]$TargetPath,
    [Parameter(Mandatory = $true)][string]$NewPath,
    [Parameter(Mandatory = $true)][int]$ProcessId,
    [switch]$Restart
)

$ErrorActionPreference = 'Continue'

$root = $PSScriptRoot
$logFile = Join-Path $root 'logs\update.log'
if (-not (Test-Path (Join-Path $root 'logs'))) {
    New-Item -ItemType Directory -Path (Join-Path $root 'logs') -Force | Out-Null
}

function Write-Log([string]$msg) {
    try {
        Add-Content -Path $logFile -Value ('[{0:yyyy-MM-dd HH:mm:ss}] {1}' -f (Get-Date), $msg) -Encoding UTF8
    } catch { }
}

Write-Log "更新助手启动：目标=$TargetPath 新文件=$NewPath 等待PID=$ProcessId"

# 1) 等待主程序退出（最多 60 秒）
$waited = 0
while ($waited -lt 60) {
    $p = Get-Process -Id $ProcessId -ErrorAction SilentlyContinue
    if (-not $p) { break }
    Start-Sleep -Milliseconds 500
    $waited++
}
Start-Sleep -Milliseconds 500

if (-not (Test-Path $NewPath)) {
    Write-Log "新文件不存在，放弃：$NewPath"
    exit 1
}

# 2) 备份旧文件
$bak = "$TargetPath.bak"
try {
    if (Test-Path $bak) { Remove-Item $bak -Force -ErrorAction SilentlyContinue }
    Copy-Item $TargetPath $bak -Force -ErrorAction Stop
    Write-Log "已备份旧版本"
} catch {
    Write-Log "备份失败：$($_.Exception.Message)"
}

# 3) 替换
$replaced = $false
for ($i = 0; $i -lt 20; $i++) {
    try {
        Copy-Item $NewPath $TargetPath -Force -ErrorAction Stop
        $replaced = $true
        break
    } catch {
        Start-Sleep -Milliseconds 500
    }
}

if (-not $replaced) {
    Write-Log "替换失败，尝试回滚"
    if (Test-Path $bak) {
        try { Copy-Item $bak $TargetPath -Force -ErrorAction Stop } catch { }
    }
    exit 1
}
Write-Log '替换完成'

# 4) 重启
if ($Restart) {
    Start-Sleep -Milliseconds 400
    try {
        Start-Process -FilePath $TargetPath -ErrorAction Stop
        Write-Log '已重新启动新版本'
    } catch {
        Write-Log "启动失败：$($_.Exception.Message)，尝试回滚"
        if (Test-Path $bak) {
            try {
                Copy-Item $bak $TargetPath -Force -ErrorAction Stop
                Start-Process -FilePath $TargetPath
                Write-Log '已回滚并启动旧版本'
            } catch { }
        }
        exit 1
    }
}

# 5) 清理
Start-Sleep -Seconds 2
try { Remove-Item $NewPath -Force -ErrorAction SilentlyContinue } catch { }
Write-Log '更新流程结束'