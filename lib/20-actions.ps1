#Requires -Version 5.1
#
# 动作：清理、掉线恢复、升级休眠、唤醒、自启
# 本文件由拆分脚本生成，供 MuMuGuardApp.ps1 dot-source（共享同一 $script: 作用域）

function Invoke-GuardCleanup {
    if (-not (Test-Path $MuMuMgr)) {
        Write-Diag "清理中止：找不到 MuMuManager（$MuMuMgr），请检查 MuMu 路径设置"
        return
    }
    $all  = @(Get-CimInstance Win32_Process -Filter "Name='MuMuNxDevice.exe' OR Name='CefViewWing.exe'" -ErrorAction SilentlyContinue)
    $devs = @($all | Where-Object { $_.Name -eq 'MuMuNxDevice.exe' })
    $cefs = @($all | Where-Object { $_.Name -eq 'CefViewWing.exe' })
    $ageLimit = (Get-Date).AddMinutes(-[int]$script:cfg.CefStaleMin)
    $killedTotal = 0

    # 1) 孤儿 CEF（所属模拟器已关闭）才是真正的残留，这些才清
    $liveIds = @($devs | ForEach-Object { $_.ProcessId })
    $orphans = @($cefs | Where-Object {
        $liveIds -notcontains $_.ParentProcessId -and
        $_.CreationDate -and $_.CreationDate -lt $ageLimit
    })
    foreach ($c in $orphans) {
        try { Stop-Process -Id $c.ProcessId -Force -ErrorAction Stop; $killedTotal++ } catch { }
    }
    if ($orphans.Count -gt 0) {
        Write-GuardLog 'CLEAN_CEF' '孤儿' ("残留 {0} 个已回收" -f $orphans.Count)
    }

    # 2) 运行中实例的 CEF 是 MuMu 窗口正在用的渲染进程：
    #    杀掉会立刻重生（实测 6 秒内补一个），造成无意义的杀进程风暴，所以只告警不动手。
    $alertN = [int]$script:cfg.CefAlert
    foreach ($d in $devs) {
        $mine = @($cefs | Where-Object { $_.ParentProcessId -eq $d.ProcessId })
        if ($mine.Count -gt $alertN) {
            Write-GuardLog 'CEF_HIGH' ("PID={0}" -f $d.ProcessId) ("total={0} 运行中，不改动" -f $mine.Count)
        }
    }

    try {
        $mem = Get-CimInstance Win32_PerfRawData_PerfOS_Memory -ErrorAction Stop
        if ([int]$mem.AvailableMBytes -lt [int]$script:cfg.LowMemMB) {
            Write-GuardLog 'LOW_MEM' '-' ("available={0}MB" -f [int]$mem.AvailableMBytes)
        }
    } catch { }

    $script:lastClean = Get-Date
    return $killedTotal
}


function Get-SleepList {
    try {
        if (-not (Test-Path $SleepFile)) { return @() }
        $raw = Get-Content $SleepFile -Raw -Encoding UTF8
        if (-not $raw -or $raw.Trim() -eq '') { return @() }
        $j = $raw | ConvertFrom-Json
        if ($null -eq $j) { return @() }
        # ConvertFrom-Json 把数组当成一个对象返回，必须手动逐个输出，
        # 否则调用方拿到的"一条记录"其实是整条数组（编号会变成 "2 3"，升级名会串成两串）
        if ($j -is [System.Array]) {
            foreach ($x in $j) { if ($null -ne $x) { $x } }
        } else {
            $j
        }
    } catch { return @() }
}


