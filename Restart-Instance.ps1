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
    [string]$LogFile,
    [string]$DataDir
)

$ErrorActionPreference = 'Continue'
$Root = $PSScriptRoot
if (-not $LogFile) { $LogFile = Join-Path $Root 'logs\restart.log' }
# 打包后 helper 在 LOCALAPPDATA，config.json / hooks 在数据目录（由面板传入）
if (-not $DataDir) { $DataDir = $Root }
if (-not (Test-Path $DataDir)) { $DataDir = $Root }

# ---- 读取配置（路径与包名可自定义）----
$cfg = @{}
$cfgPath = Join-Path $DataDir 'config.json'
if (Test-Path $cfgPath) {
    try {
        $j = Get-Content $cfgPath -Raw -Encoding UTF8 | ConvertFrom-Json
        foreach ($p in $j.PSObject.Properties) { $cfg[$p.Name] = $p.Value }
    } catch { }
}

# 定位 MuMu 安装根（不假设任何盘符；找不到就返回空，不抛异常）
function Find-MuMuRoot {
    param([string]$Hint = '')
    $ok = {
        param($p)
        if (-not $p) { return $false }
        try {
            $r = [System.IO.Path]::GetPathRoot($p)
            if (-not $r -or -not (Test-Path -LiteralPath $r)) { return $false }
            if (Test-Path -LiteralPath ([System.IO.Path]::Combine($p, 'nx_main\MuMuManager.exe'))) { return $true }
            if ((Test-Path -LiteralPath ([System.IO.Path]::Combine($p, 'nx_device'))) -and (Test-Path -LiteralPath ([System.IO.Path]::Combine($p, 'vms')))) { return $true }
        } catch { }
        return $false
    }
    if ($Hint -and (& $ok $Hint)) { return $Hint }
    try {
        $ic = Join-Path $env:APPDATA 'Netease\MuMuPlayer\install_config.json'
        if (Test-Path -LiteralPath $ic) {
            $j = Get-Content -LiteralPath $ic -Raw -Encoding UTF8 | ConvertFrom-Json
            foreach ($eng in $j.engines.PSObject.Properties) {
                $d = [string]$eng.Value.player.install_dir
                for ($i = 0; $i -lt 5 -and $d; $i++) {
                    if (& $ok $d) { return $d }
                    $d = Split-Path $d -Parent
                }
            }
        }
    } catch { }
    $subs = @('Program Files\Netease\MuMu', 'Program Files (x86)\Netease\MuMu', 'Netease\MuMu', 'MuMu', 'Program Files\Netease\MuMuPlayer')
    foreach ($drv in (Get-PSDrive -PSProvider FileSystem -ErrorAction SilentlyContinue)) {
        foreach ($s in $subs) {
            try { $p = Join-Path $drv.Root $s; if (& $ok $p) { return $p } } catch { }
        }
    }
    return ''
}
$MuMuRoot = Find-MuMuRoot ([string]$cfg.MuMuRoot)
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

# ---- 「启动后操作」：重启开机后先执行（例如连 VPN），完成后再启动紫孔雀 ----
$HookDataDir = $DataDir
$HookStatusFile = Join-Path $HookDataDir 'hooks-status.json'
$HookLogFile = Join-Path $HookDataDir 'hooks.log'

function Write-HookLog([string]$msg) {
    try { Add-Content -Path $HookLogFile -Value ('[{0:yyyy-MM-dd HH:mm:ss}] 重启器: {1}' -f (Get-Date), $msg) -Encoding UTF8 } catch { }
}

function Write-HookStatus([string]$idx, [string]$state, [string]$msg, [string]$launchTime) {
    $all = @{}
    try {
        if (Test-Path $HookStatusFile) {
            $raw = Get-Content $HookStatusFile -Raw -Encoding UTF8
            if ($raw -and $raw.Trim()) {
                $obj = $raw | ConvertFrom-Json
                foreach ($p in $obj.PSObject.Properties) { $all[$p.Name] = $p.Value }
            }
        }
    } catch { }
    $nowTxt = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
    $all["$idx"] = [ordered]@{
        State = $state; Message = $msg; UpdatedAt = $nowTxt; LastRunAt = $nowTxt; LastLaunchTime = $launchTime
    }
    try {
        $tmp = "$HookStatusFile.tmp"
        ($all | ConvertTo-Json -Depth 5) | Set-Content -Path $tmp -Encoding UTF8
        Move-Item -Path $tmp -Destination $HookStatusFile -Force
    } catch { }
}

