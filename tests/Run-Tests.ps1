#Requires -Version 5.1
<#
  Run-Tests.ps1
  MuMuGuard 单元测试（无第三方框架，直接跑即可）

  用法：
    powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\Run-Tests.ps1
    .\tests\Run-Tests.ps1 -Verbose

  退出码：0 = 全部通过，1 = 有失败
#>
param([switch]$Verbose)

$ErrorActionPreference = 'Stop'

$root = Split-Path $PSScriptRoot -Parent
$pureFile = Join-Path $root 'lib\90-pure.ps1'
if (-not (Test-Path $pureFile)) {
    Write-Host "找不到 $pureFile" -ForegroundColor Red
    exit 2
}
. $pureFile

$script:pass = 0
$script:fail = 0
$script:failures = New-Object System.Collections.Generic.List[string]

function Test-Case {
    param(
        [string]$Name,
        [scriptblock]$Body
    )
    try {
        $result = & $Body
        if ($result -eq $true) {
            $script:pass++
            if ($Verbose) { Write-Host "  PASS  $Name" -ForegroundColor Green }
        } else {
            $script:fail++
            $script:failures.Add($Name)
            Write-Host "  FAIL  $Name" -ForegroundColor Red
            if ($null -ne $result -and $result -ne $false) {
                Write-Host "        返回: $result" -ForegroundColor DarkRed
            }
        }
    } catch {
        $script:fail++
        $script:failures.Add("$Name （异常: $($_.Exception.Message)）")
        Write-Host "  ERROR $Name -> $($_.Exception.Message)" -ForegroundColor Red
    }
}

function Assert-Equal($expected, $actual) {
    if ("$expected" -ne "$actual") {
        return "期望 '$expected'，实际 '$actual'"
    }
    return $true
}

# ---------------- 采集输出解析（防标记互相吞并）----------------
# 背景：INST 段插在 GAME 和 SEP 之间，早期解析把 APK 路径当成游戏输出，导致误报「游戏运行中」
$probe1 = "READY`nSCRIPT`n2089`nGAME`nINST`npackage:/data/app/~~3MgQ4jU/base.apk`nSEP`n   0:01.09 nemuinit"
Test-Case '解析：脚本运行中、游戏未运行、已安装' {
    $sp = ''
    $gp = ''
    $ip = ''
    if ($probe1 -match '(?s)SCRIPT\s*(.*?)\s*GAME') { $sp = $Matches[1] }
    if ($probe1 -match '(?s)GAME\s*(.*?)(?:\s*INST|\s*SEP)') { $gp = $Matches[1] }
    if ($probe1 -match '(?s)INST\s*(.*?)\s*SEP') { $ip = $Matches[1] }
    Assert-Equal $true  ($sp -match '(?m)^\s*\d+\s*$')
    Assert-Equal $false ($gp -match '(?m)^\s*\d+\s*$')
    Assert-Equal $true  ($ip -match 'package:')
}

Test-Case '解析：游戏确实在运行' {
    $probe2 = "READY`nSCRIPT`n2089`nGAME`n12345`n12346`nINST`n`nSEP`n   0:01.09 nemuinit"
    $gp2 = ''
    if ($probe2 -match '(?s)GAME\s*(.*?)(?:\s*INST|\s*SEP)') { $gp2 = $Matches[1] }
    Assert-Equal $true ($gp2 -match '(?m)^\s*\d+\s*$')
}

Test-Case '解析：未安装时判定为未安装（不当作掉线）' {
    $probe3 = "READY`nSCRIPT`n`nGAME`n`nINST`n`nSEP`n   0:01.09 nemuinit"
    $ip3 = ''
    if ($probe3 -match '(?s)INST\s*(.*?)\s*SEP') { $ip3 = $Matches[1] }
    Assert-Equal $false ($ip3 -match 'package:')
}

Test-Case '解析：脚本没在跑时不能误判' {
    $probe4 = "READY`nSCRIPT`n`nGAME`n`nINST`npackage:/x/base.apk`nSEP`n   0:01.09 nemuinit"
    $sp4 = ''
    if ($probe4 -match '(?s)SCRIPT\s*(.*?)\s*GAME') { $sp4 = $Matches[1] }
    Assert-Equal $false ($sp4 -match '(?m)^\s*\d+\s*$')
}

# ---------------- 休眠判定：最短/最长/提前 -----------------
$sleepNow = [datetime]'2026-11-14 18:00:00'








