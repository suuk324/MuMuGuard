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
    [switch]$Restart,
    [string]$NewVersion = ''
)

$root = Split-Path $TargetPath -Parent
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

# 1) 等待主程序退出；超过 20 秒仍未退出就强制结束（用户已确认更新，避免卡住）
$waited = 0
# 没有有效 PID（比如手动调用）就跳过等待
while ($ProcessId -gt 0 -and $waited -lt 40) {
    $p = Get-Process -Id $ProcessId -ErrorAction SilentlyContinue
    if (-not $p) { break }
    Start-Sleep -Milliseconds 500
    $waited++
}

$still = Get-Process -Id $ProcessId -ErrorAction SilentlyContinue
if ($still) {
    Write-Log '主程序未自行退出，强制结束'
    try { Stop-Process -Id $ProcessId -Force -ErrorAction Stop } catch {
        Write-Log "强制结束失败：$($_.Exception.Message)"
    }
    # 等文件句柄释放
    for ($i = 0; $i -lt 20; $i++) {
        if (-not (Get-Process -Id $ProcessId -ErrorAction SilentlyContinue)) { break }
        Start-Sleep -Milliseconds 300
    }
}
Start-Sleep -Milliseconds 600
Write-Log '主程序已退出，开始替换'

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

# 写入新版本号，否则界面会一直显示旧版本、反复提示更新
if ($NewVersion) {
    try {
        Set-Content -Path (Join-Path $root 'VERSION') -Value $NewVersion -Encoding UTF8
        Write-Log ('已写入版本号 ' + $NewVersion)
    } catch { Write-Log ('写版本号失败：' + $_.Exception.Message) }
}

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
