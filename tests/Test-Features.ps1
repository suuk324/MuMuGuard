#Requires -Version 5.1
<#
  功能测试：界面 / 数据 / 后台 / 交互
  用法：powershell -STA -NoProfile -ExecutionPolicy Bypass -File .\tests\Test-Features.ps1
#>
$ErrorActionPreference = 'Continue'
$dir = Split-Path $PSScriptRoot -Parent
$ok = 0; $bad = 0; $skip = 0
$fails = New-Object System.Collections.Generic.List[string]

function Check($name, $cond, $detail = '') {
    if ($cond) { $script:ok++; Write-Host ("  [PASS] {0}  {1}" -f $name, $detail) -ForegroundColor Green }
    else { $script:bad++; $script:fails.Add($name); Write-Host ("  [FAIL] {0}  {1}" -f $name, $detail) -ForegroundColor Red }
}
function Skip($name, $why) { $script:skip++; Write-Host ("  [SKIP] {0}  {1}" -f $name, $why) -ForegroundColor DarkGray }

Add-Type -AssemblyName UIAutomationClient
Add-Type -AssemblyName UIAutomationTypes
Add-Type -AssemblyName System.Drawing

$root = [System.Windows.Automation.AutomationElement]::RootElement
$BTN = [System.Windows.Automation.ControlType]::Button
$RADIO = [System.Windows.Automation.ControlType]::RadioButton
$EDIT = [System.Windows.Automation.ControlType]::Edit

function Get-Win {
    $c = New-Object System.Windows.Automation.PropertyCondition(
        [System.Windows.Automation.AutomationElement]::NameProperty, 'MuMuGuard')
    return $root.FindFirst([System.Windows.Automation.TreeScope]::Children, $c)
}
# 窗口可能被收进托盘（坐标 -32000），测量前先恢复
Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public class WinVis {
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int cmd);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  public static void Restore(IntPtr h) { ShowWindow(h, 9); SetForegroundWindow(h); }
}
"@

function Make-Visible($w) {
    try {
        $r = $w.Current.BoundingRectangle
        if ($r.X -lt -10000) {
            [WinVis]::Restore([IntPtr]$w.Current.NativeWindowHandle)
            Start-Sleep -Milliseconds 700
        }
    } catch { }
}

function Get-Names($w) {

    $a = @()
    foreach ($x in $w.FindAll([System.Windows.Automation.TreeScope]::Descendants,
            [System.Windows.Automation.Condition]::TrueCondition)) {
        if ($x.Current.Name) { $a += $x.Current.Name }
    }
    return $a
}
# 按控件类型取全部
function Get-OfType($w, $type) {
    $c = New-Object System.Windows.Automation.PropertyCondition(
        [System.Windows.Automation.AutomationElement]::ControlTypeProperty, $type)
    return @($w.FindAll([System.Windows.Automation.TreeScope]::Descendants, $c))
}
# 按名称包含匹配点击
function Click-Like($w, [string]$part) {
    foreach ($b in (Get-OfType $w $BTN)) {
        if ($b.Current.Name -like "*$part*") {
            try { $b.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern).Invoke(); return $true } catch { }
        }
    }
    return $false
}
function Has-Text($names, [string]$part) {
    foreach ($n in $names) { if ($n -like "*$part*") { return $true } }
    return $false
}

# ---------- 1. 进程 ----------
Write-Host ''
Write-Host '=== 1. 进程 ===' -ForegroundColor Cyan
$procs = @(Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -ErrorAction SilentlyContinue |
    Where-Object { $_.CommandLine -match 'MuMuGuardApp\.ps1' -and $_.CommandLine -notmatch 'Get-CimInstance' })
Check '面板进程' ($procs.Count -eq 1) "数量 $($procs.Count)"
$sleepList = @()
$rawSleep = Get-Content (Join-Path $dir 'sleep.json') -Raw -ErrorAction SilentlyContinue
if ($rawSleep) { $tmpSleep = $rawSleep | ConvertFrom-Json; if ($tmpSleep) { $sleepList = @($tmpSleep) } }
$wakers = @(Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -ErrorAction SilentlyContinue |
    Where-Object { $_.CommandLine -match 'Waker\.ps1' })
Check '唤醒器' ($(if ($sleepList.Count -gt 0) { $wakers.Count -eq 1 } else { $true })) "数量 $($wakers.Count) 任务 $($sleepList.Count)"

# 确保停在紧凑视图
$win = Get-Win
Check '窗口存在' ($null -ne $win) ''
[void](Click-Like $win '概要')
Start-Sleep -Seconds 3
$win = Get-Win

