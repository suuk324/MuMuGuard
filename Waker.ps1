#Requires -Version 5.1
<#
  Waker.ps1
  独立后台唤醒进程。读取 sleep.json，到时间点自动开机并启动紫孔雀。
  面板关闭后仍可工作；没有待唤醒任务时自动退出。
#>
param(
    [string]$SleepFile,
    [string]$LogFile
)

$ErrorActionPreference = 'Continue'

if (-not $SleepFile) { $SleepFile = Join-Path $PSScriptRoot 'sleep.json' }
if (-not $LogFile)   { $LogFile   = Join-Path $PSScriptRoot 'logs\waker.log' }

# ---- 从 config.json 读取路径与包名（支持用户自定义）----
$cfgPath = Join-Path $PSScriptRoot 'config.json'
$cfg = @{}
if (Test-Path $cfgPath) {
    try {
        $j = Get-Content $cfgPath -Raw -Encoding UTF8 | ConvertFrom-Json
        foreach ($p in $j.PSObject.Properties) { $cfg[$p.Name] = $p.Value }
    } catch { }
}

$MuMuRoot = if ($cfg.MuMuRoot) { [string]$cfg.MuMuRoot } else { 'D:\Program Files\Netease\MuMu' }
$AdbExe   = Join-Path $MuMuRoot 'nx_device\15.0\shell\adb.exe'
$MuMuMgr  = Join-Path $MuMuRoot 'nx_main\MuMuManager.exe'
$PkgScript = if ($cfg.PkgScript) { [string]$cfg.PkgScript } else { 'com.coc.zkqcode' }

$CsvDir = Join-Path $PSScriptRoot 'logs'

function Write-Log([string]$msg) {
    $line = '[{0:yyyy-MM-dd HH:mm:ss}] {1}' -f (Get-Date), $msg
    try {
        $dir = Split-Path $LogFile -Parent
        if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
        Add-Content -Path $LogFile -Value $line -Encoding UTF8
    } catch { }
}

# 写入与面板共用的事件日志
function Write-Event([string]$action, [string]$instance, [string]$detail) {
    try {
        if (-not (Test-Path $CsvDir)) { New-Item -ItemType Directory -Path $CsvDir -Force | Out-Null }
        $f = Join-Path $CsvDir ('guard-{0:yyyyMMdd}.csv' -f (Get-Date))
        $new = -not (Test-Path $f)
        $line = '{0},{1},{2},{3}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $action, $instance, ($detail -replace ',', ';')
        Add-Content -Path $f -Value $line -Encoding UTF8
        if ($new) {
            # 补表头
            $content = Get-Content $f -Raw -Encoding UTF8
            Set-Content -Path $f -Value ("Time,Action,Instance,Detail`r`n" + $content) -Encoding UTF8
        }
    } catch { }
}

# 单实例：避免多个 waker 同时跑
$mutex = New-Object System.Threading.Mutex($false, 'Local\MuMuGuardWaker')
if (-not $mutex.WaitOne(0)) { exit 0 }

function Get-SleepList {
    try {
        if (-not (Test-Path $SleepFile)) { return @() }
        $raw = Get-Content $SleepFile -Raw -Encoding UTF8
        if (-not $raw -or $raw.Trim() -eq '') { return @() }
        return @(@($raw | ConvertFrom-Json) | Where-Object { $_ -ne $null })
    } catch { return @() }
}

function Save-SleepList($list) {
    try {
        $arr = @($list | Where-Object { $_ -ne $null })
        if ($arr.Count -eq 0) {
            '[]' | Set-Content -Path $SleepFile -Encoding UTF8
        } else {
            ConvertTo-Json -InputObject $arr -Depth 5 | Set-Content -Path $SleepFile -Encoding UTF8
        }
    } catch { }
}

function Get-AdbPort([string]$index) {
    try {
        $c = Join-Path $MuMuRoot ("vms\MuMuPlayer-15.0-{0}\configs\vm_config.json" -f $index)
        if (-not (Test-Path $c)) { return $null }
        $j = Get-Content $c -Raw -Encoding UTF8 | ConvertFrom-Json
        return $j.vm.nat.port_forward.adb.host_port
    } catch { return $null }
}