# ---------------- 同一升级只休眠一次 ----------------



Write-Host ''
Write-Host '=== Get-RemainingLabel（剩余时间格式化）===' -ForegroundColor Cyan

$now = [datetime]'2026-11-13 12:00:00'

Test-Case '1小时25分 -> 1h25m' {
    $r = Get-RemainingLabel -DoneAt $now.AddMinutes(85) -Now $now
    Assert-Equal '1h25m' $r
}

Test-Case '整2小时 -> 2h00m' {
    $r = Get-RemainingLabel -DoneAt $now.AddHours(2) -Now $now
    Assert-Equal '2h00m' $r
}

Test-Case '30分钟 -> 30m' {
    $r = Get-RemainingLabel -DoneAt $now.AddMinutes(30) -Now $now
    Assert-Equal '30m' $r
}

Test-Case '已过期 -> 空串' {
    $r = Get-RemainingLabel -DoneAt $now.AddMinutes(-1) -Now $now
    Assert-Equal '' $r
}

Test-Case '恰好到点 -> 空串' {
    $r = Get-RemainingLabel -DoneAt $now -Now $now
    Assert-Equal '' $r
}

Test-Case 'null -> 空串' {
    $r = Get-RemainingLabel -DoneAt $null -Now $now
    Assert-Equal '' $r
}

Test-Case '59秒 -> 1m（向上取整）' {
    $r = Get-RemainingLabel -DoneAt $now.AddSeconds(59) -Now $now
    Assert-Equal '1m' $r
}

Write-Host ''
Write-Host '=== Get-MemPercent（内存百分比）===' -ForegroundColor Cyan

Test-Case '9216/9216 -> 100' {
    Assert-Equal 100 (Get-MemPercent -PrivateMB 9216 -BaseMB 9216)
}

Test-Case '4608/9216 -> 50' {
    Assert-Equal 50 (Get-MemPercent -PrivateMB 4608 -BaseMB 9216)
}

Test-Case '超过阈值封顶 100' {
    Assert-Equal 100 (Get-MemPercent -PrivateMB 12000 -BaseMB 9216)
}

Test-Case '0 内存 -> 0' {
    Assert-Equal 0 (Get-MemPercent -PrivateMB 0 -BaseMB 9216)
}

Test-Case '阈值非法 -> 0（不除以零）' {
    Assert-Equal 0 (Get-MemPercent -PrivateMB 5000 -BaseMB 0)
}

Write-Host ''

$waitingLines = @(
    '2026-11-13 18:00:01 账号1，升级中：箭塔，剩余时间：1小时20分钟'
    '2026-11-13 18:00:04 账号1，升级中：箭塔，剩余时间：1小时19分钟'
    '2026-11-13 18:00:07 账号1，升级中：箭塔，剩余时间：1小时19分钟'
    '2026-11-13 18:00:10 账号1，升级中：箭塔，剩余时间：1小时18分钟'
    '2026-11-13 18:00:13 账号1，升级中：箭塔，剩余时间：1小时18分钟'
    '2026-11-13 18:00:16 账号1，升级中：箭塔，剩余时间：1小时17分钟'
)


$workingLines = @(
    '2026-11-13 18:00:01 账号1，主世界搜索中... 第1/15局'
    '2026-11-13 18:00:04 账号1，已找到：对战页面,坐标：181, 331'
    '2026-11-13 18:00:07 账号1，进攻需等待冷却'
    '2026-11-13 18:00:10 账号1，主世界搜索中... 第2/15局'
    '2026-11-13 18:00:13 账号1，已找到：对战页面,坐标：181, 331'
    '2026-11-13 18:00:16 账号1，进攻需等待冷却'
)





Write-Host ''
Write-Host '=== Get-UpgradeFromMemoryJson（解析升级数据）===' -ForegroundColor Cyan

$mem1 = '{"NextUpgrade1":"{\"name\":\"箭塔\",\"lvl\":11,\"completionTs\":1794566864}","accountNumber":"1"}'
$mem2 = '{"NextUpgrade2":"{\"name\":\"加农炮\",\"lvl\":5,\"completionTs\":1794567000}","accountNumber":"2"}'
$mem3 = '{"accountNumber":"1"}'
$memBad = 'not a json'