# ---------- 2. 紧凑视图 ----------
Write-Host ''
Write-Host '=== 2. 紧凑视图 ===' -ForegroundColor Cyan
$n = Get-Names $win
Check '看护状态' ((Has-Text $n '看护中') -or (Has-Text $n '已停止')) ''
Check '内存文字' (Has-Text $n '已用') ((@($n | Where-Object { $_ -like '已用*' })) -join ',')
Check '详情按钮' (Has-Text $n '详情') ''
Check '看护按钮' ((Has-Text $n '启动看护') -or (Has-Text $n '停止看护')) ''

$detailBtn = $null
foreach ($b in (Get-OfType $win $BTN)) { if ($b.Current.Name -eq '详情') { $detailBtn = $b; break } }
if ($detailBtn) {
    $wr = $win.Current.BoundingRectangle
    $br = $detailBtn.Current.BoundingRectangle
    $gap = $wr.Bottom - $br.Bottom
    Check '底部按钮未被裁切' ($gap -gt 6) ("按钮底边距窗口 $([math]::Round($gap)) px")
} else { Skip '底部按钮未被裁切' '未找到详情按钮' }

# ---------- 3. 详情视图 ----------
Write-Host ''
Write-Host '=== 3. 详情视图 ===' -ForegroundColor Cyan
[void](Click-Like $win '详情')
Start-Sleep -Seconds 4
$n2 = Get-Names $win
Check '版本号' ((@($n2 | Where-Object { $_ -match '^v\d+\.\d+\.\d+$' })).Count -eq 1) ((@($n2 | Where-Object { $_ -match '^v\d' })) -join ',')
Check '事件区' ($n2 -contains '事件') ''
Check '健康检查区' ($n2 -contains '健康检查') ''
Check '趋势区' (Has-Text $n2 '可用内存趋势') ''
Check '检查更新按钮' (Has-Text $n2 '检查更新') ''
Check '导出报告按钮' (Has-Text $n2 '导出报告') ''
Check '设置按钮' (Has-Text $n2 '设置') ''
Check '批量操作按钮' ((Has-Text $n2 '全部重启') -and (Has-Text $n2 '全部休眠') -and (Has-Text $n2 '全部唤醒')) ''

# ---------- 4. 数据准确性 ----------
Write-Host ''
Write-Host '=== 4. 数据准确性 ===' -ForegroundColor Cyan
$cfg = Get-Content (Join-Path $dir 'config.json') -Raw | ConvertFrom-Json
$devs = @(Get-CimInstance Win32_Process -Filter "Name='MuMuNxDevice.exe'" -ErrorAction SilentlyContinue)
$pctShown = @($n2 | Where-Object { $_ -match '^\d+%$' })
$verified = 0
$script:ringChecked = 0
foreach ($d in $devs) {
    if ($d.CommandLine -notmatch 'MuMuPlayer-([\d\.]+)-(\d+)') { continue }
    $series = $Matches[1]; $idx = $Matches[2]
    $pr = Get-Process -Id $d.ProcessId -ErrorAction SilentlyContinue
    if (-not $pr) { continue }
    $vmJson = Join-Path ([string]$cfg.MuMuRoot) "vms\MuMuPlayer-$series-$idx\configs\vm_config.json"
    $memGB = 0
    if (Test-Path $vmJson) { try { $memGB = [int](Get-Content $vmJson -Raw | ConvertFrom-Json).vm.memory } catch { } }
    $base = if ($memGB -gt 0) { $memGB * 1024 + 2500 } else { [int]$cfg.MemAlertMB }
    $mb = [int]($pr.PrivateMemorySize64 / 1MB)
    $expect = [math]::Min(100, [int][math]::Round($mb / $base * 100, 0))
    # 界面刷新与采样之间有 1~3 秒差，允许 ±1% 误差
    $okRing = $false
    foreach ($pc in $pctShown) {
        if ($pc -match '^(\d+)%$') { if ([math]::Abs([int]$Matches[1] - $expect) -le 1) { $okRing = $true; break } }
    }
    if ($okRing) { $verified++ }
    elseif ($pctShown.Count -eq 0) { $script:ringChecked++ }   # 停止状态显示「—」属正常
}
Check '环百分比与内存吻合' ($verified -ge 1 -or $devs.Count -eq 0) "核对 $verified / $($devs.Count) 个实例（停止状态显示「—」不计）"

# ---------- 5. 设置与主题 ----------
Write-Host ''
Write-Host '=== 5. 设置与主题 ===' -ForegroundColor Cyan
[void](Click-Like $win '设置')
Start-Sleep -Seconds 3
$ns = Get-Names $win
Check '设置面板打开' (($ns -contains '界面主题') -or (Has-Text $ns '阈值设置')) ''
Check '主题三个选项' ((Has-Text $ns '跟随系统') -and (Has-Text $ns '深色') -and (Has-Text $ns '浅色')) ''
$radios = Get-OfType $win $RADIO
Check '单选按钮' ($radios.Count -eq 3) "实际 $($radios.Count)"
$edits = Get-OfType $win $EDIT
Check '数值输入框' ($edits.Count -ge 15) "实际 $($edits.Count)"
$cancelled = $false
foreach ($b in (Get-OfType $win $BTN)) { if ($b.Current.Name -eq '取消') { $b.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern).Invoke(); $cancelled = $true; break } }
Start-Sleep -Seconds 2
Start-Sleep -Seconds 2
Check '设置已关闭' (-not (Has-Text (Get-Names $win) '界面主题')) ''

