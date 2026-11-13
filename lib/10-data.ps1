#Requires -Version 5.1
#
# 数据采集：实例状态、主机内存、健康检查
# 本文件由拆分脚本生成，供 MuMuGuardApp.ps1 dot-source（共享同一 $script: 作用域）

function Get-InstanceData {
    $now = Get-Date

    # 一次 Toolhelp32 快照拿到所有进程的 PID / 父进程 / 名字
    $snap = @()
    try { $snap = [ProcSnap]::Snap() } catch { }

    $devPids = @()
    $cefParent = @{}
    foreach ($e in $snap) {
        if ($e.Name -eq 'MuMuNxDevice.exe') { $devPids += [int]$e.Pid }
        elseif ($e.Name -eq 'CefViewWing.exe') { $cefParent[[int]$e.Pid] = [int]$e.Parent }
    }

    $rows = @()
    $adb  = $script:adbSync.Data
    $hb   = $script:adbSync.Heartbeat
    $adbFresh = ($null -ne $hb -and ($now - $hb).TotalSeconds -lt 90)

    foreach ($pidVal in $devPids) {
        $proc = Get-Process -Id $pidVal -ErrorAction SilentlyContinue
        if (-not $proc) { continue }

        # 实例编号：新 PID 首次出现时查一次命令行，之后走缓存
        if (-not $script:indexCache.ContainsKey($pidVal)) {
            $idx = '-'
            try {
                $ci = Get-CimInstance Win32_Process -Filter "ProcessId=$pidVal" -ErrorAction Stop
                if ($ci.CommandLine -match 'MuMuPlayer-[\d\.]+-(\d+)') { $idx = $Matches[1] }
            } catch { }
            $script:indexCache[$pidVal] = $idx
        }
        $index = $script:indexCache[$pidVal]

        # 该实例的配置（名称 / 内存 / CPU）
        $ic = $null
        if ($index -ne '-' -and $script:instanceMap -and $script:instanceMap.ContainsKey("$index")) {
            $ic = $script:instanceMap["$index"]
        }
        $displayName = Get-InstanceDisplayName -Config $ic -Aliases $script:cfg.Aliases

        $cefCount = 0
        foreach ($k in $cefParent.Keys) {
            if ($cefParent[$k] -eq $pidVal) { $cefCount++ }
        }

        $cores = -1
        if ($script:prevCpu.ContainsKey($pidVal)) {
            $p  = $script:prevCpu[$pidVal]
            $dt = ($now - $p.Time).TotalSeconds
            if ($dt -gt 0.4 -and $null -ne $proc.CPU -and $null -ne $p.Cpu) {
                $cores = [math]::Round(($proc.CPU - $p.Cpu) / $dt, 2)
            }
        }
        $script:prevCpu[$pidVal] = @{ Cpu = $proc.CPU; Time = $now }

        # adb 数据（按实例编号匹配）
        $online = $null; $game = $null; $spin = $null; $scriptOn = $null
        $upgrade = $null; $waiting = $null; $sched = $null
        if ($index -ne '-' -and $adbFresh -and $adb -and $adb.ContainsKey($index)) {
            $a = $adb[$index]
            $online   = $a.Online
            $scriptOn = $a.Script
            $game     = $a.Game
            $spin     = $a.Spin
            $props = $a.PSObject.Properties.Name
            if ($props -contains 'Upgrade') { $upgrade = $a.Upgrade }
            if ($props -contains 'Waiting') { $waiting = $a.Waiting }
            if ($props -contains 'Sched')   { $sched   = $a.Sched }
        }

        # 升级信息：完成时间已过就不显示
        $upName = ''; $upLvl = 0; $upDone = $null; $upLeft = ''
        if ($upgrade -and $upgrade.Ts) {
            $doneAt = [datetimeoffset]::FromUnixTimeSeconds([int64]$upgrade.Ts).ToLocalTime().DateTime
            $label = Get-RemainingLabel -DoneAt $doneAt -Now (Get-Date)
            if ($label) {
                $upName = $upgrade.Name
                $upLvl  = $upgrade.Lvl
                $upDone = $doneAt
                $upLeft = $label
            }
        }

        $privateMB = [int]($proc.PrivateMemorySize64 / 1MB)

        # 环的填充比例 = 私有内存 / 该实例的内存刻度
        # 刻度优先用实例自身配置（6G 实例 ≈ 8.6G），读不到才退回全局阈值
        $memBase = 0
        if ($ic -and $ic.MemBaseMB -gt 0) { $memBase = [int]$ic.MemBaseMB }
        if ($memBase -le 0) {
            $memBase = [int]$script:cfg.MemAlertMB
            if ($memBase -le 0) { $memBase = 9216 }
        }
        $memPct = Get-MemPercent -PrivateMB $privateMB -BaseMB $memBase

        $level = 0
        $judge = '正常'
        $detectOff = (@($script:cfg.DetectOff | Where-Object { $_ -ne $null }) -contains "$index")
        # 只以脚本是否在跑作为"在线"判据；游戏未运行属正常（脚本占用中）
        if ($detectOff)              { $level = 0; $judge = '已暂停' }
        elseif ($scriptOn -eq $false)    { $level = 2; $judge = '脚本停止' }
        elseif ($online -eq $false)  { $level = 1; $judge = 'adb 未连接' }
        elseif ($spin -ne $null -and $spin -gt [double]$script:cfg.NemuSpinPct) { $level = 2; $judge = '空转' }
        elseif ($cefCount -gt [int]$script:cfg.CefAlert) { $level = 1; $judge = 'CEF 泄漏' }
        elseif ($cores -gt [double]$script:cfg.CpuAlert) { $level = 1; $judge = 'CPU 偏高' }
        elseif ($privateMB -gt $memBase) { $level = 1; $judge = '内存偏高' }

        $rows += [pscustomobject]@{
            Index   = $index
            Detect  = (-not $detectOff)
            Name    = $displayName
            PID     = $pidVal
            Cores   = $cores
            Private = $privateMB
            WS      = [int]($proc.WorkingSet64 / 1MB)
            CEF     = $cefCount
            MemPct  = $memPct
            MemBase = $memBase
            GuestGB = $(if ($ic) { $ic.MemoryGB } else { 0 })
            Online  = $online
            Script  = $scriptOn
            Game    = $game
            Spin    = $spin
            UpName  = $upName
            UpLvl   = $upLvl
            UpDone  = $upDone
            UpLeft  = $upLeft
            Waiting = $waiting
            Sched   = $sched
            Judge   = $judge
            Level   = $level
        }
    }

    $valid = @($devPids)
    foreach ($k in @($script:prevCpu.Keys)) {
        if ($valid -notcontains $k) { $script:prevCpu.Remove($k) }
    }
    foreach ($k in @($script:indexCache.Keys)) {
        if ($valid -notcontains $k) { $script:indexCache.Remove($k) }
    }

    return @($rows | Sort-Object { [int]($_.Index -replace '\D','0') })
}


