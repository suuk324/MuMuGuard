#Requires -Version 5.1
<#
  Restart-Instance.ps1
  重启 MuMu 实例，等待开机完成后自动拉起「紫孔雀」脚本

  说明：后台挂机时游戏会由脚本自行管理（退出属正常），因此默认只拉起脚本。
  路径与包名从 config.json 读取，支持用户自定义。

  参数：
    -Index        实例编号
    -SkipScript   只重启不拉起脚本
    -LogFile      日志路径（可选）
#>
param(
    [Parameter(Mandatory = $true)][int]$Index,
    [switch]$SkipScript,
    [string]$LogFile
)

$ErrorActionPreference = 'Continue'
$Root = $PSScriptRoot
if (-not $LogFile) { $LogFile = Join-Path $Root 'logs\restart.log' }

# ---- 读取配置（路径与包名可自定义）----
$cfg = @{}
$cfgPath = Join-Path $Root 'config.json'
if (Test-Path $cfgPath) {
    try {
        $j = Get-Content $cfgPath -Raw -Encoding UTF8 | ConvertFrom-Json
        foreach ($p in $j.PSObject.Properties) { $cfg[$p.Name] = $p.Value }
    } catch { }
}

$MuMuRoot = if ($cfg.MuMuRoot) { [string]$cfg.MuMuRoot } else { 'D:\Program Files\Netease\MuMu' }
$MuMuMgr  = Join-Path $MuMuRoot 'nx_main\MuMuManager.exe'
$PkgScript = if ($cfg.PkgScript) { [string]$cfg.PkgScript } else { 'com.coc.zkqcode' }

# 实例目录里的版本号不一定等于配置里的根（可能同时装了安卓 12 / 15），按编号实际查找
function Find-VmSeries([string]$VmsDir, [string]$Idx) {
    try {
        $hit = Get-ChildItem $VmsDir -Directory -Filter ("MuMuPlayer-*-{0}" -f $Idx) -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($hit -and $hit.Name -match 'MuMuPlayer-([\d\.]+)-') { return $Matches[1] }
    } catch { }
    return '15.0'
}

$vmsDir = Join-Path $MuMuRoot 'vms'
$series = Find-VmSeries $vmsDir $Index
$CfgPath = Join-Path $MuMuRoot ("vms\MuMuPlayer-{0}-{1}\configs\vm_config.json" -f $series, $Index)

# adb 按实际存在的引擎目录取（优先与实例同版本）
$AdbExe = Join-Path $MuMuRoot ("nx_device\{0}\shell\adb.exe" -f $series)
if (-not (Test-Path $AdbExe)) {
    $cand = Get-ChildItem (Join-Path $MuMuRoot 'nx_device') -Directory -ErrorAction SilentlyContinue |
            Sort-Object Name -Descending | ForEach-Object { Join-Path $_.FullName 'shell\adb.exe' } |
            Where-Object { Test-Path $_ } | Select-Object -First 1
    if ($cand) { $AdbExe = $cand }
}
# 版本识别结果在 Write-Log 定义之后再记录（见下方）

# ---- 诊断日志 ----
$diagFile = Join-Path $Root 'logs\diag.log'
function Write-Diag([string]$msg) {
    try {
        $d = Split-Path $diagFile -Parent
        if (-not (Test-Path $d)) { New-Item -ItemType Directory -Path $d -Force | Out-Null }
        Add-Content -Path $diagFile -Value ('[{0:yyyy-MM-dd HH:mm:ss}] [Restart] {1}' -f (Get-Date), $msg) -Encoding UTF8
    } catch { }
}

function Write-Log([string]$msg) {
    $line = '[{0:HH:mm:ss}] [实例{1}] {2}' -f (Get-Date), $Index, $msg
    try {
        $d = Split-Path $LogFile -Parent
        if (-not (Test-Path $d)) { New-Item -ItemType Directory -Path $d -Force | Out-Null }
        Add-Content -Path $LogFile -Value $line -Encoding UTF8
    } catch { }
    Write-Diag $msg
}

# 记录版本识别结果（此时 Write-Diag 已定义）
Write-Diag ("实例{0} 使用版本 {1}，配置 {2}" -f $Index, $series, $CfgPath)

function Get-AdbPort {
    try {
        if (-not (Test-Path $CfgPath)) {
            Write-Diag "找不到实例配置: $CfgPath"
            return $null
        }
        $j = Get-Content $CfgPath -Raw -Encoding UTF8 | ConvertFrom-Json
        return $j.vm.nat.port_forward.adb.host_port
    } catch {
        Write-Diag "解析实例配置失败: $($_.Exception.Message)"
        return $null
    }
}

function Test-MuMuPresent {
    if (-not (Test-Path $MuMuMgr)) {
        Write-Diag "找不到 MuMuManager: $MuMuMgr（请在设置里检查 MuMu 路径）"
        return $false
    }
    return $true
}

Write-Log '开始重启'

if (-not (Test-MuMuPresent)) { exit 1 }

# 1) 重启实例
try {
    $out = (& $MuMuMgr control -v $Index restart 2>&1) -join ' '
    Write-Log ('重启指令: ' + $out.Trim())
    if ($out -notmatch 'errcode"\s*:\s*0') {
        Write-Diag "重启指令返回异常: $out"
    }
} catch {
    Write-Log ('重启指令失败: ' + $_.Exception.Message)
    exit 1
}

# 2) 等待 adb 端口可用并完成开机
$port = Get-AdbPort
if (-not $port) {
    Write-Log '读不到 adb 端口，放弃'
    exit 1
}
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

if (-not $ready) {
    Write-Log '等待开机超时'
    exit 1
}

if ($SkipScript) {
    Write-Log '已跳过脚本启动'
    exit 0
}

# 3) 拉起紫孔雀
try {
    $r = (& $MuMuMgr control -v $Index app launch -pkg $PkgScript 2>&1) -join ' '
    Write-Log ('启动紫孔雀: ' + $r.Trim())
} catch {
    Write-Log ('启动紫孔雀失败: ' + $_.Exception.Message)
}

# 4) 确认脚本进程
$ok = $false
for ($i = 0; $i -lt 10; $i++) {
    Start-Sleep -Seconds 2
    $pid1 = ((& $AdbExe -s $serial shell "pidof $PkgScript" 2>$null) -join '').Trim()
    if ($pid1) {
        Write-Log ('紫孔雀已启动 PID=' + $pid1)
        $ok = $true
        break
    }
}
if (-not $ok) { Write-Log '紫孔雀未启动成功' }

Write-Log '处理完成'