Test-Case '账号1 解析正确' {
    $u = Get-UpgradeFromMemoryJson -Text $mem1
    if ($u.Name -ne '箭塔') { return "名称错误: $($u.Name)" }
    if ($u.Lvl -ne 11) { return "等级错误: $($u.Lvl)" }
    if ($u.Ts -ne 1794566864) { return "时间戳错误: $($u.Ts)" }
    return $true
}

Test-Case '账号2 取对应字段' {
    $u = Get-UpgradeFromMemoryJson -Text $mem2
    Assert-Equal '加农炮' $u.Name
}

Test-Case '没有升级字段 -> null' {
    $u = Get-UpgradeFromMemoryJson -Text $mem3
    Assert-Equal $null $u
}

Test-Case '非法 JSON -> null' {
    $u = Get-UpgradeFromMemoryJson -Text $memBad
    Assert-Equal $null $u
}

Test-Case '空串 -> null' {
    Assert-Equal $null (Get-UpgradeFromMemoryJson -Text '')
}

Write-Host ''

function New-TestRow {
    param([hashtable]$Override = @{})
    $base = @{
        Index = '3'; Script = $true; Waiting = $true; Sched = $true
        UpDone = ([datetime]'2026-11-13 18:47:44'); Level = 0
        UpName = '箭塔'; UpLvl = 11
    }
    foreach ($k in $Override.Keys) { $base[$k] = $Override[$k] }
    return [pscustomobject]$base
}

$tNow = [datetime]'2026-11-13 18:10:00'
$common = @{
    AutoSleep = $true; GuardRunning = $true
    LeadMin = 10; MaxHours = 20; Now = $tNow
    DetectOff = @(); SleepingIndexes = @()
}















Write-Host ''
Write-Host '=== Get-ShortLabels（实例名缩写）===' -ForegroundColor Cyan

Test-Case '共享前缀 -> 只留差异部分' {
    $r = @(Get-ShortLabels -Names @('MuMu安卓设备-1','MuMu安卓设备-1-1','MuMu安卓设备-1-2'))
    Assert-Equal '1 1-1 1-2' ($r -join ' ')
}

Test-Case '无公共前缀 -> 原名' {
    $r = @(Get-ShortLabels -Names @('大号','小号2'))
    Assert-Equal '大号 小号2' ($r -join ' ')
}

Test-Case '单个实例 -> 原名' {
    $r = @(Get-ShortLabels -Names @('实例 1'))
    Assert-Equal '实例 1' ($r -join ' ')
}

Test-Case '缩写后不能重名' {
    $r = @(Get-ShortLabels -Names @('A-1','B-1'))
    Assert-Equal ($r.Count) (@($r | Select-Object -Unique).Count)
}

Write-Host ''
Write-Host '=== Get-CompactMode / Get-RingScale ===' -ForegroundColor Cyan

Test-Case '5 个及以内用环形' {
    Assert-Equal 'rings' (Get-CompactMode -Count 5)
}

Test-Case '6 个用列表' {
    Assert-Equal 'list' (Get-CompactMode -Count 6)
}

Test-Case '数量越多环越小' {
    Assert-Equal $true ((Get-RingScale 1) -gt (Get-RingScale 3) -and (Get-RingScale 3) -gt (Get-RingScale 5))
}

Write-Host ''
Write-Host '=== Get-InstanceIndexFromCommandLine（从进程命令行取实例号）===' -ForegroundColor Cyan

Test-Case 'MuMuNxDevice 命令行 -> 4' {
    $cl = '"D:\Program Files\Netease\MuMu\nx_device\12.0\shell\MuMuNxDevice.exe" -v 4 --vm MuMuPlayer-12.0-4'
    Assert-Equal '4' (Get-InstanceIndexFromCommandLine -CommandLine $cl)
}

Test-Case 'MuMuVMMHeadless --comment -> 15.0-5 的 5' {
    $cl = '"C:\Program Files\MuMuVMMVbox\Hypervisor\MuMuVMMHeadless.exe" --comment MuMuPlayer-15.0-5 --startvm f8c76c57-051b-1c87-1000-000000000005 --vrde config'
    Assert-Equal '5' (Get-InstanceIndexFromCommandLine -CommandLine $cl)
}

Test-Case '只有 --startvm uuid 时用末段 -> 1' {
    $cl = 'MuMuVMMHeadless.exe --startvm f8c76c57-051b-1c87-1000-000000000001'
    Assert-Equal '1' (Get-InstanceIndexFromCommandLine -CommandLine $cl)
}