function Get-HostMemory {
    $r = [pscustomobject]@{ AvailableMB = 0; CommitGB = 0; PageFileMB = 0; Compression = $false }

    # 内存：直接读内核，不经过 WMI
    try {
        $mi = [MemInfo]::Get()
        $r.AvailableMB = [int]($mi[1] / 1MB)
        $commitUsed = ($mi[2] - $mi[3]) / 1GB
        if ($commitUsed -lt 0) { $commitUsed = 0 }
        $r.CommitGB = [math]::Round($commitUsed, 1)
    } catch { }

    # 页面文件：WMI 较慢（本机一次约 600ms），缓存 5 分钟
    $now = Get-Date
    if (-not $script:pfCache -or ($now - $script:pfCache.Time).TotalSeconds -ge 300) {
        $pfVal = 0
        try {
            $pf = @(Get-CimInstance Win32_PageFileUsage -ErrorAction Stop)
            if ($pf.Count -gt 0) { $pfVal = [int]$pf[0].CurrentUsage }
        } catch { }
        $script:pfCache = @{ Time = $now; Value = $pfVal }
    }
    $r.PageFileMB = $script:pfCache.Value

    # 内存压缩进程：状态基本不变，缓存 5 分钟
    if (-not $script:compCache -or ($now - $script:compCache.Time).TotalSeconds -ge 300) {
        $script:compCache = @{ Time = $now; Value = [bool](Get-Process -Name 'Memory Compression' -ErrorAction SilentlyContinue) }
    }
    $r.Compression = $script:compCache.Value

    return $r
}


function Get-Health($hm) {
    $items = @()

    $comp = [bool](Get-Process -Name 'Memory Compression' -ErrorAction SilentlyContinue)
    $items += [pscustomobject]@{ Name = '内存压缩'; Ok = $comp; Text = $(if ($comp) { '已启用' } else { '已关闭' }) }

    $sm = Get-Service SysMain -ErrorAction SilentlyContinue
    $smOk = ($sm -and $sm.Status -eq 'Running')
    $items += [pscustomobject]@{ Name = 'SysMain'; Ok = $smOk; Text = $(if ($smOk) { '运行中' } else { '未运行' }) }

    $run = (Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run' -ErrorAction SilentlyContinue).'Mem Reduct'
    $mrOk = (-not $run)
    $items += [pscustomobject]@{ Name = 'Mem Reduct'; Ok = $mrOk; Text = $(if ($mrOk) { '未自启' } else { '已自启' }) }

    $hm = if ($hm) { $hm } else { Get-HostMemory }
    $pfOk = ($hm.PageFileMB -lt 8000)
    $items += [pscustomobject]@{ Name = '页面文件'; Ok = $pfOk; Text = ('{0:N0} MB' -f $hm.PageFileMB) }

    $cefOk = $true
    foreach ($r in @($script:lastInstances)) {
        if ($r.CEF -gt [int]$script:cfg.CefAlert) { $cefOk = $false }
    }
    $items += [pscustomobject]@{ Name = 'CEF 泄漏'; Ok = $cefOk; Text = $(if ($cefOk) { '无' } else { '有' }) }

    return $items
}


