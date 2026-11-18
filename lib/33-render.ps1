# 新界面的数据渲染与分页（与 32-shell.ps1 配套）
# 约定：所有更新入口是 Update-Ui（覆盖 30-ui.ps1 里的同名函数）

$script:shellPage = 1
$script:shellFilter = 'all'

function Switch-ShellPage([int]$n) {
    if (-not $script:shellWin) { return }
    if ($n -lt 1 -or $n -gt 5) { return }
    $script:shellPage = $n
    $pages = @('Page1', 'Page2', 'Page3', 'Page4', 'Page5')
    $titles = @(
        @('概览', "$($script:shellSummary)"),
        @('实例管理', '对每个实例单独启动、唤醒、重启或暂停检测'),
        @('健康检查', '系统层面的内存、服务与权限状态'),
        @('事件记录', '最近的守护动作与异常'),
        @('设置', '阈值、路径与休眠规则')
    )
    for ($i = 1; $i -le 5; $i++) {
        $pg = $script:shellWin.FindName($pages[$i - 1])
        $nv = $script:shellWin.FindName("Nav$i")
        $ico = $script:shellWin.FindName("Nav$i" + 'Ico')
        $txt = $script:shellWin.FindName("Nav$i" + 'Txt')
        $on = ($i -eq $n)
        if ($pg) { $pg.Visibility = $(if ($on) { 'Visible' } else { 'Collapsed' }) }
        if ($nv) { $nv.Background = $(if ($on) { Brush '#24FFFFFF' } else { [System.Windows.Media.Brushes]::Transparent }) }
        if ($ico) { $ico.Foreground = $(if ($on) { Brush '#F2F2F5' } else { Brush '#9E9EA6' }) }
        if ($txt) {
            $txt.Foreground = $(if ($on) { Brush '#F2F2F5' } else { Brush '#9E9EA6' })
            $txt.FontWeight = $(if ($on) { 'SemiBold' } else { 'Normal' })
        }
    }
    $t = $script:shellWin.FindName('TxtTitle')
    $s = $script:shellWin.FindName('TxtSub')
    if ($t) { $t.Text = $titles[$n - 1][0] }
    if ($s) { $s.Text = $titles[$n - 1][1] }
}

function Initialize-Shell {
    param($Win, $Logo, $InstanceIcon)

    $script:shellWin = $Win
    $script:shellLogo = $Logo
    $script:shellIcon = $InstanceIcon
    $script:shellRowsSig = ''
    $script:shellContent = $Win.Content
    $script:viewMode = 'shell'

    foreach ($pair in @(@('BtnFAll', 'all'), @('BtnFWarn', 'warn'), @('BtnFSleep', 'sleep'))) {
        $btn = $Win.FindName($pair[0])
        if ($btn) {
            $mode = $pair[1]
            $btn.Add_MouseLeftButtonUp({ $script:shellFilter = $mode; Update-FilterChips; Update-Ui }.GetNewClosure())
        }
    }
    Update-FilterChips

    # 导航
    1..5 | ForEach-Object {
        $idx = $_
        $nav = $Win.FindName("Nav$idx")
        if ($nav) { $nav.Add_MouseLeftButtonUp({ Switch-ShellPage $idx; Update-Ui }.GetNewClosure()) }
    }
    # 标题栏按钮
    $r = $Win.FindName('BtnRefresh')
    if ($r) { $r.Add_MouseLeftButtonUp({ Update-Ui; Write-Diag '界面：手动刷新' }) }
    $cp = $Win.FindName('BtnCompact')
    if ($cp) { $cp.Add_MouseLeftButtonUp({ Set-View 'compact'; Update-Ui }) }
    $m = $Win.FindName('BtnMin')
    if ($m) { $m.Add_MouseLeftButtonUp({ $Win.WindowState = 'Minimized' }) }
    $h = $Win.FindName('BtnHide')
    if ($h) { $h.Add_MouseLeftButtonUp({ Hide-Panel }) }
    $gb = $Win.FindName('BtnGuardRun')
    if ($gb) { $gb.Add_MouseLeftButtonUp({ Set-GuardState; Update-Ui }) }
    $sb = $Win.FindName('BtnSleepRun')
    if ($sb) { $sb.Add_MouseLeftButtonUp({ $script:cfg.AutoSleep = -not [bool]$script:cfg.AutoSleep; Save-Config; Update-Ui }) }
    $cb = $Win.FindName('BtnCleanNow')
    if ($cb) { $cb.Add_MouseLeftButtonUp({ try { [void](Invoke-GuardCleanup) } catch { }; Update-Ui }) }
    $lg = $Win.FindName('BtnOpenLog')
    if ($lg) { $lg.Add_MouseLeftButtonUp({ if (Test-Path $LogDir) { Start-Process explorer.exe -ArgumentList $LogDir } }) }
    $ex = $Win.FindName('BtnExportRep')
    if ($ex) { $ex.Add_MouseLeftButtonUp({ try { Export-Report } catch { Write-Diag "导出失败: $($_.Exception.Message)" } }) }
    $up = $Win.FindName('BtnCheckUpd')
    if ($up) { $up.Add_MouseLeftButtonUp({ try { Invoke-UpdateCheckUI -Silent $false } catch { } }) }
    $rb = $Win.FindName('BtnRemoteOpen')
    if ($rb) { $rb.Add_MouseLeftButtonUp({ try { Show-RemoteDialog } catch { Write-Diag "手机访问窗口异常: $($_.Exception.Message)" } }) }
    $na = $Win.FindName('NavAnnounce2'); if ($na) { $na.Add_MouseLeftButtonUp({ try { Show-Announcement -Force } catch { } }) }
    $root = $Win.FindName('Root')
    if ($root) { $root.Add_MouseLeftButtonDown({ try { $Win.DragMove() } catch { } }) }

    $startPage = 1
    if ($env:MMG_PAGE) { try { $startPage = [int]$env:MMG_PAGE } catch { } }
    Switch-ShellPage $startPage
    if ($env:MMG_COMPACT -eq '1') { Set-View 'compact' } else { Set-View 'shell' }
}

# ---------- 小工具 ----------
function New-ShellText {
    param([string]$Text, [double]$Size = 11, [string]$Color = '#9E9EA6', [string]$Weight = 'Normal')
    $t = New-Object System.Windows.Controls.TextBlock
    $t.Text = $Text
    $t.FontSize = $Size
    $t.FontWeight = $Weight
    $t.Foreground = Brush $Color
    $t.VerticalAlignment = 'Center'
    $t.TextTrimming = 'CharacterEllipsis'
    return $t
}