Test-Case '不相关命令行 -> 空串' {
    Assert-Equal '' (Get-InstanceIndexFromCommandLine -CommandLine '"C:\Windows\System32\notepad.exe"')
}

Test-Case '空命令行 -> 空串' {
    Assert-Equal '' (Get-InstanceIndexFromCommandLine -CommandLine '')
}

Write-Host ''
Write-Host '=== Get-InstanceMemBase（内存刻度）===' -ForegroundColor Cyan

Test-Case '6G 实例 -> 9144' {
    Assert-Equal 9144 (Get-InstanceMemBase -MemoryGB 6)
}

Test-Case '4G 实例 -> 7096' {
    Assert-Equal 7096 (Get-InstanceMemBase -MemoryGB 4)
}

Test-Case '未知内存 -> 兜底 9216' {
    Assert-Equal 9216 (Get-InstanceMemBase -MemoryGB 0)
}

Write-Host ''
Write-Host '=== 实例启动钩子（InstanceHooks）===' -ForegroundColor Cyan

Test-Case '默认钩子：关闭、延迟 8 秒、无动作' {
    $h = New-InstanceHook $null
    Assert-Equal $false $h.Enabled
    Assert-Equal 8 $h.DelaySec
    Assert-Equal 0 @($h.AutoStartApps).Count
    Assert-Equal 0 @($h.PostStartCommands).Count
    Assert-Equal '' $h.PostStartScript
}

Test-Case '哈希表配置归一化' {
    $h = New-InstanceHook @{ Enabled = $true; DelaySec = 3; AutoStartApps = @('a.b', ' c.d '); PostStartCommands = @('input tap 1 2'); PostStartScript = 'hooks\x.ps1' }
    Assert-Equal $true $h.Enabled
    Assert-Equal 3 $h.DelaySec
    Assert-Equal 2 @($h.AutoStartApps).Count
    Assert-Equal 'c.d' @($h.AutoStartApps)[1]
    Assert-Equal 'hooks\x.ps1' $h.PostStartScript
}

Test-Case '延迟秒数边界：负数归 0，超大归 600' {
    Assert-Equal 0 ((New-InstanceHook @{ DelaySec = -5 }).DelaySec)
    Assert-Equal 600 ((New-InstanceHook @{ DelaySec = 99999 }).DelaySec)
}

Test-Case '从哈希表配置存储按实例号取钩子' {
    $store = @{ '1' = @{ Enabled = $true; AutoStartApps = @('de.vpjs.xxyun') } }
    $h = Get-InstanceHookFromStore $store '1'
    Assert-Equal $true $h.Enabled
    Assert-Equal 'de.vpjs.xxyun' @($h.AutoStartApps)[0]
    $none = Get-InstanceHookFromStore $store '4'
    Assert-Equal $false $none.Enabled
}

Test-Case '从 JSON/PSCustomObject 存储取钩子' {
    $store = '{"2":{"Enabled":true,"DelaySec":2,"PostStartCommands":["am start -n a.b/.Main"]}}' | ConvertFrom-Json
    $h = Get-InstanceHookFromStore $store '2'
    Assert-Equal $true $h.Enabled
    Assert-Equal 2 $h.DelaySec
    Assert-Equal 'am start -n a.b/.Main' @($h.PostStartCommands)[0]
}

Test-Case '钩子摘要（关闭 / 已开启）' {
    Assert-Equal '未设置' (Get-InstanceHookSummary (New-InstanceHook $null))
    $h = New-InstanceHook @{ Enabled = $true; AutoStartApps = @('de.vpjs.xxyun'); PostStartScript = 'hooks\x.ps1' }
    Assert-Equal $true ((Get-InstanceHookSummary $h) -like '已开启*')
}

Write-Host ''
Write-Host '=== Get-OvercommitLevel（超配判定）===' -ForegroundColor Cyan

Test-Case '50% -> ok' {
    Assert-Equal 'ok' (Get-OvercommitLevel -EstimatedGB 8 -TotalGB 16)
}

Test-Case '85% -> warn' {
    Assert-Equal 'warn' (Get-OvercommitLevel -EstimatedGB 13.6 -TotalGB 16)
}

Test-Case '超过 100% -> danger' {
    Assert-Equal 'danger' (Get-OvercommitLevel -EstimatedGB 20 -TotalGB 16)
}

Write-Host ''
Write-Host '=== Get-TotalEstimatedGB（总占用估算）===' -ForegroundColor Cyan

