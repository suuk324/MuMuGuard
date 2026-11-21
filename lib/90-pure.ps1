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


# 从 memory.json 文本取出机器人账号对应的下一次升级信息
function Get-UpgradeFromMemoryJson {
    param([string]$Text)
    if (-not $Text) { return $null }
    try { $j = $Text | ConvertFrom-Json -ErrorAction Stop } catch { return $null }
    if ($null -eq $j) { return $null }

    # 一模拟器多号时，memory.json 会同时存在 NextUpgrade1 / NextUpgrade2 …
    # 只看当前登录号可能拿到较晚的那个，导致睡过头，所以取所有号里最快的。
    $nowTs = [int64](([datetime]::UtcNow - (New-Object datetime 1970,1,1,0,0,0,([DateTimeKind]::Utc))).TotalSeconds)
    $best = $null
    $accBest = $null
    $acc = "$($j.accountNumber)"
    if (-not $acc) { $acc = '1' }
    foreach ($p in $j.PSObject.Properties) {
        if ($p.Name -notmatch '^NextUpgrade(\d+)$') { continue }
        $num = $Matches[1]
        $raw = $p.Value
        if (-not $raw) { continue }
        try { $u = $raw | ConvertFrom-Json -ErrorAction Stop } catch { continue }
        if (-not $u.completionTs) { continue }
        $item = [pscustomobject]@{ Name = "$($u.name)"; Lvl = [int]$u.lvl; Ts = [int64]$u.completionTs }
        # 当前登录号的那条单独留一份，作为全部过期的兜底
        if ($num -eq $acc) { $accBest = $item }
        # 只考虑还没完成的；取最早完成的那个
        if ($item.Ts -le $nowTs) { continue }
        if (-not $best -or $item.Ts -lt $best.Ts) { $best = $item }
    }
    if ($best) { return $best }
    if ($accBest) { return $accBest }
    return $null

    return [pscustomobject]@{
        Name = "$($u.name)"
        Lvl  = [int]$u.lvl
        Ts   = [int64]$u.completionTs
    }
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
    # 少于 3 台时不做公共前缀压缩：2 台时压缩只会让人看不懂（国际服 → 际服）
    if ($list.Count -lt 3) { return @($list | ForEach-Object { [string]$_ }) }

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
    # 去掉 v 前缀与 -beta/-rc 之类的预发布后缀，否则 [version] 解析会失败退化成字符串比较
    $clean = { param($v) (($v -replace '^[vV]', '') -replace '[-+].*$', '').Trim() }
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
# 从 MuMu 进程命令行解析实例编号
#   MuMuNxDevice:    -v 4 --vm MuMuPlayer-12.0-4
#   MuMuVMMHeadless: --comment MuMuPlayer-12.0-4 --startvm <uuid>
# 优先用 --comment；兜底用 --startvm 的 uuid 末段（本机实测末段就是实例号）
function Get-InstanceIndexFromCommandLine {
    param([string]$CommandLine)
    if (-not $CommandLine) { return '' }
    if ($CommandLine -match 'MuMuPlayer-[\d\.]+-(\d+)') { return $Matches[1] }
    if ($CommandLine -match '--startvm\s+[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-([0-9a-fA-F]{12})') {
        $n = 0
        $ok = [int]::TryParse($Matches[1], [System.Globalization.NumberStyles]::HexNumber, [System.Globalization.CultureInfo]::InvariantCulture, [ref]$n)
        if ($ok -and $n -ge 0) { return [string]$n }
    }
    return ''
}

# 实例启动钩子（InstanceHooks）的默认结构与归一化（纯逻辑，便于单测）
# 每个实例可配置：启用、延迟秒数、自动启动的应用包名、启动后执行的 adb 命令、启动后执行的脚本
function New-InstanceHook {
    param($Saved)
    $h = [ordered]@{
        Enabled           = $false
        DelaySec          = 8
        AutoStartApps     = @()
        PostStartCommands = @()
        PostStartScript   = ''
    }
    if ($null -eq $Saved) { return $h }
    $read = {
        param($name)
        try {
            if ($Saved -is [System.Collections.IDictionary]) {
                if ($Saved.Contains($name)) { return $Saved[$name] }
            } else {
                $p = $Saved.PSObject.Properties[$name]
                if ($p) { return $p.Value }
            }
        } catch { }
        return $null
    }
    $en = & $read 'Enabled'
    if ($null -ne $en) { $h.Enabled = [bool]$en }
    $dl = & $read 'DelaySec'
    if ($null -ne $dl) { try { $h.DelaySec = [Math]::Max(0, [Math]::Min(600, [int]$dl)) } catch { } }
    $apps = & $read 'AutoStartApps'
    if ($apps) {
        $h.AutoStartApps = @($apps | ForEach-Object { "$_".Trim() } | Where-Object { $_ })
    }
    $cmds = & $read 'PostStartCommands'
    if ($cmds) {
        $h.PostStartCommands = @($cmds | ForEach-Object { "$_" } | Where-Object { "$_".Trim() })
    }
    $sc = & $read 'PostStartScript'
    if ($sc) { $h.PostStartScript = "$sc".Trim() }
    return $h
}

# 从可能为 PSCustomObject/哈希表/JSON 的配置里取出某个实例的钩子（纯逻辑）
function Get-InstanceHookFromStore {
    param($Store, [string]$Index)
    $found = $null
    if ($null -ne $Store) {
        try {
            if ($Store -is [System.Collections.IDictionary]) {
                foreach ($k in $Store.Keys) { if ("$k" -eq "$Index") { $found = $Store[$k]; break } }
            } else {
                foreach ($p in $Store.PSObject.Properties) { if ($p.Name -eq "$Index") { $found = $p.Value; break } }
            }
        } catch { }
    }
    return (New-InstanceHook $found)
}

# 钩子内容摘要（详情页/日志显示用）
function Get-InstanceHookSummary {
    param($Hook)
    if (-not $Hook -or -not $Hook.Enabled) { return '未设置' }
    $parts = @()
    if ($Hook.AutoStartApps -and @($Hook.AutoStartApps).Count -gt 0) { $parts += ('启动 ' + @($Hook.AutoStartApps).Count + ' 个应用') }
    if ($Hook.PostStartCommands -and @($Hook.PostStartCommands).Count -gt 0) { $parts += (@($Hook.PostStartCommands).Count.ToString() + ' 条命令') }
    if ($Hook.PostStartScript) { $parts += '脚本' }
    if ($parts.Count -eq 0) { return '已开启（无动作）' }
    return ('已开启 · ' + ($parts -join ' / '))
}

# 环的满刻度：客户机内存(GB) + 图形/转译固定开销
# 新引擎的 guest 内存在 MuMuVMMHeadless 里，实测 6G 实例总私有约 8.9~9.0G，所以开销按 3000 算
function Get-InstanceMemBase {
    param([int]$MemoryGB)
    if ($MemoryGB -le 0) { return 9216 }
    return ($MemoryGB * 1024 + 3000)
}
# 升级休眠状态机（纯逻辑，便于单测）
# 返回 @{ Action = 'wait'|'gamegone'|'sleep'|'idle'; Reason = '...' }
# 前台包名是否属于游戏（PkgGame 可能是空格分隔的多个包）
# 注意：这里必须叫 Test-IsGamePackage，不能叫 Test-GameForeground——
#       63-res.ps1 里也有一个 Test-GameForeground(实例号)，加载顺序会让它覆盖同名函数，
#       之前就因此把休眠判定的前台保护弄失效了（20-actions 绑参失败被吞）。
function Test-IsGamePackage {
    param([string]$Foreground, [string]$Packages)
    if (-not $Foreground -or -not $Packages) { return $false }
    $fg = $Foreground.Trim().ToLower()
    if (-not $fg) { return $false }
    foreach ($p in ($Packages -split '\s+')) {
        $pp = $p.Trim().ToLower()
        if ($pp -and $fg -eq $pp) { return $true }
    }
    return $false
}

# 休眠记录对齐判定（纯逻辑，便于单测）
# 返回 @{ Action = 'skip'|'reset'|'count'|'revoke'; Hits = n; Reason = '...' }
#   skip  : 刚关机，处于宽限期（adb 还停留在关机前的在线状态）→ 不判定
#   reset : 实例不在线或采集数据过期 → 不算运行，计数清零
#   count : 在线且数据新鲜 → 记一次，等下一次巡检
#   revoke: 连续 NeedHits 次确认在运行 → 撤销休眠记录
function Get-StaleSleepDecision {
    param(
        [object]$Row,
        [object]$Entry,
        [datetime]$Now,
        [int]$Hits = 0,
        [double]$GraceSec = 90,
        [double]$FreshSec = 60,
        [int]$NeedHits = 3
    )
    $h = [int]$Hits
    if (-not $Row) { return @{ Action = 'reset'; Hits = 0; Reason = 'no-row' } }
    $idx = "$($Row.Index)"
    if (-not $idx -or $idx -eq '-') { return @{ Action = 'reset'; Hits = 0; Reason = 'no-index' } }
    # 关机宽限期从记录里的 ShutdownAt 算；老记录没有这个字段就退回 Since（老记录通常早已过宽限期）
    $shut = $null
    try {
        if ($Entry -and ($Entry.PSObject.Properties.Name -contains 'ShutdownAt') -and "$($Entry.ShutdownAt)") {
            $shut = [datetime]::Parse("$($Entry.ShutdownAt)")
        } elseif ($Entry -and ($Entry.PSObject.Properties.Name -contains 'Since') -and "$($Entry.Since)") {
            $shut = [datetime]::Parse("$($Entry.Since)")
        }
    } catch { }
    if ($shut -and $GraceSec -gt 0 -and ($Now - $shut).TotalSeconds -lt $GraceSec) {
        return @{ Action = 'skip'; Hits = $h; Reason = 'grace' }
    }
    $online = ($Row.Online -eq $true)
    $fresh = $false
    try {
        if ($Row.At) { $fresh = (((($Now - [datetime]$Row.At).TotalSeconds)) -le $FreshSec) }
    } catch { }
    if (-not $online) { return @{ Action = 'reset'; Hits = 0; Reason = 'offline' } }
    if (-not $fresh) { return @{ Action = 'reset'; Hits = 0; Reason = 'stale-data' } }
    $h++
    if ($h -ge $NeedHits) { return @{ Action = 'revoke'; Hits = $h; Reason = 'running-confirmed' } }
    return @{ Action = 'count'; Hits = $h; Reason = 'running' }
}

function Get-SleepStage {
    param(
        $Row,
        [object]$Since = $null,
        [object]$GameGone = $null,
        [datetime]$Now,
        [double]$GameGoneMin = 3,
        [double]$LeadMin = 10,
        [double]$MinHours = 1,
        [double]$MaxHours = 168,
        [bool]$AutoSleep = $true,
        [bool]$GuardRunning = $true,
        [string[]]$DetectOff = @(),
        [string[]]$SleepingIndexes = @(),
        [bool]$AllowBackground = $false,
        [double]$IdleMin = 10,
        [bool]$GameForeground = $false,
        [object]$IdleSince = $null
    )
    if (-not $AutoSleep) { return @{ Action = 'idle'; Reason = 'auto-sleep-off' } }
    if (-not $GuardRunning) { return @{ Action = 'idle'; Reason = 'guard-off' } }
    $idx = "$($Row.Index)"
    if ($idx -eq '-' -or $idx -eq '') { return @{ Action = 'idle'; Reason = 'no-index' } }
    if (@($DetectOff | Where-Object { $_ }) -contains $idx) { return @{ Action = 'idle'; Reason = 'detect-off' } }
    if (@($SleepingIndexes | Where-Object { $_ }) -contains $idx) { return @{ Action = 'idle'; Reason = 'already-sleeping' } }

    # 线二只在「升级时间上号」开启时工作
    if ($Row.Sched -ne $true) { return @{ Action = 'idle'; Reason = 'scheduling-off' } }
    if ($Row.Script -ne $true) { return @{ Action = 'idle'; Reason = 'script-not-running' } }

    if (-not $Since) { $Since = $Now }

    # 游戏进程在，但可能只是被脚本切到了后台
    if ($Row.Game -eq $true) {
        if (-not $AllowBackground) { return @{ Action = 'wait'; Reason = 'game-running' } }
        # 游戏在前台 = 正在玩，绝不睡
        if ($GameForeground) { return @{ Action = 'wait'; Reason = 'game-foreground' } }
        # 后台空闲要连续够久才算「脚本在等」
        if (-not $IdleSince) { return @{ Action = 'wait'; Reason = 'idle-start' } }
        $idleNow = ($Now - [datetime]$IdleSince).TotalMinutes
        if ($idleNow -lt $IdleMin) {
            return @{ Action = 'wait'; Reason = ('background-idle {0:N0}/{1}min' -f $idleNow, $IdleMin) }
        }
    } elseif ($Row.Game -ne $false) {
        # 游戏状态读不到（采集异常）也不能睡，宁可晚睡
        return @{ Action = 'wait'; Reason = 'game-unknown' }
    } else {
        # 游戏已退出：先开始计确认时间
        if (-not $GameGone) { return @{ Action = 'gamegone'; Reason = 'start-confirm' } }
        if (($Now - [datetime]$GameGone).TotalMinutes -lt $GameGoneMin) {
            return @{ Action = 'wait'; Reason = ('confirming {0}/{1}min' -f [int]($Now - [datetime]$GameGone).TotalMinutes, [int]$GameGoneMin) }
        }
    }
    if (-not $Row.UpDone) { return @{ Action = 'wait'; Reason = 'no-upgrade' } }
    $doneAt = [datetime]$Row.UpDone
    $wakeAt = $doneAt.AddMinutes(-$LeadMin)
    if ($wakeAt -le $Now.AddMinutes(2)) { return @{ Action = 'wait'; Reason = 'too-late' } }
    if (($doneAt - $Now).TotalHours -gt $MaxHours) { return @{ Action = 'wait'; Reason = 'too-far' } }
    if ($MinHours -gt 0 -and ($doneAt - $Now).TotalHours -lt $MinHours) { return @{ Action = 'wait'; Reason = 'too-short' } }
    return @{ Action = 'sleep'; Reason = 'ok' }
}
# ---------------- 实例发现 / 唤醒通知（纯函数，可单测） ----------------

# 只把「运行中」的实例放进采集清单；没在跑的实例不去查，避免 MuMuManager 卡死
function Get-RunningDeviceList($Instances) {
    $out = @()
    foreach ($ic in @($Instances)) {
        if (-not $ic) { continue }
        $running = $false
        if ($ic.PSObject.Properties.Name -contains 'Running') { $running = ($ic.Running -eq $true) }
        if (-not $running) { continue }
        $idx = "$($ic.Index)"
        if (-not $idx -or $idx -eq '-') { continue }
        $port = 0
        if ($ic.PSObject.Properties.Name -contains 'AdbPort') {
            try { $port = [int]$ic.AdbPort } catch { $port = 0 }
        }
        $out += [pscustomobject]@{ Index = $idx; Port = $port }
    }
    return $out
}

# 解析唤醒器写的 wake-notify.json：支持 { items: [...] } 或裸数组；去重、丢弃非法项
function ConvertFrom-WakeNotifyJson([string]$Json) {
    if (-not $Json -or $Json.Trim() -eq '') { return @() }
    $j = $null
    try { $j = $Json | ConvertFrom-Json } catch { return @() }
    if (-not $j) { return @() }
    $raw = @()
    if ($j.PSObject.Properties.Name -contains 'items') { $raw = @($j.items) }
    elseif ($j -is [System.Array]) { $raw = @($j) }
    else { $raw = @($j) }
    $out = @()
    $seen = @{}
    foreach ($x in $raw) {
        if (-not $x) { continue }
        $idx = "$($x.Index)".Trim()
        if ($idx -notmatch '^\d+$') { continue }
        if ($seen.ContainsKey($idx)) { continue }
        $seen[$idx] = $true
        $at = ''
        try { $at = "$($x.At)" } catch { }
        $out += [pscustomobject]@{ Index = $idx; At = $at }
    }
    return $out
}