function New-ShellPill {
    param([string]$Text, [string]$Fg, [string]$Bg)
    $b = New-Object System.Windows.Controls.Border
    $b.CornerRadius = [System.Windows.CornerRadius]::new(20)
    $b.Padding = New-Object System.Windows.Thickness(8, 3, 8, 3)
    $b.Background = Brush $Bg
    $b.VerticalAlignment = 'Center'
    $t = New-ShellText $Text 10 $Fg
    $b.Child = $t
    return $b
}

function New-ShellButton {
    param([string]$Text, [string]$Fg, [string]$Bg, [scriptblock]$OnClick, [double]$Width = 0)
    $b = New-Object System.Windows.Controls.Border
    $b.CornerRadius = [System.Windows.CornerRadius]::new(7)
    $b.Padding = New-Object System.Windows.Thickness(10, 4, 10, 4)
    $b.Background = Brush $Bg
    $b.VerticalAlignment = 'Center'
    $b.Cursor = 'Hand'
    if ($Width -gt 0) { $b.Width = $Width }
    $t = New-ShellText $Text 10.5 $Fg
    $b.Child = $t
    if ($OnClick) { $b.Add_MouseLeftButtonUp($OnClick) }
    return $b
}

# ---------- 行数据：运行中 + 休眠中 合并 ----------
function Get-ShellRows {
    $data = @(Get-InstanceData)
    if ($script:testNoCollect -and $script:testRows) { return $script:testRows }
    $script:lastInstances = $data
    $sleep = @(Get-SleepList)
    $sleepMap = @{}
    foreach ($s in $sleep) { if ($null -ne $s) { $sleepMap["$($s.Index)"] = $s } }

    $runIdx = @{}
    foreach ($r in $data) { $runIdx["$($r.Index)"] = $true }

    $rows = @($data)
    foreach ($s in $sleep) {
        $si = "$($s.Index)"
        if ($runIdx.ContainsKey($si)) { continue }
        $wakeAt = $null
        try { $wakeAt = [datetime]::Parse("$($s.WakeAt)") } catch { }
        $sic = if ($script:instanceMap -and $script:instanceMap.ContainsKey($si)) { $script:instanceMap[$si] } else { $null }
        $rows += [pscustomobject]@{
            Index = $si; Detect = $false
            Name = (Get-InstanceDisplayName -Config $sic -Aliases $script:cfg.Aliases)
            PID = "sleep-$si"; Cores = -1; Private = 0; WS = 0; CEF = 0; MemPct = 0
            MemBase = $(if ($sic) { $sic.MemBaseMB } else { 0 })
            GuestGB = $(if ($sic) { $sic.MemoryGB } else { 0 })
            Online = $null; Script = $null; Game = $null; Spin = $null
            UpName = ''; UpLvl = 0; UpDone = $null; UpLeft = ''
            Judge = '休眠中'; Level = 0; Sleeping = $true; WakeAt = $wakeAt
        }
    }

    # 既没运行也没休眠的：按发现列表补成「已关机」
    $have = @{}
    foreach ($r in $rows) { $have["$($r.Index)"] = $true }
    foreach ($k in @($script:instanceMap.Keys)) {
        $ks = "$k"
        if ($have.ContainsKey($ks)) { continue }
        $sic = $script:instanceMap[$ks]
        $rows += [pscustomobject]@{
            Index = $ks; Detect = $false
            Name = (Get-InstanceDisplayName -Config $sic -Aliases $script:cfg.Aliases)
            PID = $null; Cores = 0; Private = 0; WS = 0; CEF = 0; MemPct = 0
            MemBase = $(if ($sic) { $sic.MemBaseMB } else { 0 })
            GuestGB = $(if ($sic) { $sic.MemoryGB } else { 0 })
            Online = $false; Script = $false; Game = $false; Spin = $false
            UpName = ''; UpLvl = 0; UpDone = $null; UpLeft = ''
            Judge = '已关机'; Level = 0
        }
    }

    $out = @()
    foreach ($r in @($rows | Sort-Object { [int]($_.Index -replace '[^\d]', '0') })) {
        $w = $null
        if ($r.PSObject.Properties.Name -contains 'WakeAt' -and $r.WakeAt) { $w = $r.WakeAt }
        elseif ($sleepMap.ContainsKey("$($r.Index)")) { $w = $sleepMap["$($r.Index)"].WakeAt }
        $o = $r | Select-Object *
        [void]($o | Add-Member -NotePropertyName WakeAt -NotePropertyValue $w -Force)
        $out += $o
    }
    $script:testRows = $out
    return $out
}
# ---------- 页1 概览 ----------
function Render-ShellOverview {
    $win = $script:shellWin
    $rows = @(Get-ShellRows)
    $sleep = @(Get-SleepList)
    $run = @($rows | Where-Object { $_.Script -eq $true })
    $slp = @($rows | Where-Object { $_.WakeAt })
    $off = @($rows | Where-Object { -not $_.WakeAt -and $_.Script -ne $true -and -not $_.Online })
    $script:shellSummary = "$($rows.Count) 个实例 · $($run.Count) 个运行 · $($slp.Count) 个休眠"

    $st = $win.FindName('StatTotal'); if ($st) { $total = @($script:instanceMap.Keys).Count; if ($total -lt $rows.Count) { $total = $rows.Count }; $st.Text = "$total" }
    $sr = $win.FindName('StatRun');   if ($sr) { $sr.Text = "$($run.Count)" }
    $ss = $win.FindName('StatSleep'); if ($ss) { $ss.Text = "$($slp.Count)" }
    $so = $win.FindName('StatOff');   if ($so) { $total = @($script:instanceMap.Keys).Count; if ($total -lt $rows.Count) { $total = $rows.Count }; $so.Text = "$([math]::Max(0, $total - $run.Count - $slp.Count))" }

    # 实例行：概览只显示运行中 / 休眠中的，关机的只在统计卡里计数
    $viewRows = @($rows | Where-Object { $_.WakeAt -or $_.Script -eq $true -or $_.Online -eq $true })
    $pnl = $win.FindName('PnlInstances')
    if ($pnl) {
        $pnl.Children.Clear()
        if ($viewRows.Count -eq 0) {
            $empty = New-ShellText '所有实例都已关机' 11 '#6E6E78'
            $empty.Margin = New-Object System.Windows.Thickness(12, 8, 12, 14)
            [void]$pnl.Children.Add($empty)
        }
        foreach ($r in $viewRows) {
            $isSleep = [bool]$r.WakeAt
            $isOff = $false
            $row = New-InstanceRowShell -Row $r -Icon $script:shellIcon -IsSleep $isSleep -IsOff $isOff
            [void]$pnl.Children.Add($row)
            $sep = New-Object System.Windows.Controls.Border
            $sep.Height = 1
            $sep.Background = Brush '#0DFFFFFF'
            $sep.Margin = New-Object System.Windows.Thickness(12, 0, 12, 0)
            [void]$pnl.Children.Add($sep)
        }
    }

    # 事件（最近 4 条）
    Render-ShellEvents -Target 'PnlEvents' -Limit 4

    # 内存
    $hm = Get-HostMemory
    if ($hm) {
        $used = $script:totalMB - $hm.AvailableMB
        $usedGB = $used / 1024.0
        $totalGB = $script:totalMB / 1024.0
        $u = $win.FindName('TxtMemUsed'); if ($u) { $u.Text = ('{0:N1}' -f $usedGB) }
        $tt = $win.FindName('TxtMemTotal'); if ($tt) { $tt.Text = ('/ {0:N1} GB' -f $totalGB) }
        $lg = $win.FindName('TxtMemUsedLg'); if ($lg) { $lg.Text = ('已用 {0:N1} GB' -f $usedGB) }
        $lf = $win.FindName('TxtMemFreeLg'); if ($lf) { $lf.Text = ('可用 {0:N1} GB' -f ($hm.AvailableMB / 1024.0)) }
        $bar = $win.FindName('MemBar')
        if ($bar -and $totalGB -gt 0) {
            $pct = [math]::Min(100, [math]::Max(2, ($usedGB / $totalGB) * 100))
            $bar.Width = 212 * $pct / 100
        }
    }

    # 健康摘要
    $items = @(Get-Health $hm)
    $bad = @($items | Where-Object { -not $_.Ok })
    $hl = $win.FindName('TxtHealthLine'); $hd = $win.FindName('HealthDot2')
    if ($hl) { $hl.Text = '系统健康 · ' + $(if ($bad.Count -eq 0) { '检查通过' } else { "$($bad.Count) 项需处理" }) }
    if ($hd) { $hd.Fill = Brush $(if ($bad.Count -eq 0) { '#34C759' } else { '#FF9F0A' }) }
    $gl = $win.FindName('HealthGlyph'); $ht = $win.FindName('TxtHealthTitle'); $hs = $win.FindName('TxtHealthSub')
    if ($ht) { $ht.Text = $(if ($bad.Count -eq 0) { '检查通过' } else { "$($bad.Count) 项需处理" }) }
    if ($hs) { $hs.Text = $(if ($bad.Count -eq 0) { '系统服务与资源状态正常' } else { ($bad | ForEach-Object { $_.Name }) -join '、' }) }
    if ($gl) {
        $gl.Text = $(if ($bad.Count -eq 0) { '✓' } else { '!' })
        $gl.Foreground = Brush $(if ($bad.Count -eq 0) { '#34C759' } else { '#FF9F0A' })
    }

    # 快捷操作按钮状态
    $guardOn = [bool]$script:cfg.GuardRunning
    $gb = $win.FindName('BtnGuardRun'); $gt = $win.FindName('TxtGuardRun')
    if ($gb -and $gt) {
        if ($guardOn) {
            $gb.Background = Brush '#1E3A2A'
            $gt.Text = '看护中 · 点击停止'
            $gt.Foreground = Brush '#34C759'
        } else {
            $gb.Background = Brush '#F2F2F5'
            $gt.Text = '开始看护'
            $gt.Foreground = Brush '#1B1B1F'
        }
    }
    $sOn = [bool]$script:cfg.AutoSleep
    $sb = $win.FindName('BtnSleepRun'); $stx = $win.FindName('TxtSleepRun')
    if ($sb -and $stx) {
        if ($sOn) {
            $sb.Background = Brush '#2A2415'
            $stx.Text = '自动休眠 开'
            $stx.Foreground = Brush '#FF9F0A'
        } else {
            $sb.Background = Brush '#1AFFFFFF'
            $stx.Text = '自动休眠 关'
            $stx.Foreground = Brush '#9E9EA6'
        }
    }

    # 唤醒 / 休眠统计
    $next = $null
    if ($sleep.Count -gt 0) { $next = @($sleep | Sort-Object { [datetime]$_.WakeAt } | Select-Object -First 1) }
    $nw = $win.FindName('TxtNextWake')
    if ($nw) { $nw.Text = $(if ($next) { ([datetime]$next[0].WakeAt).ToString('HH:mm') } else { '—' }) }
    $tc = Get-TodayCounts
    $sd = $win.FindName('TxtSleepToday'); $sd2 = $win.FindName('TxtSleepToday2')
    if ($sd) { $sd.Text = "$($tc.sleep) 次" }
    if ($sd2) { $sd2.Text = "$($tc.sleep)" }
    $wt = $win.FindName('TxtWakeToday'); if ($wt) { $wt.Text = "$($tc.wake) 次" }
    $ct = $win.FindName('TxtCleanToday'); if ($ct) { $ct.Text = "$($tc.clean) 次" }
    $rt = $win.FindName('TxtRecoverToday'); if ($rt) { $rt.Text = "$($tc.recover) 次" }
}

