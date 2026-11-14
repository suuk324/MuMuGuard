#Requires -Version 5.1
#
# 纯函数：不依赖 WPF、不读全局状态，可直接单元测试
# 主程序与 adb 后台线程（独立 runspace）都 dot-source 本文件，保证逻辑只有一份
## ---------------- 纯函数（无副作用，可单元测试）----------------

# 把"剩余时间"格式化成 1h25m / 40m；已过期返回空串
function Get-RemainingLabel {
    param([object]$DoneAt, [datetime]$Now)
    if ($null -eq $DoneAt) { return '' }
    $done = $null
    try { $done = [datetime]$DoneAt } catch { return '' }
    $left = $done - $Now
    if ($left.TotalSeconds -le 0) { return '' }
    if ($left.TotalHours -ge 1) {
        return ('{0}h{1:D2}m' -f [int][math]::Floor($left.TotalHours), $left.Minutes)
    }
    return ('{0}m' -f [int][math]::Ceiling($left.TotalMinutes))
}

# 内存百分比：私有内存 / 阈值，裁剪到 0..100
function Get-MemPercent {
    param([int]$PrivateMB, [int]$BaseMB)
    if ($BaseMB -le 0) { return 0 }
    $p = [math]::Round($PrivateMB / $BaseMB * 100, 0)
    if ($p -lt 0) { return 0 }
    if ($p -gt 100) { return 100 }
    return [int]$p
}

# 判断脚本是否只是在等升级：最后 12 条业务日志全是"升级中…剩余时间"
function Test-IsWaitingLog {
    param([string[]]$Lines)
    if (-not $Lines -or $Lines.Count -lt 5) { return $false }
    $biz = @($Lines | Where-Object { $_ -match '账号\d+[，,]' })
    if ($biz.Count -lt 5) { return $false }
    $tail = @($biz | Select-Object -Last 12)
    foreach ($l in $tail) {
        if ($l -notmatch '升级中.*剩余时间') { return $false }
    }
    return $true
}

# 从 memory.json 文本取出机器人账号对应的下一次升级信息
function Get-UpgradeFromMemoryJson {
    param([string]$Text)
    if (-not $Text) { return $null }
    try { $j = $Text | ConvertFrom-Json -ErrorAction Stop } catch { return $null }
    if ($null -eq $j) { return $null }

    $acc = "$($j.accountNumber)"
    if (-not $acc) { $acc = '1' }
    $raw = $j."NextUpgrade$acc"
    if (-not $raw) { return $null }
    try { $u = $raw | ConvertFrom-Json -ErrorAction Stop } catch { return $null }
    if (-not $u.completionTs) { return $null }

    return [pscustomobject]@{
        Name = "$($u.name)"
        Lvl  = [int]$u.lvl
        Ts   = [int64]$u.completionTs
    }
}

# 该实例此刻是否应该休眠；返回空串表示"不该"，否则返回原因（便于日志）
function Get-SleepDecision {
    param(
        $Row,
        [bool]$AutoSleep,
        [bool]$GuardRunning,
        [double]$LeadMin,
        [double]$MaxHours,
        [double]$MinHours = 0,
        [datetime]$Now,
        [string[]]$DetectOff,
        [string[]]$SleepingIndexes
    )
    if (-not $AutoSleep) { return 'auto-sleep-off' }
    if (-not $GuardRunning) { return 'guard-off' }
    $idx = "$($Row.Index)"
    if ($idx -eq '-' -or $idx -eq '') { return 'no-index' }
    if (@($DetectOff | Where-Object { $_ -ne $null }) -contains $idx) { return 'detect-off' }
    if (@($SleepingIndexes | Where-Object { $_ -ne $null }) -contains $idx) { return 'already-sleeping' }
    if ($Row.Script -ne $true) { return 'script-not-running' }
    if ($Row.Waiting -ne $true) { return 'not-waiting' }
    if ($Row.Sched -ne $true) { return 'scheduling-off' }
    if (-not $Row.UpDone) { return 'no-upgrade' }

    $doneAt = [datetime]$Row.UpDone
    $wakeAt = $doneAt.AddMinutes(-$LeadMin)
    if ($wakeAt -le $Now.AddMinutes(2)) { return 'too-late' }
    if (($doneAt - $Now).TotalHours -gt $MaxHours) { return 'too-far' }
    if ($MinHours -gt 0 -and ($doneAt - $Now).TotalHours -lt $MinHours) { return 'too-short' }
    return ''
}
# 求多个字符串的最长公共前缀（用于压缩实例名，如 "MuMu安卓设备-1" / "MuMu安卓设备-1-1"）
function Get-CommonPrefix {
    param([string[]]$Strings)
    $arr = @($Strings | Where-Object { $_ })
    if ($arr.Count -eq 0) { return '' }
    if ($arr.Count -eq 1) { return '' }
    $prefix = $arr[0]
    foreach ($s in $arr) {
        $n = [math]::Min($prefix.Length, $s.Length)
        $i = 0
        while ($i -lt $n -and $prefix[$i] -eq $s[$i]) { $i++ }
        $prefix = $prefix.Substring(0, $i)
        if (-not $prefix) { return '' }
    }
    return $prefix
}