function Invoke-Wake([string]$index) {
    Write-Log "开始唤醒实例 $index"

    # 1) 启动实例
    try {
        $r = (& $MuMuMgr control -v $index launch 2>&1) -join ' '
        Write-Log ("启动实例: " + $r.Trim())
    } catch {
        Write-Log ("启动实例失败: " + $_.Exception.Message)
        return $false
    }

    # 2) 等开机
    $port = Get-AdbPort $index
    if (-not $port) { Write-Log "读不到 adb 端口"; return $false }
    $serial = "127.0.0.1:$port"

    $ready = $false
    for ($i = 0; $i -lt 60; $i++) {
        Start-Sleep -Seconds 3
        try { & $AdbExe connect $serial *> $null } catch { }
        try {
            $boot = (& $AdbExe -s $serial shell "getprop sys.boot_completed" 2>$null) -join ''
            if ($boot -match '1') {
                Start-Sleep -Seconds 4
                $ready = $true
                Write-Log ('开机完成，约 {0} 秒' -f (($i + 1) * 3))
                break
            }
        } catch { }
    }
    if (-not $ready) { Write-Log "等待开机超时"; return $false }

    # 3) 启动紫孔雀
    try {
        $r = (& $MuMuMgr control -v $index app launch -pkg $PkgScript 2>&1) -join ' '
        Write-Log ("启动紫孔雀: " + $r.Trim())
    } catch {
        Write-Log ("启动紫孔雀失败: " + $_.Exception.Message)
    }

    # 4) 确认
    for ($i = 0; $i -lt 10; $i++) {
        Start-Sleep -Seconds 2
        $pid1 = ((& $AdbExe -s $serial shell "pidof $PkgScript" 2>$null) -join '').Trim()
        if ($pid1) { Write-Log "唤醒成功 PID=$pid1"; return $true }
    }
    Write-Log "唤醒后脚本未启动"
    return $false
}

Write-Log '唤醒进程启动'

$lastReport = $null
while ($true) {
    $list = Get-SleepList
    if ($list.Count -eq 0) {
        Write-Log '没有待唤醒任务，退出'
        break
    }

    $now = Get-Date
    $remain = @()
    foreach ($item in $list) {
        $idx = "$($item.Index)"
        $wakeAt = $null
        try { $wakeAt = [datetime]::Parse("$($item.WakeAt)") } catch { }

        if (-not $wakeAt) {
            Write-Log "实例 $idx 的唤醒时间无效，移除"
            Write-Event 'WAKE_FAIL' "实例$idx" '唤醒时间无效'
            continue
        }

        if ($wakeAt -le $now) {
            $lateMin = [int]($now - $wakeAt).TotalMinutes
            if ($lateMin -ge 2) {
                Write-Log "实例 $idx 迟到 $lateMin 分钟唤醒（可能电脑关机过）"
                Write-Event 'WAKE_LATE' "实例$idx" ("迟到 $lateMin 分钟")
            }

            $ok = Invoke-Wake $idx
            if ($ok) {
                Write-Event 'WAKE_OK' "实例$idx" '已唤醒并启动脚本'
            } else {
                Write-Log "实例 $idx 唤醒失败，移除任务（请手动处理）"
                Write-Event 'WAKE_FAIL' "实例$idx" '唤醒失败，请手动处理'
            }
            continue
        }

        $remain += $item
        $msg = "实例 $idx 将于 $($wakeAt.ToString('HH:mm:ss')) 唤醒"
        if ($lastReport -ne $msg) { Write-Log $msg; $lastReport = $msg }
    }

    Save-SleepList $remain
    if ($remain.Count -eq 0) {
        Write-Log '所有任务完成，退出'
        break
    }

    Start-Sleep -Seconds 20
}

try { $mutex.ReleaseMutex() } catch { }