Test-Case '两个 6G 实例 -> 15 GB' {
    $rows = @(
        [pscustomobject]@{ GuestGB = 6; Sleeping = $false },
        [pscustomobject]@{ GuestGB = 6; Sleeping = $false }
    )
    Assert-Equal 15 (Get-TotalEstimatedGB -Rows $rows)
}

Test-Case '休眠实例不计入' {
    $rows = @(
        [pscustomobject]@{ GuestGB = 6; Sleeping = $false },
        [pscustomobject]@{ GuestGB = 6; Sleeping = $true }
    )
    Assert-Equal 7.5 (Get-TotalEstimatedGB -Rows $rows)
}

Write-Host ''
Write-Host '=== Test-NewerVersion（版本比较）===' -ForegroundColor Cyan

Test-Case '1.0.0 -> v1.0.1 有新版' {
    Assert-Equal $true (Test-NewerVersion -Local '1.0.0' -Remote 'v1.0.1')
}

Test-Case '1.0.0 -> v1.0.0 无新版' {
    Assert-Equal $false (Test-NewerVersion -Local '1.0.0' -Remote 'v1.0.0')
}

Test-Case '1.1.0 -> v1.0.9 无新版' {
    Assert-Equal $false (Test-NewerVersion -Local '1.1.0' -Remote 'v1.0.9')
}

Test-Case '远程为空 无新版' {
    Assert-Equal $false (Test-NewerVersion -Local '1.0.0' -Remote '')
}

# ---------------- 休眠状态机（以游戏是否在跑为准）----------------
$stNow = [datetime]'2026-11-15 17:00:00'

Test-Case '状态机：游戏在跑 → 不睡' {
    $row = @{ Index = '3'; Script = $true; Sched = $true; Game = $true; UpDone = $stNow.AddHours(6) }
    $r = Get-SleepStage -Row $row -Since $stNow.AddMinutes(-60) -Now $stNow
    Assert-Equal 'wait' "$($r.Action)"
    Assert-Equal 'game-running' "$($r.Reason)"
}

Test-Case '状态机：游戏关闭未确认 -> 先进入确认）' {
    $row = @{ Index = '3'; Script = $true; Sched = $true; Game = $false; UpDone = $stNow.AddHours(6) }
    $r = Get-SleepStage -Row $row -Since $stNow.AddMinutes(-5) -Now $stNow
    Assert-Equal 'gamegone' "$($r.Action)"
}

Test-Case '状态机：开机 20 分钟后游戏已关 → 开始确认' {
    $row = @{ Index = '3'; Script = $true; Sched = $true; Game = $false; UpDone = $stNow.AddHours(6) }
    $r = Get-SleepStage -Row $row -Since $stNow.AddMinutes(-25) -Now $stNow
    Assert-Equal 'gamegone' "$($r.Action)"
}

Test-Case '状态机：游戏关了 1 分钟 → 继续确认' {
    $row = @{ Index = '3'; Script = $true; Sched = $true; Game = $false; UpDone = $stNow.AddHours(6) }
    $r = Get-SleepStage -Row $row -Since $stNow.AddMinutes(-25) -GameGone $stNow.AddMinutes(-1) -Now $stNow
    Assert-Equal 'wait' "$($r.Action)"
}

Test-Case '状态机：游戏关了 5 分钟 → 休眠' {
    $row = @{ Index = '3'; Script = $true; Sched = $true; Game = $false; UpDone = $stNow.AddHours(6) }
    $r = Get-SleepStage -Row $row -Since $stNow.AddMinutes(-25) -GameGone $stNow.AddMinutes(-5) -Now $stNow
    Assert-Equal 'sleep' "$($r.Action)"
}

Test-Case '状态机：上号开关没开 → 完全停用' {
    $row = @{ Index = '3'; Script = $true; Sched = $false; Game = $false; UpDone = $stNow.AddHours(6) }
    $r = Get-SleepStage -Row $row -Since $stNow.AddMinutes(-25) -GameGone $stNow.AddMinutes(-5) -Now $stNow
    Assert-Equal 'idle' "$($r.Action)"
}

Test-Case '状态机：紫孔雀没跑 → 交给存活线' {
    $row = @{ Index = '3'; Script = $false; Sched = $true; Game = $false; UpDone = $stNow.AddHours(6) }
    $r = Get-SleepStage -Row $row -Since $stNow.AddMinutes(-25) -GameGone $stNow.AddMinutes(-5) -Now $stNow
    Assert-Equal 'idle' "$($r.Action)"
}

