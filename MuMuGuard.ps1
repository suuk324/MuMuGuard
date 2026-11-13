<#
  MuMuGuard.ps1  -  MuMu 模拟器看护脚本

  功能：
    1) 清理泄漏的 CefViewWing 子进程（每个实例只保留最新 3 个）
    2) 监控实例 CPU 空转，连续 3 轮超过阈值则记录告警
    3) 主机可用内存低于阈值时记录告警

  参数：
    -Status   只读查看当前状态，不做任何修改
    -WhatIf   试运行，不结束进程、不写状态文件

  停止方式：禁用计划任务 MuMuGuard，或双击管理菜单
#>
[CmdletBinding()]
param(
    [switch]$Status,
    [switch]$WhatIf
)

$ErrorActionPreference = 'Continue'
$Root      = $PSScriptRoot
$LogDir    = Join-Path $Root 'logs'
$StateFile = Join-Path $Root 'state.json'
$LogFile   = Join-Path $LogDir ('guard-{0:yyyyMMdd}.csv' -f (Get-Date))

$CEF_KEEP      = 3     # 每个实例至少保留最新几个
$CEF_STALE_MIN = 10    # 只清理存在超过多少分钟的 CEF（避免误杀活跃进程）
$CEF_ALERT     = 20    # CEF 总数超过此值才判定为泄漏并清理
$CPU_ALERT     = 4.0   # 单实例超过多少核视为异常
$LOW_MEM_MB    = 800   # 主机可用内存低于此值告警

if (-not (Test-Path $LogDir)) { New-Item -ItemType Directory -Path $LogDir -Force | Out-Null }

function Write-GuardLog {
    param([string]$Action, [string]$Instance, [string]$Detail)
    $line = '{0:yyyy-MM-dd HH:mm:ss},{1},{2},{3}' -f (Get-Date), $Action, $Instance, $Detail
    if (-not $WhatIf) {
        if (-not (Test-Path $LogFile)) {
            'Time,Action,Instance,Detail' | Set-Content -Path $LogFile -Encoding UTF8
        }
        Add-Content -Path $LogFile -Value $line -Encoding UTF8
    }
}

function Get-CefChildren {
    param([int]$ParentPid)
    Get-CimInstance Win32_Process -Filter "Name='CefViewWing.exe'" -ErrorAction SilentlyContinue |
        Where-Object { $_.ParentProcessId -eq $ParentPid }
}

function Get-CpuCores {
    param([int[]]$TargetPids, [int]$Seconds = 2)
    $before = @{}
    foreach ($p in $TargetPids) {
        $proc = Get-Process -Id $p -ErrorAction SilentlyContinue
        if ($proc) { $before[$p] = $proc.CPU }
    }
    Start-Sleep -Seconds $Seconds
    $result = @{}
    foreach ($p in $before.Keys) {
        $proc = Get-Process -Id $p -ErrorAction SilentlyContinue
        if ($proc -and $null -ne $proc.CPU) {
            $result[$p] = [math]::Round(($proc.CPU - $before[$p]) / $Seconds, 2)
        }
    }
    return $result
}

$devices = @(Get-Process MuMuNxDevice -ErrorAction SilentlyContinue)