# ---------- 页2 实例管理 ----------
function Render-ShellManage {
    $win = $script:shellWin
    $pnl = $win.FindName('PnlManage')
    if (-not $pnl) { return }
    $pnl.Children.Clear()

    foreach ($r in @(Get-ShellRows)) {
        $isSleep = [bool]$r.WakeAt
        $idx = "$($r.Index)"
        $g = New-Object System.Windows.Controls.Grid
        $g.Height = 58
        $g.Margin = New-Object System.Windows.Thickness(10, 0, 10, 0)
        foreach ($w in @('Auto', '*', '116', '150')) {
            $cd = New-Object System.Windows.Controls.ColumnDefinition
            if ($w -eq '*') { $cd.Width = [System.Windows.GridLength]::new(1, [System.Windows.GridUnitType]::Star) }
            elseif ($w -eq 'Auto') { $cd.Width = [System.Windows.GridLength]::Auto }
            else { $cd.Width = [System.Windows.GridLength]::new([double]$w) }
            [void]$g.ColumnDefinitions.Add($cd)
        }

        $ico = New-Object System.Windows.Controls.Border
        $ico.Width = 26; $ico.Height = 26
        $ico.CornerRadius = [System.Windows.CornerRadius]::new(8)
        $ico.VerticalAlignment = 'Center'
        $img = New-Object System.Windows.Controls.Image
        $img.Stretch = 'UniformToFill'
        if ($script:shellIcon) { $img.Source = $script:shellIcon }
        if (-not $r.Online) { $img.Opacity = 0.4 }
        $ico.Child = $img
        [void]$g.Children.Add($ico)

        $sp = New-Object System.Windows.Controls.StackPanel
        $sp.Margin = New-Object System.Windows.Thickness(10, 0, 0, 0)
        $sp.VerticalAlignment = 'Center'
        [void]$sp.Children.Add((New-ShellText "$($r.Name)" 12.5 '#F2F2F5'))
        $sub = New-ShellText ("{0} · {1}" -f $r.Judge, $(if ($r.UpName) { "$($r.UpName) Lv.$($r.UpLvl)" } else { '无升级任务' })) 10.5 '#6E6E78'
        $sub.Margin = New-Object System.Windows.Thickness(0, 2, 0, 0)
        [void]$sp.Children.Add($sub)
        [System.Windows.Controls.Grid]::SetColumn($sp, 1)
        [void]$g.Children.Add($sp)

        $ops = New-Object System.Windows.Controls.StackPanel
        $ops.Orientation = 'Horizontal'
        $ops.HorizontalAlignment = 'Right'
        $ops.VerticalAlignment = 'Center'

        $detOff = (@($script:cfg.DetectOff | Where-Object { $_ -ne $null }) -contains $idx)
        $btnDet = New-ShellButton $(if ($detOff) { '已暂停' } else { '检测中' }) $(if ($detOff) { '#6E6E78' } else { '#9E9EA6' }) '#1AFFFFFF' ({
            $cur = @($script:cfg.DetectOff | Where-Object { $_ -ne $null -and "$_" -ne '' })
            if (@($cur | Where-Object { "$_" -eq $idx }).Count -gt 0) {
                $script:cfg.DetectOff = @($cur | Where-Object { "$_" -ne $idx })
            } else {
                $script:cfg.DetectOff = @($cur + $idx)
            }
            Save-Config
            Update-Ui
        }.GetNewClosure())
        $btnDet.Margin = New-Object System.Windows.Thickness(0, 0, 6, 0)
        [void]$ops.Children.Add($btnDet)

        $actText = $(if ($isSleep) { '唤醒' } elseif ($r.Online) { '重启' } else { '启动' })
        $btnAct = New-ShellButton $actText '#1F1F23' '#F2F2F5' ({
            if ($isSleep) {
                try { Remove-SleepEntry $idx; Start-Instance "$idx"; Write-GuardLog 'WAKE_MANUAL' "实例$idx" '手动唤醒' } catch { }
            } elseif ($r.Online) {
                try { Start-InstanceRecover $idx } catch { }
            } else {
                try { Start-Instance "$idx" } catch { }
            }
            Start-Sleep -Milliseconds 500
            Update-Ui
        }.GetNewClosure())
        [void]$ops.Children.Add($btnAct)

        [System.Windows.Controls.Grid]::SetColumn($ops, 3)
        [void]$g.Children.Add($ops)

        [void]$pnl.Children.Add($g)
        $sep = New-Object System.Windows.Controls.Border
        $sep.Height = 1; $sep.Background = Brush '#0DFFFFFF'
        $sep.Margin = New-Object System.Windows.Thickness(10, 0, 10, 0)
        [void]$pnl.Children.Add($sep)
    }
}

