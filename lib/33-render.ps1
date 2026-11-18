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
    if ($cp) { $cp.Add_MouseLeftButtonUp({ Set-View 'compact'; Update-Ui }.GetNewClosure()) }
    $m = $Win.FindName('BtnMin')
    if ($m) { $m.Add_MouseLeftButtonUp({ $Win.WindowState = 'Minimized' }) }
    $h = $Win.FindName('BtnHide')
    if ($h) { $h.Add_MouseLeftButtonUp({ Hide-Panel }) }
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

    # 实例行
    $pnl = $win.FindName('PnlInstances')
    if ($pnl) {
        $sig = (($rows | ForEach-Object { "$($_.Index)|$($_.Judge)|$($_.Name)|$($_.UpLeft)|$($_.WakeAt)" }) -join ';')
        if ($sig -ne $script:shellRowsSig) {
            $script:shellRowsSig = $sig
            $pnl.Children.Clear()
            foreach ($r in $rows) {
                $isSleep = [bool]$r.WakeAt
                $isOff = (-not $isSleep -and $r.Script -ne $true -and -not $r.Online)
                $row = New-InstanceRowShell -Row $r -Icon $script:shellIcon -IsSleep $isSleep -IsOff $isOff
                [void]$pnl.Children.Add($row)
                $sep = New-Object System.Windows.Controls.Border
                $sep.Height = 1
                $sep.Background = Brush '#0DFFFFFF'
                $sep.Margin = New-Object System.Windows.Thickness(12, 0, 12, 0)
                [void]$pnl.Children.Add($sep)
            }
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
    $gl = $win.FindName('HealthGlyph'); $ht = $win.FindName('TxtHealthTitle'); $hs = $win.FindName('TxtHealthSub')
    if ($ht) { $ht.Text = $(if ($bad.Count -eq 0) { '检查通过' } else { "$($bad.Count) 项需处理" }) }
    if ($hs) { $hs.Text = $(if ($bad.Count -eq 0) { '系统服务与资源状态正常' } else { ($bad | ForEach-Object { $_.Name }) -join '、' }) }
    if ($gl) {
        $gl.Text = $(if ($bad.Count -eq 0) { '✓' } else { '!' })
        $gl.Foreground = Brush $(if ($bad.Count -eq 0) { '#34C759' } else { '#FF9F0A' })
    }

    # 唤醒 / 休眠统计
    $next = $null
    if ($sleep.Count -gt 0) { $next = @($sleep | Sort-Object { [datetime]$_.WakeAt } | Select-Object -First 1) }
    $nw = $win.FindName('TxtNextWake')
    if ($nw) { $nw.Text = $(if ($next) { ([datetime]$next[0].WakeAt).ToString('HH:mm') } else { '—' }) }
    $tc = Get-TodayCounts
    $sd = $win.FindName('TxtSleepToday')
    if ($sd) { $sd.Text = "$($tc.sleep) 次" }
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
        @{ K = 'AutoSleep';         L = '自动休眠';              T = 'bool' }
        @{ K = 'SleepBackground';   L = '游戏切后台时也休眠';     T = 'bool' }
        @{ K = 'SleepIdleMin';      L = '后台空闲判定';          T = 'min' }
        @{ K = 'SleepLeadMin';      L = '提前唤醒';              T = 'min' }
        @{ K = 'SleepMaxHours';     L = '最长休眠';              T = 'hour' }
        @{ K = 'AutoRecover';       L = '掉线自动恢复';          T = 'bool' }
        @{ K = 'RecoverCheckSec';   L = '检测间隔';              T = 'sec' }
        @{ K = 'RecoverFailCount';  L = '连续几次判定掉线';       T = 'time' }
    )
    foreach ($d in $defs) {
        $g = New-Object System.Windows.Controls.Grid
        $g.Height = 42
        $cd0 = New-Object System.Windows.Controls.ColumnDefinition
        $cd0.Width = [System.Windows.GridLength]::new(1, [System.Windows.GridUnitType]::Star)
        [void]$g.ColumnDefinitions.Add($cd0)
        $cd1 = New-Object System.Windows.Controls.ColumnDefinition
        $cd1.Width = [System.Windows.GridLength]::Auto
        [void]$g.ColumnDefinitions.Add($cd1)
        [void]$g.Children.Add((New-ShellText $d.L 12 '#F2F2F5'))

        $v = $script:cfg[$d.K]
        if ($d.T -eq 'bool') {
            $on = [bool]$v
            $pill = New-Object System.Windows.Controls.Border
            $pill.Width = 36; $pill.Height = 20
            $pill.CornerRadius = [System.Windows.CornerRadius]::new(10)
            $pill.Background = Brush $(if ($on) { '#34C759' } else { '#3A3A42' })
            $knob = New-Object System.Windows.Shapes.Ellipse
            $knob.Width = 16; $knob.Height = 16
            $knob.Fill = Brush '#FFFFFF'
            $knob.HorizontalAlignment = $(if ($on) { 'Right' } else { 'Left' })
            $knob.Margin = New-Object System.Windows.Thickness(2, 0, 2, 0)
            $pill.Child = $knob
            [System.Windows.Controls.Grid]::SetColumn($pill, 1)
            [void]$g.Children.Add($pill)
        } else {
            $txt = switch ($d.T) {
                'min'  { "$v 分钟" }
                'hour' { "$v 小时" }
                'sec'  { "$v 秒" }
                default { "$v 次" }
            }
            $t = New-ShellText $txt 12 '#6E6E78'
            [System.Windows.Controls.Grid]::SetColumn($t, 1)
            [void]$g.Children.Add($t)
        }
        [void]$pnl.Children.Add($g)
        $sep = New-Object System.Windows.Controls.Border
        $sep.Height = 1; $sep.Background = Brush '#0DFFFFFF'
        [void]$pnl.Children.Add($sep)
    }

    $foot = New-ShellText ("MuMu 安装目录：{0}    版本 {1}" -f $MuMuRoot, $script:appVersion) 10 '#6E6E78'
    $foot.Margin = New-Object System.Windows.Thickness(0, 8, 0, 0)
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
            $script:compactRoot = [Windows.Markup.XamlReader]::Parse((Get-CompactXaml))
            $lg = $script:compactRoot.FindName('CmpLogo')
            if ($lg -and $script:shellLogo) { $lg.Source = $script:shellLogo }
            $script:compactRoot.Add_MouseLeftButtonDown({ try { $win.DragMove() } catch { } })
            $ex = $script:compactRoot.FindName('BtnCmpExpand')
            if ($ex) { $ex.Add_MouseLeftButtonUp({ Set-View 'shell'; Update-Ui }.GetNewClosure()) }
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

    $targets = @('Nav1', 'Nav2', 'Nav3', 'Nav4', 'Nav5', 'BtnRefresh', 'BtnCompact')
    foreach ($n in $targets) {
        $el = $win.FindName($n)
        if (-not $el) { $lines += "MISS  $n  元素不存在"; continue }
        try {
            $args = New-Object System.Windows.Input.MouseButtonEventArgs([System.Windows.Input.Mouse]::PrimaryDevice, 0, [System.Windows.Input.MouseButton]::Left)
            $args.RoutedEvent = [System.Windows.UIElement]::MouseLeftButtonUpEvent
            $el.RaiseEvent($args)
            $lines += "PASS  $n"
        } catch {
            $lines += "FAIL  $n  $($_.Exception.Message)"
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
            $lines += "FAIL  $n  $($_.Exception.Message)"
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