function Get-InstanceHookCfg([string]$idx) {
    try {
        $store = $cfg['InstanceHooks']
        if ($store -and $store.PSObject.Properties.Name -contains "$idx") { return $store."$idx" }
    } catch { }
    return $null
}

function Get-InstancePid([string]$idx) {
    for ($i = 0; $i -lt 20; $i++) {
        try {
            $raw = (& $MuMuMgr info -v $idx 2>&1 | Out-String)
            if ($raw -match '"index"') {
                $j = $raw | ConvertFrom-Json
                if ($j.pid) { return "$($j.pid)" }
            }
        } catch { }
        Start-Sleep -Milliseconds 500
    }
    return ''
}

function Invoke-StartHook([string]$idx, [string]$serial, [string]$instancePid) {
    $hook = Get-InstanceHookCfg $idx
    if (-not $hook) { return $true }
    $on = $false; try { $on = [bool]$hook.Enabled } catch { }
    if (-not $on) { return $true }

    $delay = 0; try { $delay = [int]$hook.DelaySec } catch { }
    Write-HookStatus $idx 'running' '重启器：执行启动后操作' $instancePid
    if ($delay -gt 0) { Start-Sleep -Seconds $delay }
    $errs = @()
    foreach ($pkg in @($hook.AutoStartApps)) {
        $p = "$pkg".Trim()
        if (-not $p) { continue }
        Write-HookLog "实例$idx 启动应用 $p"
        try { $null = (& $AdbExe -s $serial shell "monkey -p $p -c android.intent.category.LAUNCHER 1" 2>&1) } catch { $errs += $_.Exception.Message }
        Start-Sleep -Seconds 2
    }
    foreach ($c in @($hook.PostStartCommands)) {
        $cmd = "$c".Trim()
        if (-not $cmd) { continue }
        Write-HookLog "实例$idx 执行命令 $cmd"
        try { $null = (& $AdbExe -s $serial shell $cmd 2>&1) } catch { $errs += $_.Exception.Message }
    }
    $sc = "$($hook.PostStartScript)".Trim()
    if ($sc) {
        $path = $sc
        if (-not [System.IO.Path]::IsPathRooted($path)) { $path = Join-Path $HookDataDir $path }
        if (Test-Path $path) {
            Write-HookLog "实例$idx 执行脚本 $path"
            $env:MMG_INSTANCE = "$idx"
            $env:MMG_SERIAL = $serial
            $env:MMG_ADB = $AdbExe
            $env:MMG_DATA_DIR = $HookDataDir
            try {
                $psi = New-Object System.Diagnostics.ProcessStartInfo
                $psi.FileName = 'powershell.exe'
                $psi.Arguments = '-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "' + $path + '"'
                $psi.UseShellExecute = $false
                $psi.CreateNoWindow = $true
                $psi.RedirectStandardOutput = $true
                $psi.RedirectStandardError = $true
                $child = [System.Diagnostics.Process]::Start($psi)
                $done = $child.WaitForExit(240000)
                if (-not $done) { try { $child.Kill() } catch { }; $errs += '脚本超时（240秒）' }
                elseif ([int]$child.ExitCode -ne 0) { $errs += "脚本退出码 $($child.ExitCode)" }
                try { $null = $child.StandardOutput.ReadToEnd() } catch { }
                try { $null = $child.StandardError.ReadToEnd() } catch { }
            } catch { $errs += $_.Exception.Message }
        } else { $errs += "脚本不存在: $sc" }
    }
    if ($errs.Count -gt 0) {
        Write-HookStatus $idx 'error' ('重启器：部分失败: ' + ($errs -join '; ')) $instancePid
        Write-HookLog "实例$idx 启动后操作失败: $($errs -join '; ')"
        return $false
    }
    Write-HookStatus $idx 'ok' '重启器：启动后操作完成' $instancePid
    Write-HookLog "实例$idx 启动后操作完成"
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

# 2.5) 先执行「启动后操作」（如连 VPN），脚本成功退出后再启动紫孔雀
# 紫孔雀有开机自启广播，可能抢在 VPN 前面起来：先停掉，等启动后操作完成再主动启动
try { $null = (& $AdbExe -s $serial shell "am force-stop $PkgScript" 2>&1) } catch { }
Start-Sleep -Seconds 2
$hookPid = Get-InstancePid $Index
$hookOk = $true
try { $hookOk = Invoke-StartHook $Index $serial $hookPid } catch { Write-Log ('启动后操作异常: ' + $_.Exception.Message) }
if ($hookOk) { Write-Log '启动后操作完成，继续启动紫孔雀' } else { Write-Log '启动后操作未完全成功，继续启动紫孔雀（不阻塞上号）' }

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