# ---------- 页3 健康检查 ----------
function Render-ShellHealth {
    $win = $script:shellWin
    $pnl = $win.FindName('PnlHealthDetail')
    if (-not $pnl) { return }
    $pnl.Children.Clear()
    foreach ($it in @(Get-Health)) {
        $g = New-Object System.Windows.Controls.Grid
        $g.Height = 52
        $g.Margin = New-Object System.Windows.Thickness(0, 0, 0, 0)
        $cd0 = New-Object System.Windows.Controls.ColumnDefinition
        $cd0.Width = [System.Windows.GridLength]::new(1, [System.Windows.GridUnitType]::Star)
        [void]$g.ColumnDefinitions.Add($cd0)
        $cd1 = New-Object System.Windows.Controls.ColumnDefinition
        $cd1.Width = [System.Windows.GridLength]::Auto
        [void]$g.ColumnDefinitions.Add($cd1)

        $sp = New-Object System.Windows.Controls.StackPanel
        $sp.VerticalAlignment = 'Center'
        [void]$sp.Children.Add((New-ShellText "$($it.Name)" 12 '#F2F2F5'))
        $sub = New-ShellText "$($it.Text)" 10.5 '#6E6E78'
        $sub.Margin = New-Object System.Windows.Thickness(0, 2, 0, 0)
        [void]$sp.Children.Add($sub)
        [void]$g.Children.Add($sp)

        $pill = New-ShellPill $(if ($it.Ok) { '正常' } else { '需处理' }) $(if ($it.Ok) { '#34C759' } else { '#FF9F0A' }) $(if ($it.Ok) { '#2934C759' } else { '#29FF9F0A' })
        [System.Windows.Controls.Grid]::SetColumn($pill, 1)
        [void]$g.Children.Add($pill)

        [void]$pnl.Children.Add($g)
        $sep = New-Object System.Windows.Controls.Border
        $sep.Height = 1; $sep.Background = Brush '#0DFFFFFF'
        [void]$pnl.Children.Add($sep)
    }
}

# ---------- 页4 事件 ----------
function Render-ShellEvents {
    param([string]$Target = 'PnlEventDetail', [int]$Limit = 40)
    $win = $script:shellWin
    $pnl = $win.FindName($Target)
    if (-not $pnl) { return }

    $file = Get-LogFile
    $rows = @()
    if (Test-Path $file) { try { $rows = @(Import-Csv $file -ErrorAction Stop) } catch { } }
    if ($script:shellFilter -eq 'warn') {
        $warn = @('LOW_MEM', 'ALERT_SPIN', 'ALERT_MEM', 'ALERT_SCRIPT', 'RECOVER_FAIL', 'CEF_HIGH', 'ROOT_FAIL', 'SLEEP_FAIL', 'WAKE_LATE')
        $rows = @($rows | Where-Object { $warn -contains $_.Action })
    } elseif ($script:shellFilter -eq 'sleep') {
        $rows = @($rows | Where-Object { $_.Action -in @('SLEEP', 'SLEEP_BG', 'WAKE_MANUAL', 'WAKE_LATE') })
    }
    if ($rows.Count -gt 1) { [array]::Reverse($rows) }
    $rows = @($rows | Select-Object -First $Limit)

    $pnl.Children.Clear()
    if ($rows.Count -eq 0) {
        [void]$pnl.Children.Add((New-ShellText '今天还没有事件' 11 '#6E6E78'))
        return
    }
    foreach ($r in $rows) {
        $level = 'info'
        if ($r.Action -match 'FAIL|ALERT|LATE|HIGH') { $level = 'err' }
        elseif ($r.Action -match 'SLEEP|WAKE|RECOVER|LOW_MEM') { $level = 'warn' }
        elseif ($r.Action -match 'OK|CLEAN') { $level = 'ok' }
        [void]$pnl.Children.Add((New-EventRowShell -Time $r.Time.Substring(11) -Text ("{0} {1}" -f $r.Detail, $(if ($r.Instance) { "($($r.Instance))" } else { '' })) -Level $level))
    }
}

