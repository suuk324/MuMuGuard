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
Write-Host '=== Test-IsWaitingLog（是否只是在等升级）===' -ForegroundColor Cyan

$waitingLines = @(
    '2026-11-13 18:00:01 账号1，升级中：箭塔，剩余时间：1小时20分钟'
    '2026-11-13 18:00:04 账号1，升级中：箭塔，剩余时间：1小时19分钟'
    '2026-11-13 18:00:07 账号1，升级中：箭塔，剩余时间：1小时19分钟'
    '2026-11-13 18:00:10 账号1，升级中：箭塔，剩余时间：1小时18分钟'
    '2026-11-13 18:00:13 账号1，升级中：箭塔，剩余时间：1小时18分钟'
    '2026-11-13 18:00:16 账号1，升级中：箭塔，剩余时间：1小时17分钟'
)

Test-Case '全是升级倒计时 -> true' {
    Assert-Equal $true (Test-IsWaitingLog -Lines $waitingLines)
}

$workingLines = @(
    '2026-11-13 18:00:01 账号1，主世界搜索中... 第1/15局'
    '2026-11-13 18:00:04 账号1，已找到：对战页面,坐标：181, 331'
    '2026-11-13 18:00:07 账号1，进攻需等待冷却'
    '2026-11-13 18:00:10 账号1，主世界搜索中... 第2/15局'
    '2026-11-13 18:00:13 账号1，已找到：对战页面,坐标：181, 331'
    '2026-11-13 18:00:16 账号1，进攻需等待冷却'
)

Test-Case '在打资源 -> false' {
    Assert-Equal $false (Test-IsWaitingLog -Lines $workingLines)
}

Test-Case '混合（末尾出现干活）-> false' {
    $mixed = @($waitingLines) + @('2026-11-13 18:00:19 账号1，主世界搜索中... 第3/15局')
    Assert-Equal $false (Test-IsWaitingLog -Lines $mixed)
}

Test-Case '日志太少 -> false（不冒险）' {
    $few = @($waitingLines[0], $waitingLines[1], $waitingLines[2])
    Assert-Equal $false (Test-IsWaitingLog -Lines $few)
}

Test-Case '空数组 -> false' {
    Assert-Equal $false (Test-IsWaitingLog -Lines @())
}

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
Write-Host '=== Get-SleepDecision（是否该休眠）===' -ForegroundColor Cyan

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

Test-Case '条件齐全 -> 可休眠（返回空串）' {
    $d = Get-SleepDecision -Row (New-TestRow) @common
    Assert-Equal '' $d
}

Test-Case '总开关关闭 -> auto-sleep-off' {
    $p = $common.Clone(); $p.AutoSleep = $false
    Assert-Equal 'auto-sleep-off' (Get-SleepDecision -Row (New-TestRow) @p)
}

Test-Case '看护未开 -> guard-off' {
    $p = $common.Clone(); $p.GuardRunning = $false
    Assert-Equal 'guard-off' (Get-SleepDecision -Row (New-TestRow) @p)
}

Test-Case '检测已暂停 -> detect-off' {
    $p = $common.Clone(); $p.DetectOff = @('3')
    Assert-Equal 'detect-off' (Get-SleepDecision -Row (New-TestRow) @p)
}

Test-Case '已在休眠列表 -> already-sleeping' {
    $p = $common.Clone(); $p.SleepingIndexes = @('3')
    Assert-Equal 'already-sleeping' (Get-SleepDecision -Row (New-TestRow) @p)
}

Test-Case '脚本没跑 -> script-not-running' {
    Assert-Equal 'script-not-running' (Get-SleepDecision -Row (New-TestRow @{ Script = $false }) @common)
}

Test-Case '不在等待状态 -> not-waiting' {
    Assert-Equal 'not-waiting' (Get-SleepDecision -Row (New-TestRow @{ Waiting = $false }) @common)
}

Test-Case '升级时间上号未开 -> scheduling-off' {
    Assert-Equal 'scheduling-off' (Get-SleepDecision -Row (New-TestRow @{ Sched = $false }) @common)
}

Test-Case '没有升级数据 -> no-upgrade' {
    Assert-Equal 'no-upgrade' (Get-SleepDecision -Row (New-TestRow @{ UpDone = $null }) @common)
}

Test-Case '离唤醒不到2分钟 -> too-late' {
    $row = New-TestRow @{ UpDone = $tNow.AddMinutes(5) }
    Assert-Equal 'too-late' (Get-SleepDecision -Row $row @common)
}

Test-Case '升级太远（超20小时）-> too-far' {
    $row = New-TestRow @{ UpDone = $tNow.AddHours(30) }
    Assert-Equal 'too-far' (Get-SleepDecision -Row $row @common)
}

Test-Case '索引缺失 -> no-index' {
    Assert-Equal 'no-index' (Get-SleepDecision -Row (New-TestRow @{ Index = '-' }) @common)
}

Test-Case '总开关关了应优先于其他条件' {
    $p = $common.Clone(); $p.AutoSleep = $false; $p.DetectOff = @('3')
    Assert-Equal 'auto-sleep-off' (Get-SleepDecision -Row (New-TestRow) @p)
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
Write-Host '=== Get-InstanceMemBase（内存刻度）===' -ForegroundColor Cyan

Test-Case '6G 实例 -> 8644' {
    Assert-Equal 8644 (Get-InstanceMemBase -MemoryGB 6)
}

Test-Case '4G 实例 -> 6596' {
    Assert-Equal 6596 (Get-InstanceMemBase -MemoryGB 4)
}

Test-Case '未知内存 -> 兜底 9216' {
    Assert-Equal 9216 (Get-InstanceMemBase -MemoryGB 0)
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
Write-Host ''
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