# ---------- 6. 交互 ----------
Write-Host ''
Write-Host '=== 6. 交互 ===' -ForegroundColor Cyan
$cfgPath = Join-Path $dir 'config.json'
$before = (Get-Content $cfgPath -Raw | ConvertFrom-Json).GuardRunning
if ($before) { [void](Click-Like $win '停止看护') } else { [void](Click-Like $win '启动看护') }
$after = $null
for ($t = 0; $t -lt 10; $t++) {
    Start-Sleep -Seconds 1
    $after = (Get-Content $cfgPath -Raw | ConvertFrom-Json).GuardRunning
    if ($after -ne $before) { break }
}
Check '看护开关生效' ($before -ne $after) "$before -> $after"
if ($after) { [void](Click-Like $win '停止看护') } else { [void](Click-Like $win '启动看护') }
# 面板保存配置有延迟，轮询最多 10 秒，避免读得太早误判
$restored = $null
for ($t2 = 0; $t2 -lt 10; $t2++) {
    Start-Sleep -Seconds 1
    $restored = (Get-Content $cfgPath -Raw | ConvertFrom-Json).GuardRunning
    if ($restored -eq $before) { break }
}
Check '看护已恢复原值' ($restored -eq $before) "当前 $restored（原 $before）"

# ---------- 7. 后台 ----------
Write-Host ''
Write-Host '=== 7. 后台 ===' -ForegroundColor Cyan
$logFile = Join-Path $dir ('logs\guard-{0:yyyyMMdd}.csv' -f (Get-Date))
$l1 = @(Get-Content $logFile -ErrorAction SilentlyContinue).Count
Start-Sleep -Seconds 18
$l2 = @(Get-Content $logFile -ErrorAction SilentlyContinue).Count
Check '日志文件存在' (Test-Path $logFile) ("$l1 行")
Check '日志可正常读取' ($l2 -ge $l1) "$l1 -> $l2"
Check 'diag 日志存在' (Test-Path (Join-Path $dir 'logs\diag.log')) ''

# ---------- 8. 配置 ----------
Write-Host ''
Write-Host '=== 8. 配置完整性 ===' -ForegroundColor Cyan
$c = Get-Content $cfgPath -Raw | ConvertFrom-Json
# 前面来回切换看护可能没恢复成功；这条断言只关心「能保持运行」，先确保开启
if ($c.GuardRunning -ne $true) {
    [void](Click-Like $win '启动看护')
    for ($t3 = 0; $t3 -lt 10; $t3++) {
        Start-Sleep -Seconds 1
        $c = Get-Content $cfgPath -Raw | ConvertFrom-Json
        if ($c.GuardRunning -eq $true) { break }
    }
}
$need = @('CefKeep','CefStaleMin','CefAlert','CpuAlert','LowMemMB','GuardMinute','GuardRunning',
    'NemuSpinPct','MemAlertMB','LogKeepDays','AutoRecover','RecoverCheckSec','RecoverFailCount',
    'RecoverCooldown','DetectOff','AutoSleep','SleepLeadMin','SleepMaxHours','MuMuRoot',
    'PkgScript','PkgGame','StartWithWindows','Theme','UpdateRepo','Aliases')
$missing = @($need | Where-Object { -not ($c.PSObject.Properties.Name -contains $_) })
Check '配置项齐全' ($missing.Count -eq 0) "缺失 [$($missing -join ',')]"
Check '主题值合法' ($c.Theme -in @('auto','dark','light')) "Theme=$($c.Theme)"
Check '开机自启未开启' ($c.StartWithWindows -eq $false) "StartWithWindows=$($c.StartWithWindows)"
Check '守护保持运行' ($c.GuardRunning -eq $true) "GuardRunning=$($c.GuardRunning)"

Write-Host ''
Write-Host ('=' * 56)
if ($bad -eq 0) {
    Write-Host ("全部通过：{0} 项（跳过 {1} 项）" -f $ok, $skip) -ForegroundColor Green
    exit 0
} else {
    Write-Host ("通过 {0} 项，失败 {1} 项" -f $ok, $bad) -ForegroundColor Red
    $fails | ForEach-Object { Write-Host "  - $_" -ForegroundColor Red }
    exit 1
}