# ---------- 页5 设置 ----------
function Render-ShellSettings {
    $win = $script:shellWin
    $pnl = $win.FindName('PnlSettings')
    if (-not $pnl) { return }
    $pnl.Children.Clear()

    $defs = @(
        @{ K = 'AutoSleep';        L = '自动休眠';        D = '脚本在等升级时关掉模拟器省内存，升级前自动唤醒'; T = 'bool' }
        @{ K = 'SleepBackground';  L = '后台也休眠';      D = '游戏退到后台时也允许休眠';                     T = 'bool' }
        @{ K = 'SleepIdleMin';     L = '后台空闲判定';    D = '游戏退到后台多少分钟后才算「在等升级」';        T = 'min' }
        @{ K = 'SleepLeadMin';     L = '提前唤醒';        D = '升级完成前多少分钟把模拟器打开';               T = 'min' }
        @{ K = 'SleepMinHours';    L = '最短休眠';        D = '剩余时间短于这个值就不睡，省得反复开关机';      T = 'hour' }
        @{ K = 'SleepMaxHours';    L = '最长休眠';        D = '剩余时间超过这个值就不睡（比如两天以上）';      T = 'hour' }
        @{ K = 'AutoRecover';      L = '掉线自动恢复';    D = '脚本或游戏掉线时自动重启实例并重新拉起脚本';    T = 'bool' }
        @{ K = 'RecoverCheckSec';  L = '检测间隔';        D = '每隔多少秒检查一次实例是否掉线';               T = 'sec' }
        @{ K = 'RecoverFailCount'; L = '连续几次判定掉线'; D = '连续失败这么多次才重启，避免误判';              T = 'time' }
        @{ K = 'CefAlert';         L = 'CEF 告警阈值';    D = '单个实例的 CEF 进程超过这个数就清理';           T = 'cnt' }
        @{ K = 'LogKeepDays';      L = '日志保留';        D = '超过这个天数的日志会自动删除';                 T = 'day' }
    )

    $first = $true
    foreach ($d in $defs) {
        $row = New-Object System.Windows.Controls.Grid
        $row.Height = 52
        $row.Background = [System.Windows.Media.Brushes]::Transparent
        $c0 = New-Object System.Windows.Controls.ColumnDefinition
        $c0.Width = [System.Windows.GridLength]::new(1, [System.Windows.GridUnitType]::Star)
        $c1 = New-Object System.Windows.Controls.ColumnDefinition
        $c1.Width = [System.Windows.GridLength]::Auto
        [void]$row.ColumnDefinitions.Add($c0)
        [void]$row.ColumnDefinitions.Add($c1)

        $left = New-Object System.Windows.Controls.StackPanel
        $left.VerticalAlignment = 'Center'
        [void]$left.Children.Add((New-ShellText $d.L 12 '#F2F2F5'))
        $sub = New-ShellText $d.D 9.5 '#6E6E78'
        $sub.Margin = New-Object System.Windows.Thickness(0, 2, 0, 0)
        [void]$left.Children.Add($sub)
        [void]$row.Children.Add($left)

        $v = $script:cfg[$d.K]
        $key = $d.K; $label = $d.L; $desc = $d.D
        if ($d.T -eq 'bool') {
            $on = [bool]$v
            $pill = New-Object System.Windows.Controls.Border
            $pill.Width = 38; $pill.Height = 22
            $pill.CornerRadius = [System.Windows.CornerRadius]::new(11)
            $pill.Background = Brush $(if ($on) { '#34C759' } else { '#3A3A42' })
            $knob = New-Object System.Windows.Shapes.Ellipse
            $knob.Width = 18; $knob.Height = 18
            $knob.Fill = Brush '#FFFFFF'
            $knob.HorizontalAlignment = $(if ($on) { 'Right' } else { 'Left' })
            $knob.Margin = New-Object System.Windows.Thickness(2, 0, 2, 0)
            $pill.Child = $knob
            $pill.Cursor = 'Hand'
            [System.Windows.Controls.Grid]::SetColumn($pill, 1)
            $pill.Add_MouseLeftButtonUp({
                $script:cfg[$key] = -not [bool]$script:cfg[$key]
                Save-Config
                Update-Ui
            })
            [void]$row.Children.Add($pill)
        } else {
            $txt = switch ($d.T) {
                'min'  { "$v 分钟" }
                'hour' { "$v 小时" }
                'sec'  { "$v 秒" }
                'cnt'  { "$v 个" }
                'day'  { "$v 天" }
                default { "$v 次" }
            }
            $btn = New-Object System.Windows.Controls.Border
            $btn.CornerRadius = [System.Windows.CornerRadius]::new(7)
            $btn.Padding = New-Object System.Windows.Thickness(9, 4, 9, 4)
            $btn.Background = Brush '#1AFFFFFF'
            $btn.Cursor = 'Hand'
            $btn.VerticalAlignment = 'Center'
            $bt = New-ShellText $txt 11.5 '#E6E6EC'
            $btn.Child = $bt
            [System.Windows.Controls.Grid]::SetColumn($btn, 1)
            $unit = switch ($d.T) { 'min' { '分钟' } 'hour' { '小时' } 'sec' { '秒' } 'cnt' { '个' } 'day' { '天' } default { '次' } }
            $btn.Add_MouseLeftButtonUp({
                Show-SettingInput -Key $key -Label $label -Desc $desc -Value $script:cfg[$key] -Unit $unit
            })
            [void]$row.Children.Add($btn)
        }

        [void]$pnl.Children.Add($row)
        $sep = New-Object System.Windows.Controls.Border
        $sep.Height = 1; $sep.Background = Brush '#0DFFFFFF'
        [void]$pnl.Children.Add($sep)
    }

    # 主题
    $mode = "$($script:cfg.Theme)"; if (-not $mode) { $mode = 'auto' }
    $modeText = switch ($mode) { 'light' { '浅色' } 'dark' { '深色' } default { '跟随系统' } }
    $rowT = New-Object System.Windows.Controls.Grid
    $rowT.Height = 44
    $c0 = New-Object System.Windows.Controls.ColumnDefinition; $c0.Width = [System.Windows.GridLength]::new(1, [System.Windows.GridUnitType]::Star)
    $c1 = New-Object System.Windows.Controls.ColumnDefinition; $c1.Width = [System.Windows.GridLength]::Auto
    [void]$rowT.ColumnDefinitions.Add($c0); [void]$rowT.ColumnDefinitions.Add($c1)
    $lt = New-ShellText '主题（点击切换）' 12 '#F2F2F5'
    [void]$rowT.Children.Add($lt)
    $vt = New-ShellText $modeText 11.5 '#6E6E78'
    [System.Windows.Controls.Grid]::SetColumn($vt, 1)
    [void]$rowT.Children.Add($vt)
    $rowT.Cursor = 'Hand'
    $rowT.Add_MouseLeftButtonUp({
        $cur = "$($script:cfg.Theme)"
        $next = switch ($cur) { 'auto' { 'dark' } 'dark' { 'light' } default { 'auto' } }
        Set-Theme $next
        Update-Ui
    })
    [void]$pnl.Children.Add($rowT)

    $sepT = New-Object System.Windows.Controls.Border
    $sepT.Height = 1; $sepT.Background = Brush '#0DFFFFFF'
    [void]$pnl.Children.Add($sepT)

    # 清除记忆
    $rowM = New-Object System.Windows.Controls.Grid
    $rowM.Height = 44
    $m0 = New-Object System.Windows.Controls.ColumnDefinition; $m0.Width = [System.Windows.GridLength]::new(1, [System.Windows.GridUnitType]::Star)
    $m1 = New-Object System.Windows.Controls.ColumnDefinition; $m1.Width = [System.Windows.GridLength]::Auto
    [void]$rowM.ColumnDefinitions.Add($m0); [void]$rowM.ColumnDefinitions.Add($m1)
    [void]$rowM.Children.Add((New-ShellText '清除记忆' 12 '#F2F2F5'))
    $vm = New-ShellText '删除休眠任务与统计' 10 '#6E6E78'
    [System.Windows.Controls.Grid]::SetColumn($vm, 1)
    [void]$rowM.Children.Add($vm)
    $rowM.Cursor = 'Hand'
    $rowM.Add_MouseLeftButtonUp({ try { Show-ClearMemoryDialog } catch { Write-Diag "清除记忆失败: $($_.Exception.Message)" } })
    [void]$pnl.Children.Add($rowM)

    $foot = New-ShellText ("MuMu 安装目录：{0}    版本 {1}" -f $MuMuRoot, $script:appVersion) 10 '#6E6E78'
    $foot.Margin = New-Object System.Windows.Thickness(0, 10, 0, 0)
    [void]$pnl.Children.Add($foot)
}