# 原子写 JSON：先写临时文件再替换，避免 Waker/面板同时读写时读到半截文件
function Write-JsonAtomic([string]$Path, [string]$Json) {
    try {
        $dir = Split-Path $Path -Parent
        if ($dir -and -not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
        $tmp = "$Path.$PID.tmp"
        [System.IO.File]::WriteAllText($tmp, $Json, (New-Object System.Text.UTF8Encoding $false))
        for ($i = 0; $i -lt 5; $i++) {
            try { Move-Item -LiteralPath $tmp -Destination $Path -Force -ErrorAction Stop; break }
            catch { Start-Sleep -Milliseconds 60 }
        }
    } catch { }
}

function Save-SleepList($list) {
    try {
        $arr = @($list | Where-Object { $_ -ne $null })
        # 同一实例只保留最后一条，避免重复任务
        $uniq = [ordered]@{}
        foreach ($e in $arr) { $uniq["$($e.Index)"] = $e }
        $arr = @($uniq.Values)
        $json = $(if ($arr.Count -eq 0) { '[]' } else { ConvertTo-Json -InputObject $arr -Depth 5 })
        Write-JsonAtomic $SleepFile $json
    } catch { }
}


# 启动（开机）一个已关闭的实例；「唤醒」和「启动」按钮都走这里
function Start-Instance([string]$index) {
    if (-not $index -or $index -eq '-') { return $false }
    $mgr = $null
    try { $mgr = $MuMuMgr } catch { $mgr = $null }
    if (-not $mgr -or -not (Test-Path $mgr)) {
        Write-GuardLog 'START_FAIL' "实例$index" '找不到 MuMuManager.exe'
        return $false
    }
    try {
        $out = (& $mgr control -v $index launch 2>&1) -join ' '
        $out = $out.Trim()
        Write-Diag ("启动实例{0}: {1}" -f $index, $out)
        $code = -1
        try { if ($out -match 'errcode"\s*:\s*(-?\d+)') { $code = [int]$Matches[1] } } catch { }
        if ($code -ne 0) {
            Write-GuardLog 'START_FAIL' "实例$index" $out
            return $false
        }
        return $true
    } catch {
        Write-GuardLog 'START_FAIL' "实例$index" $_.Exception.Message
        return $false
    }
}

# 唤醒时把该实例从休眠计划里移除（否则界面一直显示「休眠中」）
function Remove-SleepEntry([string]$index) {
    try {
        $list = @(Get-SleepList)
        $new = @($list | Where-Object { "$($_.Index)" -ne "$index" })
        if ($new.Count -ne $list.Count) {
            Save-SleepList $new
            Write-Diag "已从休眠计划移除实例 $index"
        }
    } catch { Write-Diag "移除休眠记录失败: $($_.Exception.Message)" }
}

function Start-Waker {
    try {
        $running = Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -ErrorAction SilentlyContinue |
                   Where-Object { $_.CommandLine -like '*Waker.ps1*' }
        if ($running) { return }
    } catch { }

    try {
        Start-Process -FilePath 'C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe' `
            -ArgumentList '-NoProfile', '-ExecutionPolicy', 'Bypass', '-WindowStyle', 'Hidden',
                          '-File', (Get-HelperScript 'Waker.ps1'),
                          '-SleepFile', $SleepFile `
            -WindowStyle Hidden | Out-Null
    } catch {
        Write-Diag "启动唤醒器失败: $($_.Exception.Message)"
    }
}


function Invoke-CatchUpWake {
    $list = @(Get-SleepList)
    if ($list.Count -eq 0) { return }

    $now = Get-Date
    $late = @()
    foreach ($s in $list) {
        $wa = $null
        try { $wa = [datetime]::Parse("$($s.WakeAt)") } catch { }
        if ($wa -and $wa -le $now) {
            $late += $s
            $mins = [int]($now - $wa).TotalMinutes
            Write-GuardLog 'WAKE_LATE' "实例$($s.Index)" ("错过唤醒 {0} 分钟，立即补唤醒" -f $mins)
            Write-Diag "补唤醒实例 $($s.Index)，迟到 $mins 分钟"
        }
    }

    # 唤醒器启动后会处理所有已到期条目
    Start-Waker

    if ($late.Count -gt 0) {
        try {
            $names = ($late | ForEach-Object { "实例 $($_.Index)" }) -join '、'
            $tray.ShowBalloonTip(5000, 'MuMuGuard',
                "$names 错过了唤醒时间（可能电脑关机了），正在立即唤醒。",
                [System.Windows.Forms.ToolTipIcon]::Warning)
        } catch { }
    }
}


# 实例实际已经在运行 -> 撤销它的休眠记录
# 独立于「自动休眠」开关：即使不开自动休眠，休眠记录也不该和实际状态对不上
# 防误撤：
#   1) 刚关机 90 秒内不判定（adb 采集还是关机前的在线状态）
#   2) 只有「在线 + 采集数据新鲜（60 秒内）」才算在运行
#   3) 连续 3 次（约 30 秒）确认才撤销，撤销后把计数清零
function Clear-StaleSleepEntries {
    try {
        $list = @(Get-SleepList)
        if ($list.Count -eq 0) { return }
        $now = Get-Date
        if (-not $script:staleSleepHits) { $script:staleSleepHits = @{} }
        $rows = @{}
        foreach ($r in @($script:lastInstances)) {
            if (-not $r) { continue }
            $idx = "$($r.Index)"
            if (-not $idx -or $idx -eq '-') { continue }
            $rows[$idx] = $r
        }
        $keep = @()
        $changed = $false
        foreach ($s in $list) {
            $idx = "$($s.Index)"
            $hits = 0
            if ($script:staleSleepHits.ContainsKey($idx)) { $hits = [int]$script:staleSleepHits[$idx] }
            $row = $null
            if ($rows.ContainsKey($idx)) { $row = $rows[$idx] }
            $dec = Get-StaleSleepDecision -Row $row -Entry $s -Now $now -Hits $hits
            switch ("$($dec.Action)") {
                'skip' {
                    # 关机宽限期：既不撤销也不计数
                    $keep += $s
                }
                'reset' {
                    if ($script:staleSleepHits.ContainsKey($idx)) { $script:staleSleepHits.Remove($idx) }
                    $keep += $s
                }
                'count' {
                    $script:staleSleepHits[$idx] = [int]$dec.Hits
                    $keep += $s
                }
                'revoke' {
                    Write-GuardLog 'WAKE_MANUAL' "实例$idx" '实例已在运行，撤销休眠记录'
                    Write-Diag ("实例{0} 已在运行（连续 {1} 次确认），撤销休眠记录" -f $idx, $dec.Hits)
                    try { $script:staleSleepHits.Remove($idx) } catch { }
                    try { Reset-InstanceMemory $idx } catch { }
                    $changed = $true
                }
            }
        }
        if ($changed) { Save-SleepList $keep }
    } catch { }
}
function Invoke-AutoSleep {
    if ($script:cfg.AutoSleep -ne $true) { return }
    if (-not $script:guardRunning) { return }

    $leadMin  = [double]$script:cfg.SleepLeadMin
    $maxHours = [double]$script:cfg.SleepMaxHours
    $minHours = [double]$script:cfg.SleepMinHours
    $goneMin  = 3    # 游戏关闭后再确认 3 分钟，防止脚本只是重开游戏
    $now = Get-Date
    $list = @(Get-SleepList)
    $changed = $false

    if (-not $script:sleepStage) { $script:sleepStage = @{} }

    # 休眠记录和实际状态的对齐统一由 Clear-StaleSleepEntries 处理（每 10 秒一次，
    # 带关机宽限期和连续确认）。这里不再用「实例行是否存在」判断，
    # 否则刚发出 shutdown 时实例还在 lastInstances 里，会立刻把记录撤销。

    foreach ($r in @($script:lastInstances)) {
        $idx = "$($r.Index)"

        if (-not $script:sleepStage.ContainsKey($idx)) {
            $script:sleepStage[$idx] = @{ Since = $null; GameGone = $null; IdleSince = $null }
        }
        $st = $script:sleepStage[$idx]
        # 20 分钟保护期按模拟器进程启动时间算，面板重启也不会重置
        $procStart = $null
        try { if ($r.PID -and [int]$r.PID -gt 0) { $procStart = (Get-Process -Id ([int]$r.PID) -ErrorAction Stop).StartTime } } catch { }
        if ($procStart) { $st['Since'] = $procStart }
        elseif (-not $st['Since']) { $st['Since'] = $now }

        # 采集数据超过 60 秒未更新就不判定（宁可晚睡，不能用过期状态误关机）
        $ageSec = $null
        try { if ($r.At) { $ageSec = [int]((Get-Date) - [datetime]$r.At).TotalSeconds } } catch { }
        if ($null -eq $ageSec -or $ageSec -gt 60) {
            $key = "sleep-$idx-stale"
            if (-not $script:sleepWarnAt) { $script:sleepWarnAt = @{} }
            $lastAt2 = $script:sleepWarnAt[$key]
            if (-not $lastAt2 -or ($now - $lastAt2).TotalMinutes -ge 10) {
                $script:sleepWarnAt[$key] = $now
                $ageTxt = $(if ($null -eq $ageSec) { '未知' } else { "$ageSec 秒" })
                Write-Diag ("实例{0} 未休眠[stale-data] 采集数据 {1}未更新" -f $idx, $ageTxt)
            }
            continue
        }

        # 前台判定：游戏不在前台持续够久 = 脚本在等升级（紫孔雀会把游戏切后台）
        # 注意用 Test-IsGamePackage（90-pure 的纯函数）；Test-GameForeground 是 63-res 的
        # adb 查询版本（按实例号），两者不能同名，否则加载顺序会覆盖导致这里绑参失败。
        $fgPkg = ''
        try { if ($r.PSObject.Properties.Name -contains 'Foreground') { $fgPkg = [string]$r.Foreground } } catch { }
        $gameFg = $false
        if ($fgPkg) {
            try { $gameFg = Test-IsGamePackage -Foreground $fgPkg -Packages ([string]$script:cfg.PkgGame) } catch { }
        }
        # 取不到前台包名（adb 解析失败/窗口切换瞬间）时不累计后台空闲，宁可晚睡也不误睡
        if ($r.Game -eq $true -and $fgPkg -and -not $gameFg) {
            if (-not $st['IdleSince']) { $st['IdleSince'] = $now }
        } else {
            $st['IdleSince'] = $null
        }

        $dec = Get-SleepStage -Row $r -Since $st['Since'] -GameGone $st['GameGone'] -Now $now `
             -GameGoneMin $goneMin `
            -LeadMin $leadMin -MinHours $minHours -MaxHours $maxHours `
            -AutoSleep ([bool]$script:cfg.AutoSleep) -GuardRunning ([bool]$script:guardRunning) `
            -DetectOff @($script:cfg.DetectOff) `
            -SleepingIndexes @($list | ForEach-Object { "$($_.Index)" }) `
            -AllowBackground ([bool]$script:cfg.SleepBackground) -IdleMin ([double]$script:cfg.SleepIdleMin) -GameForeground $gameFg -IdleSince $st['IdleSince']

        $action = "$($dec.Action)"
        $reason = "$($dec.Reason)"

        if ($action -eq 'gamegone') {
            $st['GameGone'] = $now
            Write-Diag ("实例{0} 游戏已退出，开始 {1} 分钟确认" -f $idx, $goneMin)
            continue
        }

        if ($action -eq 'wait') {
            # 游戏又起来了 → 取消确认计时
            if ($r.Game -eq $true -and $st['GameGone']) { $st['GameGone'] = $null }
            $key = "sleep-$idx-$reason"
            if (-not $script:sleepWarnAt) { $script:sleepWarnAt = @{} }
            $lastAt = $script:sleepWarnAt[$key]
            if (-not $lastAt -or ($now - $lastAt).TotalMinutes -ge 10) {
                $script:sleepWarnAt[$key] = $now
                Write-Diag ("实例{0} 未休眠[{1}] Script={2} Game={3} Sched={4} UpDone={5}" -f $idx, $reason, $r.Script, $r.Game, $r.Sched, $r.UpDone)
            }
            continue
        }

        if ($action -ne 'sleep') { continue }

        $doneAt = [datetime]$r.UpDone
        $wakeAt = $doneAt.AddMinutes(-$leadMin)
        $entry = [pscustomobject]@{
            Index   = $idx
            WakeAt  = $wakeAt.ToString('yyyy-MM-ddTHH:mm:ss')
            DoneAt  = $doneAt.ToString('yyyy-MM-ddTHH:mm:ss')
            Upgrade = ('{0} Lv.{1}' -f $r.UpName, $r.UpLvl)
            Since   = $now.ToString('yyyy-MM-ddTHH:mm:ss')
            ShutdownAt = $now.ToString('yyyy-MM-ddTHH:mm:ss')
        }
        $list += $entry
        $changed = $true
        try {
            Start-Process -FilePath $MuMuMgr -ArgumentList 'control', '-v', $idx, 'shutdown' -WindowStyle Hidden | Out-Null
            if ($r.Game -eq $true) {
                $idleTxt = $(if ($st['IdleSince']) { [int]($now - [datetime]$st['IdleSince']).TotalMinutes } else { 0 })
                Write-GuardLog 'SLEEP_BG' "实例$idx" ("游戏在后台空闲 {0} 分钟（前台：{1}），按升级时间休眠" -f $idleTxt, $(if ($fgPkg) { $fgPkg } else { '未知' }))
            }
            Write-GuardLog 'SLEEP' "实例$idx" ("关机休眠，{0} 唤醒（{1}）" -f $wakeAt.ToString('HH:mm'), $entry.Upgrade)
            # 我们自己关的：清空该实例记忆，下次开机像新实例一样重新抓取
            try { Reset-InstanceMemory $idx 'sleep' } catch { }
            $st['Since'] = $null
            $st['GameGone'] = $null
        } catch {
            Write-GuardLog 'SLEEP_FAIL' "实例$idx" $_.Exception.Message
            $list = @($list | Where-Object { -not ("$($_.Index)" -eq $idx) })
        }
    }

    if ($changed) { Save-SleepList $list }
}


function Start-ScriptRecover([string]$index) {
    # 先只重新拉起脚本（快，不影响实例）
    $log = Join-Path $LogDir 'recover.log'
    try {
        $r = (& $MuMuMgr control -v $index app launch -pkg $PkgScript 2>&1) -join ' '
        Add-Content -Path $log -Value ('[{0:HH:mm:ss}] [实例{1}] 拉起脚本: {2}' -f (Get-Date), $index, $r.Trim()) -Encoding UTF8
    } catch {
        Add-Content -Path $log -Value ('[{0:HH:mm:ss}] [实例{1}] 拉起失败: {2}' -f (Get-Date), $index, $_.Exception.Message) -Encoding UTF8
    }
    $script:lastRecover[$index] = Get-Date
    Write-GuardLog 'AUTO_RECOVER' "实例$index" 'relaunch script'
}


function Start-InstanceRecover([string]$index) {
    # 脚本拉不起来就整机重启并自动开脚本
    $log = Join-Path $LogDir 'restart.log'
    try {
        Start-Process -FilePath 'C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe' `
            -ArgumentList '-NoProfile', '-ExecutionPolicy', 'Bypass', '-WindowStyle', 'Hidden',
                          '-File', (Get-HelperScript 'Restart-Instance.ps1'),
                          '-Index', "$index", '-LogFile', $log `
            -WindowStyle Hidden | Out-Null
        Write-GuardLog 'AUTO_RESTART' "实例$index" 'restart instance + launch script'
    } catch {
        Write-GuardLog 'RECOVER_FAIL' "实例$index" $_.Exception.Message
    }
    $script:lastRecover[$index] = Get-Date
}


function Invoke-AutoRecover {
    if ($script:cfg.AutoRecover -ne $true) { return }
    if (-not $script:guardRunning) { return }

    $now = Get-Date
    $data = @($script:lastInstances)

    foreach ($r in $data) {
        $idx = "$($r.Index)"
        if ($idx -eq '-') { continue }

        # 该实例的检测被手动暂停
        if (@($script:cfg.DetectOff | Where-Object { $_ -ne $null }) -contains $idx) {
            $script:failCount[$idx] = 0
            continue
        }

        # 脚本根本没安装：不是掉线，绝对不要去恢复（否则会反复重启用户的模拟器）
        if ($r.PSObject.Properties.Name -contains 'Installed' -and $r.Installed -eq $false) {
            $script:failCount[$idx] = 0
            continue
        }

        # adb 不通时不判定（避免把网络问题当成脚本掉了）
        if ($r.Online -ne $true) {
            $script:failCount[$idx] = 0
            continue
        }

        # 只有「确认没在跑」才计入掉线；Script 为 $null（采集未知）时不动
        if ($r.Script -ne $false) {
            $script:failCount[$idx] = 0
            continue
        }

        # 脚本确认没在跑
        if ($script:recovering.ContainsKey($idx) -and $script:recovering[$idx]) { continue }

        $script:failCount[$idx] = [int]$script:failCount[$idx] + 1
        $need = [int]$script:cfg.RecoverFailCount
        if ($need -lt 1) { $need = 1 }

        if ($script:failCount[$idx] -lt $need) {
            Write-GuardLog 'ALERT_SCRIPT' "实例$idx" ("未运行，连续 {0}/{1}" -f $script:failCount[$idx], $need)
            continue
        }

        # 冷却期内不重复恢复
        $gapMin = [double]$script:cfg.RecoverCooldown
        if ($script:lastRecover.ContainsKey($idx)) {
            if (($now - $script:lastRecover[$idx]).TotalMinutes -lt $gapMin) { continue }
        }

        $script:recovering[$idx] = $true
        try {
            Write-GuardLog 'ALERT_SCRIPT' "实例$idx" '脚本掉线，开始恢复'

            # 第一次：尝试单独拉起脚本
            Start-ScriptRecover $idx
            Start-Sleep -Seconds 8

            # 复查
            $adbPort = $null
            try {
                # 版本号按编号实际查找（可能同时装了安卓 12 / 15）
                $series = $null
                if ($script:instanceMap -and $script:instanceMap.ContainsKey("$idx") -and $script:instanceMap["$idx"].Series) { $series = "$($script:instanceMap["$idx"].Series)" }
                if (-not $series) {
                    $vmsPath = if ($MuMuRoot) { Join-Path $MuMuRoot 'vms' } else { '' }
    $hit = if ($vmsPath -and (Test-Path -LiteralPath $vmsPath)) { Get-ChildItem -LiteralPath $vmsPath -Directory -Filter ("MuMuPlayer-*-{0}" -f $idx) -ErrorAction SilentlyContinue | Select-Object -First 1 } else { $null }
                    if ($hit -and $hit.Name -match 'MuMuPlayer-([\d\.]+)-') { $series = $Matches[1] } else { $series = '15.0' }
                }
                $cfgPath = if ($vmsPath) { Join-Path $vmsPath ("MuMuPlayer-{0}-{1}\configs\vm_config.json" -f $series, $idx) } else { '' }
                if (Test-Path $cfgPath) {
                    $adbPort = (Get-Content $cfgPath -Raw -Encoding UTF8 | ConvertFrom-Json).vm.nat.port_forward.adb.host_port
                }
            } catch { }

            $ok = $false
            if ($adbPort) {
                $serial = "127.0.0.1:$adbPort"
                for ($k = 0; $k -lt 4; $k++) {
                    $pidOut = ((& $AdbExe -s $serial shell "pidof $PkgScript" 2>$null) -join '').Trim()
                    if ($pidOut) { $ok = $true; break }
                    Start-Sleep -Seconds 3
                }
            }

            if ($ok) {
                Write-GuardLog 'RECOVER_OK' "实例$idx" '脚本已恢复'
                $script:failCount[$idx] = 0
            } else {
                Write-GuardLog 'RECOVER_FAIL' "实例$idx" '脚本未起来，转为整机重启'
                Start-InstanceRecover $idx
                $script:failCount[$idx] = 0
            }
        } finally {
            $script:recovering[$idx] = $false
        }
    }

    # 清理已消失实例的记录
    $valid = @($data | ForEach-Object { "$($_.Index)" })
    foreach ($k in @($script:failCount.Keys)) { if ($valid -notcontains $k) { $script:failCount.Remove($k) } }
    foreach ($k in @($script:lastRecover.Keys)) { if ($valid -notcontains $k) { $script:lastRecover.Remove($k) } }
    foreach ($k in @($script:recovering.Keys)) { if ($valid -notcontains $k) { $script:recovering.Remove($k) } }
}


function Export-Report {
    $file = Get-LogFile
    $rows = @()
    if (Test-Path $file) { try { $rows = @(Import-Csv $file -ErrorAction Stop) } catch { } }

    $path = Join-Path $LogDir ('report-{0:yyyyMMdd-HHmmss}.txt' -f (Get-Date))
    $lines = @()
    $lines += 'MuMuGuard 报告'
    $lines += ('生成时间: {0:yyyy-MM-dd HH:mm:ss}' -f (Get-Date))
    $lines += ''
    $lines += '== 当前实例 =='
    foreach ($r in @($script:lastInstances)) {
        # Online 只代表 adb 通了，游戏是否在跑要用 Game 字段（之前写错，报告一律显示"游戏运行中"）
        $gameText = if ($r.Online -eq $false) { 'adb 未连接' }
                    elseif ($r.Game -eq $true) { '游戏运行中' }
                    elseif ($r.Game -eq $false) { '游戏未运行' }
                    else { '未知' }
        $lines += ('{0}  PID={1}  CPU={2:N2}核  私有={3}MB  CEF={4}  {5}  {6}' -f $r.Name, $r.PID, $r.Cores, $r.Private, $r.CEF, $gameText, $r.Judge)
    }
    $hm = Get-HostMemory
    $lines += ''
    $lines += '== 主机内存 =='
    $lines += ('可用 {0} MB / 共 {1} MB' -f $hm.AvailableMB, $script:totalMB)
    $lines += ('提交 {0:N1} GB   页面文件 {1} MB   内存压缩 {2}' -f $hm.CommitGB, $hm.PageFileMB, $(if ($hm.Compression) { '已启用' } else { '已关闭' }))
    $lines += ''
    $lines += '== 今日统计 =='
    $lines += ('清理 {0} 次，回收 {1} 个进程，告警 {2} 条' -f $script:logClean, $script:logKilled, $script:logAlert)
    $lines += ''
    $lines += '== 环境诊断 =='
    $lines += ('MuMu 路径: {0}' -f $MuMuRoot)
    $lines += ('MuMuManager: {0}  存在={1}' -f $MuMuMgr, (Test-Path $MuMuMgr))
    $lines += ('adb 路径: {0}  存在={1}' -f $AdbExe, (Test-Path $AdbExe))
    try { $lines += ('adb 版本: {0}' -f (((& $AdbExe version 2>&1) -join ' '))) } catch { $lines += 'adb 版本: 读取失败' }
    try {
        $devOut = ((& $AdbExe devices 2>&1) -join "`n")
        $lines += 'adb devices:'
        foreach ($ln in ($devOut -split "`n")) { if ($ln.Trim()) { $lines += ('  ' + $ln.Trim()) } }
    } catch { $lines += 'adb devices: 执行失败' }
    try {
        $srv = Get-NetTCPConnection -LocalPort 5037 -State Listen -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($srv) { $lines += ('5037 端口被 PID={0} 占用: {1}' -f $srv.OwningProcess, (Get-Process -Id $srv.OwningProcess -ErrorAction SilentlyContinue).Path) }
        else { $lines += '5037 端口无监听' }
    } catch { }
    $lines += ''
    $lines += '== MuMu 实例（MuMuManager）=='
    try {
        $infoRaw = Invoke-CaptureUtf8 -Exe $MuMuMgr -ArgList @('info', '-v', 'all')
        foreach ($ln in ($infoRaw -split "`n")) { if ($ln.Trim()) { $lines += $ln.TrimEnd() } }
    } catch { $lines += '读取失败' }
    $lines += ''
    $lines += '== adb 连接状态 =='
    foreach ($r in @($script:lastInstances)) {
        $errText = ''
        if ($r.PSObject.Properties.Name -contains 'AdbErr') { $errText = "$($r.AdbErr)" }
        $lines += ('{0}  在线={1}  {2}' -f $r.Name, $r.Online, $(if ($errText) { '错误: ' + $errText } else { 'ok' }))
    }
    $lines += ''
    $lines += '== 事件明细 =='
    foreach ($r in $rows) { $lines += ('{0}  {1}  {2}  {3}' -f $r.Time, $r.Action, $r.Instance, $r.Detail) }

    $lines | Set-Content -Path $path -Encoding UTF8
    Start-Process notepad.exe -ArgumentList $path
}


function Set-GuardState {
    if ($script:guardRunning) {
        $script:guardRunning = $false
        $script:guardTimer.Stop()
        $script:recoverTimer.Stop()
    } else {
        $script:guardRunning = $true
        [void](Invoke-GuardCleanup)
        $script:guardTimer.Interval = [TimeSpan]::FromMinutes([double]$script:cfg.GuardMinute)
        $script:guardTimer.Start()
        $script:recoverTimer.Interval = [TimeSpan]::FromSeconds([double]$script:cfg.RecoverCheckSec)
        $script:recoverTimer.Start()
    }
    # 记住看护状态与窗口位置，下次打开自动恢复
    try {
        if ($win.WindowState -eq 'Normal') {
            $script:cfg.WindowLeft = [math]::Round($win.Left)
            $script:cfg.WindowTop  = [math]::Round($win.Top)
        }
        $script:cfg.GuardRunning = $script:guardRunning
        Save-Config
    } catch { }
    $script:lastGuardState = $null
    Update-Ui
}


function Set-Autostart([bool]$enable) {
    try {
        if ($enable) {
            $vbs = Join-Path $Root '启动面板.vbs'
            if (-not (Test-Path $vbs)) {
                Write-Diag "开机自启失败：找不到 $vbs"
                return $false
            }
            $cmd = ('wscript.exe "{0}"' -f $vbs)
            if (-not (Test-Path $script:runKey)) { New-Item -Path $script:runKey -Force | Out-Null }
            New-ItemProperty -Path $script:runKey -Name $script:runName -Value $cmd -PropertyType String -Force | Out-Null
            Write-Diag "已开启开机自启"
            return $true
        } else {
            Remove-ItemProperty -Path $script:runKey -Name $script:runName -ErrorAction SilentlyContinue
            Write-Diag "已关闭开机自启"
            return $true
        }
    } catch {
        Write-Diag "开机自启设置失败: $($_.Exception.Message)"
        return $false
    }
}


function Get-Autostart {
    try {
        $v = Get-ItemProperty -Path $script:runKey -Name $script:runName -ErrorAction SilentlyContinue
        return ($null -ne $v)
    } catch { return $false }
}



# ---------------- 批量操作 ----------------




# 手动接管某台实例：清掉它的"记忆"，下一轮重新抓取
function Reset-InstanceMemory([string]$index, [string]$Reason = 'manual') {
    $i = "$index"
    try { $script:failCount[$i] = 0 } catch { }
    try { $script:lastRecover.Remove($i) } catch { }
    try { $script:recovering[$i] = $false } catch { }
    try { if ($script:adbSync.Force) { $script:adbSync.Force[$i] = $true } } catch { }
    # 重新计时：像新实例一样，先等 20 分钟再判断
    try { if (-not $script:sleepStage) { $script:sleepStage = @{} }; $script:sleepStage[$i] = @{ Since = Get-Date; GameGone = $null } } catch { }
    Write-Diag ("实例{0} 已清除升级数据，等待重新抓取（{1}）" -f $i, $Reason)
}

# 彻底清除程序记忆：删除休眠任务、趋势、日志、统计，只保留 config.json
function Invoke-ClearMemory([bool]$StopGuard) {
    $removed = 0

    # 先停掉唤醒器，否则它内存里还挂着旧任务
    try { Stop-AllWakers } catch { }

    foreach ($f in @((Join-Path $Root 'sleep.json'), (Join-Path $Root 'trend.json'), (Join-Path $Root 'state.json'))) {
        if (Test-Path $f) { try { Remove-Item $f -Force -ErrorAction Stop; $removed++ } catch { } }
    }

    $logDir = Join-Path $Root 'logs'
    if (Test-Path $logDir) {
        Get-ChildItem $logDir -File -ErrorAction SilentlyContinue | Where-Object {
            $_.Extension -in '.log', '.csv', '.txt'
        } | ForEach-Object {
            try { Remove-Item $_.FullName -Force -ErrorAction Stop; $removed++ } catch { }
        }
    }

    # 运行时状态
    $script:failCount = @{}
    $script:lastRecover = @{}
    $script:recovering = @{}
    $script:sleepWarnAt = @{}
    $script:rootWarned = $false
    $script:lastInstances = @()
    $script:cardMap = @{}
    $script:cmpMap = @{}
    try { $script:trend.Clear() } catch { }
    try { $script:lastGuardState = $null } catch { }

    # 运行中的实例也必须立即清空并重新抓取，否则采集线程会用内存缓存把旧数据填回来
    try {
        $script:sleepStage = @{}
        $script:sleepWarnAt = @{}
        $allIdx = @()
        if ($script:instanceMap) { $allIdx = @($script:instanceMap.Keys) }
        foreach ($k in $allIdx) { Reset-InstanceMemory "$k" }
    } catch { }

    # 界面上的缓存控件
    try { if ($pnlCards) { [void]$pnlCards.Children.Clear() } } catch { }
    try { if ($cmpRings) { [void]$cmpRings.Children.Clear() } } catch { }

    if ($StopGuard -and $script:guardRunning) {
        try { Set-GuardState $false } catch { }
    }

    Write-Diag ("已清除程序记忆：删除 {0} 个文件，休眠任务与统计已归零" -f $removed)
    return $removed
}
