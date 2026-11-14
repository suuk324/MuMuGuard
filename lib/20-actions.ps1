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

    foreach ($d in $devs) {
        $mine = @($cefs | Where-Object { $_.ParentProcessId -eq $d.ProcessId } | Sort-Object CreationDate -Descending)
        if ($mine.Count -le [int]$script:cfg.CefAlert) { continue }

        $candidates = @($mine | Select-Object -Skip ([int]$script:cfg.CefKeep) |
                        Where-Object { $_.CreationDate -and $_.CreationDate -lt $ageLimit })
        if ($candidates.Count -eq 0) { continue }

        $k = 0
        foreach ($c in $candidates) {
            try { Stop-Process -Id $c.ProcessId -Force -ErrorAction Stop; $k++ } catch { }
        }
        if ($k -gt 0) {
            $killedTotal += $k
            Write-GuardLog 'CLEAN_CEF' ("PID={0}" -f $d.ProcessId) ("total={0} stale={1} killed={2}" -f $mine.Count, $candidates.Count, $k)
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
        return @(@($raw | ConvertFrom-Json) | Where-Object { $_ -ne $null })
    } catch { return @() }
}


function Save-SleepList($list) {
    try {
        $arr = @($list | Where-Object { $_ -ne $null })
        if ($arr.Count -eq 0) {
            '[]' | Set-Content -Path $SleepFile -Encoding UTF8
        } else {
            ConvertTo-Json -InputObject $arr -Depth 5 | Set-Content -Path $SleepFile -Encoding UTF8
        }
    } catch { }
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


function Invoke-AutoSleep {
    if ($script:cfg.AutoSleep -ne $true) { return }
    if (-not $script:guardRunning) { return }

    $leadMin  = [double]$script:cfg.SleepLeadMin
    $maxHours = [double]$script:cfg.SleepMaxHours
    $now = Get-Date
    $list = @(Get-SleepList)
    $changed = $false

    # 已在休眠列表里的实例：如果已经被手动启动，就撤销记录
    $runningIdx = @{}
    foreach ($r in @($script:lastInstances)) { $runningIdx["$($r.Index)"] = $true }
    $keep = @()
    foreach ($s in $list) {
        $idx = "$($s.Index)"
        if ($runningIdx.ContainsKey($idx)) {
            Write-GuardLog 'WAKE_MANUAL' "实例$idx" '已恢复运行，撤销休眠记录'
            $changed = $true
            continue
        }
        $keep += $s
    }
    $list = $keep

    # 判断是否该休眠
    foreach ($r in @($script:lastInstances)) {
        $idx = "$($r.Index)"

        $decision = Get-SleepDecision -Row $r `
            -AutoSleep ([bool]$script:cfg.AutoSleep) `
            -GuardRunning ([bool]$script:guardRunning) `
            -LeadMin $leadMin -MaxHours $maxHours -Now $now `
            -DetectOff @($script:cfg.DetectOff) `
            -SleepingIndexes @($list | ForEach-Object { "$($_.Index)" })

        if ($decision -ne '') { continue }

        $doneAt = [datetime]$r.UpDone
        $wakeAt = $doneAt.AddMinutes(-$leadMin)

        # 记录并关机
        $entry = [pscustomobject]@{
            Index   = $idx
            WakeAt  = $wakeAt.ToString('yyyy-MM-ddTHH:mm:ss')
            DoneAt  = $doneAt.ToString('yyyy-MM-ddTHH:mm:ss')
            Upgrade = ('{0} Lv.{1}' -f $r.UpName, $r.UpLvl)
            Since   = $now.ToString('yyyy-MM-ddTHH:mm:ss')
        }
        $list += $entry
        $changed = $true

        try {
            Start-Process -FilePath $MuMuMgr -ArgumentList 'control', '-v', $idx, 'shutdown' -WindowStyle Hidden | Out-Null
            Write-GuardLog 'SLEEP' "实例$idx" ("关机休眠，{0} 唤醒（{1}）" -f $wakeAt.ToString('HH:mm'), $entry.Upgrade)
        } catch {
            Write-GuardLog 'SLEEP_FAIL' "实例$idx" $_.Exception.Message
            $list = @($list | Where-Object { -not ("$($_.Index)" -eq $idx) })
        }
    }

    if ($changed) {
        Save-SleepList $list
    }
    if (@($list).Count -gt 0) { Start-Waker }
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

        if ($r.Script -eq $true) {
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
                    $hit = Get-ChildItem (Join-Path $MuMuRoot 'vms') -Directory -Filter ("MuMuPlayer-*-{0}" -f $idx) -ErrorAction SilentlyContinue | Select-Object -First 1
                    if ($hit -and $hit.Name -match 'MuMuPlayer-([\d\.]+)-') { $series = $Matches[1] } else { $series = '15.0' }
                }
                $cfgPath = Join-Path $MuMuRoot ("vms\MuMuPlayer-{0}-{1}\configs\vm_config.json" -f $series, $idx)
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
        $gameText = if ($r.Online -eq $true) { '游戏运行中' } elseif ($r.Online -eq $false) { '未运行' } else { '未知' }
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
        $guardTimer.Stop()
        $recoverTimer.Stop()
    } else {
        $script:guardRunning = $true
        [void](Invoke-GuardCleanup)
        $guardTimer.Interval = [TimeSpan]::FromMinutes([double]$script:cfg.GuardMinute)
        $guardTimer.Start()
        $recoverTimer.Interval = [TimeSpan]::FromSeconds([double]$script:cfg.RecoverCheckSec)
        $recoverTimer.Start()
    }
    # 记住看护状态与窗口位置，下次打开自动恢复
    try {
        $script:cfg.WindowLeft = [math]::Round($win.Left)
        $script:cfg.WindowTop  = [math]::Round($win.Top)
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

# 全部重启：对所有运行中的实例触发重启并自动拉起脚本
function Invoke-BatchRestart {
    $rows = @($script:lastInstances | Where-Object { $_.Index -ne '-' })
    if ($rows.Count -eq 0) { return 0 }
    $n = 0
    foreach ($r in $rows) {
        $idx = "$($r.Index)"
        try {
            $log = Join-Path $LogDir 'restart.log'
            Start-Process -FilePath 'C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe' `
                -ArgumentList '-NoProfile', '-ExecutionPolicy', 'Bypass', '-WindowStyle', 'Hidden',
                              '-File', (Get-HelperScript 'Restart-Instance.ps1'),
                              '-Index', $idx, '-LogFile', $log `
                -WindowStyle Hidden | Out-Null
            Write-GuardLog 'AUTO_RESTART' "实例$idx" '批量重启'
            $n++
        } catch {
            Write-Diag "批量重启实例 $idx 失败: $($_.Exception.Message)"
        }
    }
    return $n
}

# 全部休眠：只休眠有升级完成时间的实例，其余跳过
function Invoke-BatchSleep {
    $list = @(Get-SleepList)
    $leadMin = [double]$script:cfg.SleepLeadMin
    $now = Get-Date
    $n = 0
    $skip = 0

    foreach ($r in @($script:lastInstances)) {
        $idx = "$($r.Index)"
        if ($idx -eq '-' -or $r.Sleeping) { continue }
        if (@($list | Where-Object { "$($_.Index)" -eq $idx }).Count -gt 0) { continue }
        if (-not $r.UpDone) { $skip++; continue }

        $doneAt = [datetime]$r.UpDone
        $wakeAt = $doneAt.AddMinutes(-$leadMin)
        if ($wakeAt -le $now.AddMinutes(2)) { $skip++; continue }

        $list += [pscustomobject]@{
            Index   = $idx
            WakeAt  = $wakeAt.ToString('yyyy-MM-ddTHH:mm:ss')
            DoneAt  = $doneAt.ToString('yyyy-MM-ddTHH:mm:ss')
            Upgrade = ('{0} Lv.{1}' -f $r.UpName, $r.UpLvl)
            Since   = $now.ToString('yyyy-MM-ddTHH:mm:ss')
        }
        try {
            Start-Process -FilePath $MuMuMgr -ArgumentList 'control', '-v', $idx, 'shutdown' -WindowStyle Hidden | Out-Null
            Write-GuardLog 'SLEEP' "实例$idx" ("批量休眠，{0} 唤醒" -f $wakeAt.ToString('HH:mm'))
            $n++
        } catch {
            Write-Diag "批量休眠实例 $idx 失败: $($_.Exception.Message)"
        }
    }

    Save-SleepList $list
    if (@($list).Count -gt 0) { Start-Waker }
    return [pscustomobject]@{ Slept = $n; Skipped = $skip }
}

# 全部唤醒：把所有休眠任务改成立即执行
function Invoke-BatchWake {
    $list = @(Get-SleepList)
    if ($list.Count -eq 0) { return 0 }
    $nowStr = (Get-Date).ToString('yyyy-MM-ddTHH:mm:ss')
    $n = 0
    foreach ($e in $list) {
        $e.WakeAt = $nowStr
        $n++
    }
    Save-SleepList $list
    Start-Waker
    Write-GuardLog 'WAKE_MANUAL' '-' '批量唤醒'
    return $n
}