# ---------- 总入口（覆盖 30-ui.ps1 的实现） ----------
function Update-Ui {
    if (-not $script:shellWin) { return }
    try {
        if ($script:viewMode -eq 'compact') { Render-Compact; return }
        switch ($script:shellPage) {
            1 { Render-ShellOverview }
            2 { Render-ShellManage }
            3 { Render-ShellHealth }
            4 { Render-ShellEvents -Target 'PnlEventDetail' -Limit 40 }
            5 { Render-ShellSettings }
        }
    } catch {
        Write-Diag ("界面刷新异常: " + $_.Exception.Message + " @ " + $_.InvocationInfo.ScriptLineNumber)
    }
}

# ---------- 今日统计 ----------
function Get-TodayCounts {
    $c = @{ wake = 0; clean = 0; recover = 0; sleep = 0 }
    try {
        $file = Get-LogFile
        if (Test-Path $file) {
            $today = (Get-Date).ToString('yyyy-MM-dd')
            foreach ($r in @(Import-Csv $file)) {
                if (-not ("$($r.Time)" -like "$today*")) { continue }
                $a = "$($r.Action)"
                if ($a -like '*WAKE*') { $c.wake++ }
                elseif ($a -like '*CLEAN*') { $c.clean++ }
                elseif ($a -like '*RECOVER*' -or $a -like '*RESTART*') { $c.recover++ }
                elseif ($a -like '*SLEEP*') { $c.sleep++ }
            }
        }
    } catch { }
    return $c
}

# ---------- 紧凑视图 ----------
function Render-Compact {
    $win = $script:shellWin
    if (-not $win) { return }
    $root = $script:compactRoot
    if (-not $root) { return }

    $rows = @(Get-ShellRows)
    $sleep = @(Get-SleepList)
    $cntRun = @($rows | Where-Object { $_.Script -eq $true }).Count
    $cntSlp = @($rows | Where-Object { $_.WakeAt }).Count

    $st = $root.FindName('CmpState')
    if ($st) { $st.Text = "$cntRun 跑 · $cntSlp 睡" }
    $dot = $root.FindName('CmpDot')
    if ($dot) {
        $on = [bool]$script:cfg.GuardRunning
        $dot.Fill = Brush $(if ($on) { '#34C759' } else { '#6E6E78' })
    }

    $pnl = $root.FindName('PnlRings')
    if ($pnl) {
        $pnl.Children.Clear()
        foreach ($r in @($rows | Select-Object -First 5)) {
            $short = "$($r.Name)"
            if ($short -like 'MuMu安卓设备-*') { $short = '设备' + ($short -replace '.*-', '') }
            if ($short.Length -gt 5) { $short = $short.Substring(0, 5) }
            $state = 'off'
            $pct = 0
            if ($r.WakeAt) { $state = 'sleep' }
            elseif ($r.Script -eq $true -or $r.Online) {
                $state = 'run'
                $base = [double]$r.MemBase
                if ($base -le 0) { $base = 6144 }
                $pct = [int]([math]::Min(99, [math]::Max(3, ([double]$r.Private / $base) * 100)))
            }
            [void]$pnl.Children.Add((New-RingCell -Row $r -Label $short -Pct $pct -State $state))
        }
    }

    $tw = $root.FindName('TxtCmpWake')
    if ($tw) {
        $next = @($sleep | Sort-Object { [datetime]$_.WakeAt } | Select-Object -First 1)
        $tw.Text = $(if ($next.Count -gt 0) { ([datetime]$next[0].WakeAt).ToString('HH:mm') + ' 唤醒' } else { '无唤醒任务' })
    }
    $tm = $root.FindName('TxtCmpMem')
    if ($tm) {
        $hm = Get-HostMemory
        if ($hm) { $tm.Text = ('内存 {0:N1} GB 可用' -f ($hm.AvailableMB / 1024.0)) }
    }
}