Test-Case '状态机：没有升级信息 → 不睡' {
    $row = @{ Index = '3'; Script = $true; Sched = $true; Game = $false; UpDone = $null }
    $r = Get-SleepStage -Row $row -Since $stNow.AddMinutes(-25) -GameGone $stNow.AddMinutes(-5) -Now $stNow
    Assert-Equal 'wait' "$($r.Action)"
    Assert-Equal 'no-upgrade' "$($r.Reason)"
}

Test-Case '状态机：升级只有 50 分钟 → 不睡' {
    $row = @{ Index = '3'; Script = $true; Sched = $true; Game = $false; UpDone = $stNow.AddMinutes(50) }
    $r = Get-SleepStage -Row $row -Since $stNow.AddMinutes(-25) -GameGone $stNow.AddMinutes(-5) -Now $stNow
    Assert-Equal 'wait' "$($r.Action)"
    Assert-Equal 'too-short' "$($r.Reason)"
}

Test-Case '解析：去掉 LOG 段后 MEM 不能吞掉 SCH' {
    # 采集不再输出 LOG，如果 MEM 仍以 LOG 为结束标记，会把 SCH 一起吞进去导致 base64 解码失败
    $probe = "READY`nSCRIPT`n1234`nGAME`n`nINST`npackage:/x`nSEP`n   0:01 nemuinit`nROOT`nuid=0`nMEM`nSGVsbG8=`nSCH`nupgrade_time_scheduling`": `"1`""
    $b64 = ''
    if ($probe -match '(?s)MEM\s*(.*?)(?:SCH|$)') { $b64 = $Matches[1].Trim() }
    Assert-Equal 'SGVsbG8=' $b64
    Assert-Equal 'Hello' ([System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($b64)))
}

Test-Case '解析：SCH 段能单独取到上号开关' {
    $probe = "MEM`nSGVsbG8=`nSCH`nupgrade_time_scheduling`": `"1`""
    $sched = $false
    if ($probe -match 'upgrade_time_scheduling"\s*:\s*"([01])"') { $sched = ($Matches[1] -eq '1') }
    Assert-Equal $true $sched
}

Test-Case '状态机：没有起始时间 -> 直接进入确认' {
    $row = @{ Index = '9'; Script = $true; Sched = $true; Game = $false; UpDone = $stNow.AddHours(6) }
    $r = Get-SleepStage -Row $row -Since $null -GameGone $null -Now $stNow
    Assert-Equal 'gamegone' "$($r.Action)"
}

Test-Case '状态机：登记满 20 分钟且游戏已关 3 分钟 → 休眠' {
    $row = @{ Index = '9'; Script = $true; Sched = $true; Game = $false; UpDone = $stNow.AddHours(6) }
    $r = Get-SleepStage -Row $row -Since $stNow.AddMinutes(-25) -GameGone $stNow.AddMinutes(-4) -Now $stNow
    Assert-Equal 'sleep' "$($r.Action)"
}

Test-Case '状态机：游戏状态读不到（未知）→ 不睡' {
    $row = @{ Index = '3'; Script = $true; Sched = $true; Game = $null; UpDone = $stNow.AddHours(6) }
    $r = Get-SleepStage -Row $row -Since $stNow.AddMinutes(-25) -GameGone $stNow.AddMinutes(-5) -Now $stNow
    Assert-Equal 'wait' "$($r.Action)"
    Assert-Equal 'game-unknown' "$($r.Reason)"
}

Write-Host ''
Test-Case '后台休眠关闭时：游戏在跑 → 不睡' {
    $row = @{ Index = '2'; Script = $true; Sched = $true; Game = $true; UpDone = $stNow.AddHours(6) }
    $r = Get-SleepStage -Row $row -Since $stNow.AddHours(-2) -Now $stNow `
        -AllowBackground $false -GameForeground $false -IdleSince $stNow.AddMinutes(-30)
    Assert-Equal 'wait' "$($r.Action)"
    Assert-Equal 'game-running' "$($r.Reason)"
}

Test-Case '游戏在前台 → 绝不睡' {
    $row = @{ Index = '2'; Script = $true; Sched = $true; Game = $true; UpDone = $stNow.AddHours(6) }
    $r = Get-SleepStage -Row $row -Since $stNow.AddHours(-2) -Now $stNow `
        -AllowBackground $true -GameForeground $true -IdleSince $stNow.AddMinutes(-30)
    Assert-Equal 'wait' "$($r.Action)"
    Assert-Equal 'game-foreground' "$($r.Reason)"
}