# ================= 状态查看模式 =================
if ($Status) {
    Write-Host ''
    Write-Host '  MuMuGuard - 当前状态' -ForegroundColor Cyan
    Write-Host '  ================================================'
    if ($devices.Count -eq 0) {
        Write-Host '  未发现 MuMu 实例'
    } else {
        $cpu = Get-CpuCores -TargetPids @($devices.Id) -Seconds 3
        $rows = foreach ($d in $devices) {
            $cefCount = @(Get-CefChildren -ParentPid $d.Id).Count
            [pscustomobject]@{
                '实例PID'  = $d.Id
                '核心占用' = $cpu[$d.Id]
                '私有MB'   = [int]($d.PrivateMemorySize64 / 1MB)
                '工作集MB' = [int]($d.WorkingSet64 / 1MB)
                'CEF进程'  = $cefCount
            }
        }
        $rows | Format-Table -AutoSize | Out-String -Width 100 | Write-Host
    }

    $mem = Get-CimInstance Win32_PerfRawData_PerfOS_Memory
    $pf  = Get-CimInstance Win32_PageFileUsage
    $mc  = Get-Process -Name 'Memory Compression' -ErrorAction SilentlyContinue
    $task = Get-ScheduledTask -TaskName 'MuMuGuard' -ErrorAction SilentlyContinue
    Write-Host ('  主机可用内存 : {0} MB' -f [int]$mem.AvailableMBytes)
    Write-Host ('  提交内存     : {0:N1} GB' -f ($mem.CommittedBytes / 1GB))
    Write-Host ('  页面文件     : {0} MB' -f $pf.CurrentUsage)
    if ($mc) { Write-Host '  内存压缩     : 已启用' -ForegroundColor Green }
    else     { Write-Host '  内存压缩     : 未启用' -ForegroundColor Yellow }
    if ($task) { Write-Host ('  看护任务     : {0}' -f $task.State) } else { Write-Host '  看护任务     : 未安装' }
    Write-Host ''
    return
}

# ================= 看护主逻辑 =================
if ($devices.Count -eq 0) { Write-GuardLog 'SKIP' '-' 'no MuMu instance'; return }

$cpu = Get-CpuCores -TargetPids @($devices.Id) -Seconds 2

$oldState = @{}
if (Test-Path $StateFile) {
    try {
        $obj = Get-Content $StateFile -Raw -ErrorAction Stop | ConvertFrom-Json
        foreach ($prop in $obj.PSObject.Properties) { $oldState[$prop.Name] = [int]$prop.Value }
    } catch { }
}

$newState = @{}

foreach ($d in $devices) {
    $key = "$($d.Id)"

    # 1) CEF 清理（只清陈旧进程，活跃进程保留）
    $cef = @(Get-CefChildren -ParentPid $d.Id | Sort-Object CreationDate -Descending)
    if ($cef.Count -gt $CEF_ALERT) {
        $ageLimit = (Get-Date).AddMinutes(-$CEF_STALE_MIN)
        $toKill = @($cef | Select-Object -Skip $CEF_KEEP |
                    Where-Object { $_.CreationDate -and $_.CreationDate -lt $ageLimit })
        if ($toKill.Count -gt 0) {
            $killed = 0
            foreach ($c in $toKill) {
                if ($WhatIf) { $killed++; continue }
                try { Stop-Process -Id $c.ProcessId -Force -ErrorAction Stop; $killed++ } catch { }
            }
            Write-GuardLog 'CLEAN_CEF' "PID=$key" ("total={0} stale={1} killed={2}" -f $cef.Count, $toKill.Count, $killed)
        }
    }

    # 2) 空转监控
    $cores  = $cpu[$d.Id]
    $rounds = 0
    if ($oldState.ContainsKey($key)) { $rounds = $oldState[$key] }
    if ($null -ne $cores -and $cores -gt $CPU_ALERT) {
        $rounds++
        if ($rounds -ge 3) {
            Write-GuardLog 'ALERT_SPIN' "PID=$key" ("cpu={0} cores, rounds={1}" -f $cores, $rounds)
        }
    } else {
        $rounds = 0
    }
    $newState[$key] = $rounds
}

# 3) 主机内存告警
$mem   = Get-CimInstance Win32_PerfRawData_PerfOS_Memory
$avail = [int]$mem.AvailableMBytes
if ($avail -lt $LOW_MEM_MB) {
    Write-GuardLog 'LOW_MEM' '-' ("available={0}MB" -f $avail)
}

if (-not $WhatIf) {
    $newState | ConvertTo-Json -Compress | Set-Content -Path $StateFile -Encoding UTF8
}