# ---------- 视图切换 ----------
function Set-View([string]$mode) {
    try { Write-Diag "SETVIEW $mode -> $(Get-Date -Format HH:mm:ss)" } catch { }
    $win = $script:shellWin
    if (-not $win) { return }

    if ($mode -eq 'compact') {
        if (-not $script:compactRoot) {
            $script:compactRoot = [Windows.Markup.XamlReader]::Parse((Convert-XamlTheme (Get-CompactXaml)))
            $lg = $script:compactRoot.FindName('CmpLogo')
            if ($lg -and $script:shellLogo) { $lg.Source = $script:shellLogo }
            $script:compactRoot.Add_MouseLeftButtonDown({ try { $win.DragMove() } catch { } })
            $ex = $script:compactRoot.FindName('BtnCmpExpand')
            if ($ex) { $ex.Add_MouseLeftButtonUp({ Set-View 'shell'; Update-Ui }) }
            $cl = $script:compactRoot.FindName('BtnCmpClose')
            if ($cl) { $cl.Add_MouseLeftButtonUp({ Hide-Panel }) }
        }
        if (-not $script:shellContent) { $script:shellContent = $win.Content }
        $win.Content = $script:compactRoot
        $win.MinWidth = 0; $win.MinHeight = 0
        $win.Width = 344; $win.Height = 182
        $script:viewMode = 'compact'
    } else {
        if ($script:shellContent) { $win.Content = $script:shellContent }
        $win.MinWidth = 900; $win.MinHeight = 620
        $win.Width = 1000; $win.Height = 700
        $script:viewMode = 'shell'
    }
    $script:cmpSig = ''
}

# ---------- 筛选按钮 ----------
function Update-FilterChips {
    $win = $script:shellWin
    if (-not $win) { return }
    $map = @{ all = 'BtnFAll'; warn = 'BtnFWarn'; sleep = 'BtnFSleep' }
    foreach ($k in $map.Keys) {
        $b = $win.FindName($map[$k])
        if (-not $b) { continue }
        $on = ($script:shellFilter -eq $k)
        $b.Background = Brush $(if ($on) { '#24FFFFFF' } else { '#1AFFFFFF' })
        if ($b.Child) { $b.Child.Foreground = Brush $(if ($on) { '#F2F2F5' } else { '#9E9EA6' }) }
    }
}
# ---------- 自检：模拟点击所有安全按钮 ----------
function Invoke-UiSelfTest {
    $win = $script:shellWin
    $script:testNoCollect = $true
    $log = Join-Path $LogDir 'uitest.log'
    $lines = @()
    $lines += "===== UI 自检 $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') ====="

    $targets = @('Nav1', 'Nav2', 'Nav3', 'Nav4', 'Nav5', 'BtnRefresh', 'BtnCompact', 'BtnGuardRun', 'BtnSleepRun', 'BtnCleanNow', 'BtnOpenLog')
    foreach ($n in $targets) {
        $el = $win.FindName($n)
        if (-not $el) { $lines += "MISS  $n  元素不存在"; continue }
        try {
            $args = New-Object System.Windows.Input.MouseButtonEventArgs([System.Windows.Input.Mouse]::PrimaryDevice, 0, [System.Windows.Input.MouseButton]::Left)
            $args.RoutedEvent = [System.Windows.UIElement]::MouseLeftButtonUpEvent
            $el.RaiseEvent($args)
            $lines += "PASS  $n"
        } catch {
            $lines += "FAIL  $n  $($_.Exception.Message)  @@ " + $_.ScriptStackTrace
        }
        if ($n -eq 'BtnCompact') { try { Set-View 'shell' } catch { } }
    }

    # 事件筛选按钮
    try { Switch-ShellPage 4 } catch { }
    foreach ($n in @('BtnFAll', 'BtnFWarn', 'BtnFSleep')) {
        $el = $win.FindName($n)
        if (-not $el) { $lines += "MISS  $n  元素不存在"; continue }
        try {
            $args = New-Object System.Windows.Input.MouseButtonEventArgs([System.Windows.Input.Mouse]::PrimaryDevice, 0, [System.Windows.Input.MouseButton]::Left)
            $args.RoutedEvent = [System.Windows.UIElement]::MouseLeftButtonUpEvent
            $el.RaiseEvent($args)
            $lines += "PASS  $n"
        } catch {
            $lines += "FAIL  $n  $($_.Exception.Message)  @@ " + $_.ScriptStackTrace
        }
    }

    # 紧凑视图
    try {
        Set-View 'compact'
        Update-Ui
        $rings = $script:compactRoot.FindName('PnlRings')
        $lines += ("PASS  compact 环数=" + $(if ($rings) { $rings.Children.Count } else { -1 }))
        Set-View 'shell'
        Update-Ui
        $lines += "PASS  回到完整视图"
    } catch {
        $lines += "FAIL  compact  $($_.Exception.Message)"
    }

    # 五页渲染
    foreach ($p in 1..5) {
        try {
            Switch-ShellPage $p
            Update-Ui
            $lines += "PASS  渲染第 $p 页"
        } catch {
            $lines += "FAIL  第 $p 页  $($_.Exception.Message)"
        }
    }

    $lines += "===== 结束 ====="
    try { $lines | Set-Content -Path $log -Encoding UTF8 } catch { }
    $script:testNoCollect = $false
}