# 去掉前缀并清理分隔符；结果为空则返回原串
function Get-ShortLabel {
    param([string]$Name, [string]$Prefix)
    if (-not $Name) { return '' }
    $s = $Name
    if ($Prefix -and $s.StartsWith($Prefix)) { $s = $s.Substring($Prefix.Length) }
    $s = $s.Trim()
    $s = $s.TrimStart('-', '_', ' ', '.')
    $s = $s.TrimEnd('-', '_', ' ', '.')
    return $s
}

# 批量生成短名：从公共前缀开始逐字缩短，直到所有名字都还有剩余字符
# 例：MuMu安卓设备-1 / MuMu安卓设备-1-1 / MuMu安卓设备-1-2  ->  1 / 1-1 / 1-2
function Get-ShortLabels {
    param([string[]]$Names)
    $list = @($Names)
    if ($list.Count -eq 0) { return @() }
    if ($list.Count -eq 1) {
        # 单个实例：取最后一段标识（如「MuMu安卓设备-1-1」→「1-1」），避免长名字压到环上
        $n = [string]$list[0]
        $parts = @($n -split '-')
        if ($parts.Count -ge 2) {
            $tail = ($parts | Select-Object -Last 2) -join '-'
            if ($tail.Length -le 8) { return @($tail) }
        }
        if ($n.Length -le 6) { return @($n) }
        return @(($n).Substring(0, 5) + '…')
    }

    $prefix = Get-CommonPrefix -Strings $list
    for ($len = $prefix.Length; $len -ge 0; $len--) {
        $p = $prefix.Substring(0, $len)
        $outs = @()
        $ok = $true
        foreach ($n in $list) {
            $s = Get-ShortLabel -Name $n -Prefix $p
            if (-not $s) { $ok = $false; break }
            $outs += $s
        }
        if ($ok) {
            # 缩短后如果还是有重名，继续缩短
            $distinct = @($outs | Select-Object -Unique)
            if ($distinct.Count -eq $outs.Count) { return $outs }
        }
    }
    return $list
}

# 根据实例数量决定紧凑面板用环形还是列表
function Get-CompactMode {
    param([int]$Count)
    if ($Count -le 5) { return 'rings' }
    return 'list'
}

# 环形模式下每个环的缩放比例（数量越多越小）
function Get-RingScale {
    param([int]$Count)
    switch ($Count) {
        1 { return 1.20 }
        2 { return 1.00 }
        3 { return 0.86 }
        4 { return 0.74 }
        5 { return 0.64 }
        default { return 0.58 }
    }
}

# 估算已开启实例的总内存占用（GB），用于超配预警
function Get-TotalEstimatedGB {
    param($Rows)
    $sum = 0.0
    foreach ($r in @($Rows)) {
        if ($null -eq $r) { continue }
        if ($r.Sleeping) { continue }
        if ($r.GuestGB -and $r.GuestGB -gt 0) {
            $sum += [double]$r.GuestGB + 1.5
        } elseif ($r.Private -and $r.Private -gt 0) {
            $sum += [double]$r.Private / 1024.0
        }
    }
    return [math]::Round($sum, 1)
}

# 超配等级：ok / warn / danger
function Get-OvercommitLevel {
    param([double]$EstimatedGB, [double]$TotalGB)
    if ($TotalGB -le 0) { return 'ok' }
    $ratio = $EstimatedGB / $TotalGB
    if ($ratio -ge 1.0) { return 'danger' }
    if ($ratio -ge 0.8) { return 'warn' }
    return 'ok'
}

# 版本比较：v1.0.0 < v1.0.1 < v1.1.0；返回 $true 表示 Remote 更新
function Test-NewerVersion {
    param([string]$Local, [string]$Remote)
    $clean = { param($v) ($v -replace '^[vV]', '').Trim() }
    $l = & $clean $Local
    $r = & $clean $Remote
    if (-not $r) { return $false }
    if (-not $l) { return $true }
    try {
        return ([version]$r -gt [version]$l)
    } catch {
        return ($r -ne $l)
    }
}
# 环的满刻度：客户机内存(GB) + 图形/转译固定开销
function Get-InstanceMemBase {
    param([int]$MemoryGB)
    if ($MemoryGB -le 0) { return 9216 }
    return ($MemoryGB * 1024 + 2500)
}