Test-Case '游戏在后台但空闲不够久 → 继续等' {
    $row = @{ Index = '2'; Script = $true; Sched = $true; Game = $true; UpDone = $stNow.AddHours(6) }
    $r = Get-SleepStage -Row $row -Since $stNow.AddHours(-2) -Now $stNow `
        -AllowBackground $true -GameForeground $false -IdleSince $stNow.AddMinutes(-3) -IdleMin 10
    Assert-Equal 'wait' "$($r.Action)"
}

Test-Case '后台空闲够久 + 升级时间合法 → 休眠' {
    $row = @{ Index = '2'; Script = $true; Sched = $true; Game = $true; UpDone = $stNow.AddHours(6) }
    $r = Get-SleepStage -Row $row -Since $stNow.AddHours(-2) -Now $stNow `
        -AllowBackground $true -GameForeground $false -IdleSince $stNow.AddMinutes(-12) -IdleMin 10
    Assert-Equal 'sleep' "$($r.Action)"
}

Test-Case '后台空闲够久但升级快完成 → 不睡' {
    $row = @{ Index = '2'; Script = $true; Sched = $true; Game = $true; UpDone = $stNow.AddMinutes(40) }
    $r = Get-SleepStage -Row $row -Since $stNow.AddHours(-2) -Now $stNow `
        -AllowBackground $true -GameForeground $false -IdleSince $stNow.AddMinutes(-12) -IdleMin 10
    Assert-Equal 'wait' "$($r.Action)"
}


Test-Case '前台包名判断：游戏包 → 是游戏在前台' {
    Assert-Equal 'True' "$(Test-IsGamePackage -Foreground 'com.supercell.clashofclans' -Packages 'com.tencent.tmgp.supercell.clashofclans com.supercell.clashofclans')"
}

Test-Case '前台包名判断：脚本包 → 不算游戏前台' {
    Assert-Equal 'False' "$(Test-IsGamePackage -Foreground 'com.coc.zkqcode' -Packages 'com.supercell.clashofclans')"
}

Test-Case '前台包名判断：取不到 → 不算游戏前台' {
    Assert-Equal 'False' "$(Test-IsGamePackage -Foreground '' -Packages 'com.supercell.clashofclans')"
}
Test-Case '多号同时等：取最早完成的那个' {
    $now = [int64](([datetime]::UtcNow - (New-Object datetime 1970,1,1,0,0,0,([DateTimeKind]::Utc))).TotalSeconds)
    $json = '{"NextUpgrade1":"{\"name\":\"早的\",\"lvl\":1,\"completionTs\":' + ($now + 3600) + '}","accountNumber":"2","NextUpgrade2":"{\"name\":\"晚的\",\"lvl\":2,\"completionTs\":' + ($now + 7200) + '}"}'
    $u = Get-UpgradeFromMemoryJson -Text $json
    Assert-Equal '早的' "$($u.Name)"
}

Test-Case '多号同时等：当前号是晚的那个，也取最早的' {
    $now = [int64](([datetime]::UtcNow - (New-Object datetime 1970,1,1,0,0,0,([DateTimeKind]::Utc))).TotalSeconds)
    $json = '{"NextUpgrade1":"{\"name\":\"早的\",\"lvl\":1,\"completionTs\":' + ($now + 3600) + '}","accountNumber":"1","NextUpgrade2":"{\"name\":\"晚的\",\"lvl\":2,\"completionTs\":' + ($now + 7200) + '}"}'
    $u = Get-UpgradeFromMemoryJson -Text $json
    Assert-Equal '早的' "$($u.Name)"
}

Test-Case '升级全部过期：返回当前号那条做兜底' {
    $json = '{"NextUpgrade1":"{\"name\":\"旧\",\"lvl\":1,\"completionTs\":1000}","accountNumber":"1"}'
    $u = Get-UpgradeFromMemoryJson -Text $json
    Assert-Equal '旧' "$($u.Name)"
}
# ---------------- 休眠记录对齐（防误撤销）----------------
$nowT = Get-Date
$entryFresh = [pscustomobject]@{ Index = '2'; Since = $nowT.AddMinutes(-5).ToString('yyyy-MM-ddTHH:mm:ss'); ShutdownAt = $nowT.AddMinutes(-5).ToString('yyyy-MM-ddTHH:mm:ss') }
$entryJustShut = [pscustomobject]@{ Index = '2'; Since = $nowT.AddSeconds(-10).ToString('yyyy-MM-ddTHH:mm:ss'); ShutdownAt = $nowT.AddSeconds(-10).ToString('yyyy-MM-ddTHH:mm:ss') }

Test-Case '休眠对齐：关机宽限期内跳过（adb 还报在线也不算运行）' {
    $row = [pscustomobject]@{ Index = '2'; Online = $true; At = $nowT }
    $r = Get-StaleSleepDecision -Row $row -Entry $entryJustShut -Now $nowT
    Assert-Equal 'skip' "$($r.Action)"
}

Test-Case '休眠对齐：宽限期后在线且数据新鲜 → 记一次' {
    $row = [pscustomobject]@{ Index = '2'; Online = $true; At = $nowT }
    $r = Get-StaleSleepDecision -Row $row -Entry $entryFresh -Now $nowT
    Assert-Equal 'count' "$($r.Action)"
}

Test-Case '休眠对齐：连续 3 次确认才撤销' {
    $row = [pscustomobject]@{ Index = '2'; Online = $true; At = $nowT }
    $r1 = Get-StaleSleepDecision -Row $row -Entry $entryFresh -Now $nowT -Hits 0
    $r2 = Get-StaleSleepDecision -Row $row -Entry $entryFresh -Now $nowT -Hits ([int]$r1.Hits)
    $r3 = Get-StaleSleepDecision -Row $row -Entry $entryFresh -Now $nowT -Hits ([int]$r2.Hits)
    Assert-Equal 'revoke' "$($r3.Action)"
}

Test-Case '休眠对齐：采集数据过期 → 清零不撤销' {
    $row = [pscustomobject]@{ Index = '2'; Online = $true; At = $nowT.AddSeconds(-120) }
    $r = Get-StaleSleepDecision -Row $row -Entry $entryFresh -Now $nowT -Hits 2
    Assert-Equal 'reset' "$($r.Action)"
}

Test-Case '休眠对齐：离线 → 清零' {
    $row = [pscustomobject]@{ Index = '2'; Online = $false; At = $nowT }
    $r = Get-StaleSleepDecision -Row $row -Entry $entryFresh -Now $nowT -Hits 2
    Assert-Equal 'reset' "$($r.Action)"
}

Test-Case '休眠对齐：没有实例行 → 清零' {
    $r = Get-StaleSleepDecision -Row $null -Entry $entryFresh -Now $nowT -Hits 2
    Assert-Equal 'reset' "$($r.Action)"
}

# ---------------- 防函数重名回归 ----------------
Test-Case 'lib 模块没有新增重名函数（白名单除外）' {
    $allowed = @('New-RingCell', 'Update-Ui', 'Set-View', 'Write-Diag')
    $seen = @{}
    $dups = @()
    Get-ChildItem (Join-Path $root 'lib') -Filter '*.ps1' | ForEach-Object {
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($_.FullName, [ref]$null, [ref]$null)
        $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true) | ForEach-Object {
            $nm = $_.Name
            if ($seen.ContainsKey($nm)) {
                if ($allowed -notcontains $nm) { $dups += $nm }
            } else { $seen[$nm] = $_.Extent.File }
        }
    }
    if ($dups.Count -gt 0) { return ("重名函数: " + (($dups | Select-Object -Unique) -join ', ')) }
    return $true
}

Test-Case '休眠判定调用的是 Test-IsGamePackage（防再次绑参失败）' {
    $txt = Get-Content (Join-Path $root 'lib\20-actions.ps1') -Raw -Encoding UTF8
    if ($txt -match 'Test-GameForeground\s+-Foreground') { return '20-actions 仍在用 Test-GameForeground -Foreground（会被 63-res 覆盖）' }
    if ($txt -notmatch 'Test-IsGamePackage') { return '20-actions 没调用 Test-IsGamePackage' }
    return $true
}
Write-Host ('=' * 50)
if ($script:fail -eq 0) {
    Write-Host ("全部通过：{0} 个测试" -f $script:pass) -ForegroundColor Green
    exit 0
} else {
    Write-Host ("通过 {0} 个，失败 {1} 个" -f $script:pass, $script:fail) -ForegroundColor Red
    Write-Host '失败列表：' -ForegroundColor Red
    $script:failures | ForEach-Object { Write-Host "  - $_" -ForegroundColor Red }
    exit 1
}