# ---------- 设置项编辑对话框 ----------
function Show-SettingInput {
    param([string]$Key, [string]$Label, [string]$Desc, $Value, [string]$Unit)

    $cur = "$Value"
    $xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="修改" Width="360" Height="196"
        WindowStyle="None" AllowsTransparency="True" Background="Transparent"
        WindowStartupLocation="CenterOwner" ShowInTaskbar="False">
  <Border x:Name="Root" CornerRadius="14" Background="#232327" BorderBrush="#33FFFFFF" BorderThickness="1">
    <StackPanel Margin="20,18,20,16">
      <TextBlock x:Name="Ttl" Text="修改" FontSize="14" FontWeight="SemiBold" Foreground="#F2F2F5"/>
      <TextBlock x:Name="Dsc" Text="" FontSize="10.5" Foreground="#6E6E78" TextWrapping="Wrap" Margin="0,4,0,12"/>
      <Border Background="#1A1A1E" CornerRadius="9" BorderBrush="#33FFFFFF" BorderThickness="1" Padding="10,8">
        <TextBox x:Name="Inp" Text="" FontSize="13" Foreground="#F2F2F5" Background="Transparent" BorderThickness="0"/>
      </Border>
      <TextBlock x:Name="Err" Text="" FontSize="10" Foreground="#FF6B6B" Margin="2,6,0,0"/>
      <StackPanel Orientation="Horizontal" HorizontalAlignment="Right" Margin="0,12,0,0">
        <Border x:Name="BtnCancel" Background="#1AFFFFFF" CornerRadius="8" Padding="14,7" Margin="0,0,8,0" Cursor="Hand">
          <TextBlock Text="取消" FontSize="11.5" Foreground="#E6E6EC"/>
        </Border>
        <Border x:Name="BtnOk" Background="#F2F2F5" CornerRadius="8" Padding="14,7" Cursor="Hand">
          <TextBlock Text="保存" FontSize="11.5" Foreground="#1B1B1F" FontWeight="SemiBold"/>
        </Border>
      </StackPanel>
    </StackPanel>
  </Border>
</Window>
'@
    $dlg = [Windows.Markup.XamlReader]::Parse((Convert-XamlTheme $xaml))
    $dlg.FindName('Ttl').Text = $Label
    $dlg.FindName('Dsc').Text = $Desc
    $dlg.FindName('Inp').Text = $cur
    $dlg.FindName('Root').Add_MouseLeftButtonDown({ try { $dlg.DragMove() } catch { } })
    $dlg.FindName('BtnCancel').Add_MouseLeftButtonUp({ $dlg.Close() })
    $dlg.FindName('BtnOk').Add_MouseLeftButtonUp({
        $raw = $dlg.FindName('Inp').Text
        $isNum = ($Value -ne $null) -and ("$($Value.GetType().Name)" -match 'Int|Double|Decimal')
        $ok = $true; $v = $null
        if ($isNum) {
            $n = 0.0
            if ([double]::TryParse($raw, [ref]$n)) { $v = $n } else { $ok = $false }
        } else {
            if ($raw -ne '') { $v = $raw } else { $ok = $false }
        }
        if (-not $ok) { $dlg.FindName('Err').Text = '请输入有效数字'; return }
        try {
            $script:cfg.$Key = $v
            Save-Config
            $dlg.Close()
            Update-Ui
        } catch { $dlg.FindName('Err').Text = "保存失败：$($_.Exception.Message)" }
    }.GetNewClosure())
    if ($script:shellWin) { try { $dlg.Owner = $script:shellWin } catch { } }
    [void]$dlg.ShowDialog()
}


# ---------- 清除记忆 ----------
function Show-ClearMemoryDialog {
    $xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="清除记忆" Width="430" Height="286"
        WindowStyle="None" AllowsTransparency="True" Background="Transparent"
        WindowStartupLocation="CenterOwner" ShowInTaskbar="False">
  <Border x:Name="Root" CornerRadius="14" Background="#232327" BorderBrush="#33FFFFFF" BorderThickness="1">
    <StackPanel Margin="22,20,22,16">
      <TextBlock Text="清除记忆" FontSize="15" FontWeight="SemiBold" Foreground="#F2F2F5"/>
      <TextBlock Text="彻底删除以下内容，不可恢复：" FontSize="11" Foreground="#6E6E78" Margin="0,6,0,10"/>
      <StackPanel Margin="0,0,0,6">
        <TextBlock Text="· 全部休眠任务（正在休眠的实例不会再自动唤醒）" FontSize="11.5" Foreground="#B9B9C2" TextWrapping="Wrap" Margin="0,0,0,4"/>
        <TextBlock Text="· 内存趋势、今日统计、事件记录" FontSize="11.5" Foreground="#B9B9C2" TextWrapping="Wrap" Margin="0,0,0,4"/>
        <TextBlock Text="· 所有日志与已导出的报告" FontSize="11.5" Foreground="#B9B9C2" TextWrapping="Wrap" Margin="0,0,0,4"/>
        <TextBlock Text="· 设置项会保留，不用重配" FontSize="11.5" Foreground="#6E6E78" TextWrapping="Wrap"/>
      </StackPanel>
      <Border x:Name="ChkRow" Background="Transparent" Padding="0,10,0,0" Cursor="Hand">
        <StackPanel Orientation="Horizontal">
          <Border x:Name="ChkBox" Width="16" Height="16" CornerRadius="4" BorderBrush="#33FFFFFF" BorderThickness="1" Background="Transparent" VerticalAlignment="Center">
            <TextBlock x:Name="ChkMark" Text="" FontSize="10" Foreground="#1B1B1F" HorizontalAlignment="Center" VerticalAlignment="Center"/>
          </Border>
          <TextBlock x:Name="ChkText" Text="同时停止看护" FontSize="11.5" Foreground="#E6E6EC" Margin="8,0,0,0" VerticalAlignment="Center"/>
        </StackPanel>
      </Border>
      <TextBlock x:Name="Hint" Text="" FontSize="10" Foreground="#6E6E78" Margin="0,8,0,0"/>
      <StackPanel Orientation="Horizontal" HorizontalAlignment="Right" Margin="0,10,0,0">
        <Border x:Name="BtnNo" Background="#1AFFFFFF" CornerRadius="9" Padding="16,8" Margin="0,0,8,0" Cursor="Hand">
          <TextBlock Text="取消" FontSize="11.5" Foreground="#E6E6EC"/>
        </Border>
        <Border x:Name="BtnYes" Background="#FF453A" CornerRadius="9" Padding="16,8" Cursor="Hand">
          <TextBlock Text="彻底清除" FontSize="11.5" Foreground="#FFFFFF" FontWeight="SemiBold"/>
        </Border>
      </StackPanel>
    </StackPanel>
  </Border>
</Window>
'@
    $dlg = [Windows.Markup.XamlReader]::Parse((Convert-XamlTheme $xaml))
    $script:chkOn = $false
    $dlg.FindName('Root').Add_MouseLeftButtonDown({ try { $dlg.DragMove() } catch { } })
    $dlg.FindName('ChkRow').Add_MouseLeftButtonUp({
        $script:chkOn = -not $script:chkOn
        $box = $dlg.FindName('ChkBox')
        if ($script:chkOn) {
            $box.Background = Brush '#F2F2F5'
            $dlg.FindName('ChkMark').Text = '✓'
        } else {
            $box.Background = Brush '#00000000'
            $dlg.FindName('ChkMark').Text = ''
        }
    })
    $dlg.FindName('BtnNo').Add_MouseLeftButtonUp({ $dlg.Close() })
    $dlg.FindName('BtnYes').Add_MouseLeftButtonUp({
        try {
            $n = Invoke-ClearMemory ([bool]$script:chkOn)
            $dlg.Close()
            $script:lastInstances = @()
            Update-Ui
            Write-Diag ("清除记忆完成，删除 {0} 个文件" -f $n)
            [void][System.Windows.MessageBox]::Show(("已清除 {0} 个文件，记忆已归零" -f $n), 'MuMuGuard', 'OK', 'Information')
        } catch {
            $dlg.FindName('Hint').Text = "清除失败：$($_.Exception.Message)"
        }
    })
    if ($script:shellWin) { try { $dlg.Owner = $script:shellWin } catch { } }
    [void]$dlg.ShowDialog()
}