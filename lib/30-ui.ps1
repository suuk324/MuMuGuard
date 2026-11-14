#Requires -Version 5.1
#
# 界面：环形控件、实例卡片、各区域同步、设置窗口
# 本文件由拆分脚本生成，供 MuMuGuardApp.ps1 dot-source（共享同一 $script: 作用域）

# 环的显示状态判定（紧凑视图与详情卡片共用，避免两处逻辑不一致）
function Get-RingView($r, [string]$ctx) {
    $smallSize = if ($ctx -eq 'card') { 10 } else { 12 }
    $bigSize   = if ($ctx -eq 'card') { 11 } else { 20 }

    if ($r.Sleeping) {
        return [pscustomobject]@{
            Mode        = 'sleep'
            Dashed      = $false
            TrackColor  = '#232B3A'
            CenterText  = $(if ($r.WakeAt) { $r.WakeAt.ToString('HH:mm') } else { '—' })
            CenterSize  = $smallSize
            CenterColor = '#7C8BA8'
            Pct         = 0
            ArcColor    = '#3DDC84'
        }
    }

    if ($r.Script -eq $false) {
        return [pscustomobject]@{
            Mode        = 'off'
            Dashed      = $false
            TrackColor  = '#2A1214'
            CenterText  = '—'
            CenterSize  = $bigSize
            CenterColor = '#414B5E'
            Pct         = 0
            ArcColor    = '#3DDC84'
        }
    }

    $col = '#3DDC84'
    if ($r.Level -eq 1) { $col = '#F5A524' }
    if ($r.Level -eq 2) { $col = '#F26D6D' }

    return [pscustomobject]@{
        Mode        = 'on'
        Dashed      = $false
        TrackColor  = '#1A2130'
        CenterText  = ([string][int]$r.MemPct + '%')
        CenterSize  = $bigSize
        CenterColor = '#8A94A6'
        Pct         = $r.MemPct
        ArcColor    = $col
    }
}

# 应用环的底圈与中心文字（几何由各视图自己的 Set-RingArc / Set-CardArc 负责）
function Set-RingBase($c, $v) {
    $c.Track.Stroke = Brush $v.TrackColor
    if ($v.Dashed) {
        $dash = New-Object System.Windows.Media.DoubleCollection
        [void]$dash.Add(2)
        [void]$dash.Add(2)
        $c.Track.StrokeDashArray = $dash
        $c.Arc.Visibility = 'Collapsed'
        $c.Arc.Data = $null
    } else {
        $c.Track.StrokeDashArray = $null
    }
    $c.Pct.FontSize   = $v.CenterSize
    $c.Pct.Text       = $v.CenterText
    $c.Pct.Foreground = Brush $v.CenterColor
}

function New-RingCell {
    $panel = New-Object System.Windows.Controls.StackPanel
    $panel.HorizontalAlignment = 'Center'
    $grid = New-Object System.Windows.Controls.Grid
    $grid.Width  = $RingSize
    $grid.Height = $RingSize

    $track = New-Object System.Windows.Shapes.Ellipse
    $track.Width  = $RingSize
    $track.Height = $RingSize
    $track.Stroke = Brush '#1A2130'
    $track.StrokeThickness = $RingStroke
    [void]$grid.Children.Add($track)

    $arc = New-Object System.Windows.Shapes.Path
    $arc.Stroke = Brush '#3DDC84'
    $arc.StrokeThickness = $RingStroke
    $arc.StrokeStartLineCap = 'Round'
    $arc.StrokeEndLineCap   = 'Round'
    $arc.Visibility = 'Collapsed'
    [void]$grid.Children.Add($arc)

    $inner = New-Object System.Windows.Controls.StackPanel
    $inner.HorizontalAlignment = 'Center'
    $inner.VerticalAlignment   = 'Center'

    $pct = New-Object System.Windows.Controls.TextBlock
    $pct.Text = '--'
    $pct.FontSize = 20
    $pct.FontWeight = 'Bold'
    $pct.Foreground = Brush '#E6EAF2'
    $pct.HorizontalAlignment = 'Center'

    $num = New-Object System.Windows.Controls.TextBlock
    $num.Text = '实例'
    $num.FontSize = 8.5
    $num.Foreground = Brush '#414B5E'
    $num.HorizontalAlignment = 'Center'
    $num.Margin = [System.Windows.Thickness]::new(0,2,0,0)

    $num.MaxWidth = $RingSize - 10
    $num.TextTrimming = 'CharacterEllipsis'
    $num.TextAlignment = 'Center'
    [void]$inner.Children.Add($pct)
    [void]$inner.Children.Add($num)
    [void]$grid.Children.Add($inner)


    [void]$panel.Children.Add($grid)

    $viewbox = New-Object System.Windows.Controls.Viewbox
    $viewbox.Stretch = 'Uniform'
    $viewbox.StretchDirection = 'Both'
    $viewbox.HorizontalAlignment = 'Center'
    $viewbox.VerticalAlignment = 'Center'
    $viewbox.Child = $panel
    return [pscustomobject]@{ Panel=$viewbox; Box=$viewbox; Track=$track; Arc=$arc; Pct=$pct; Num=$num; Sig=''; Scale=1.0 }
}


function Set-RingArc($cell, [double]$pct, [string]$color) {
    $cell.Arc.Stroke = Brush $color
    if ($pct -lt 0.5) {
        $cell.Arc.Visibility = 'Collapsed'
        $cell.Arc.Data = $null
        return
    }
    $sweep = 359.9 * $pct / 100
    if ($pct -ge 99.5) {
        $cell.Arc.Visibility = 'Collapsed'
        $cell.Arc.Data = $null
        $cell.Track.Stroke = Brush $color
        return
    }
    $cx = $RingSize / 2.0
    $cy = $RingSize / 2.0
    $r  = $RingRadius
    $a1 = -90.0
    $a2 = $a1 + $sweep
    $sx = $cx + $r * [math]::Cos($a1 * [math]::PI / 180)
    $sy = $cy + $r * [math]::Sin($a1 * [math]::PI / 180)
    $ex = $cx + $r * [math]::Cos($a2 * [math]::PI / 180)
    $ey = $cy + $r * [math]::Sin($a2 * [math]::PI / 180)

    $fig = New-Object System.Windows.Media.PathFigure
    $fig.StartPoint = New-Object System.Windows.Point($sx, $sy)
    $seg = New-Object System.Windows.Media.ArcSegment
    $seg.Point = New-Object System.Windows.Point($ex, $ey)
    $seg.Size  = New-Object System.Windows.Size($r, $r)
    $seg.IsLargeArc = ($sweep -gt 180)
    $seg.SweepDirection = 'Clockwise'
    [void]$fig.Segments.Add($seg)
    $geo = New-Object System.Windows.Media.PathGeometry
    [void]$geo.Figures.Add($fig)
    $cell.Arc.Data = $geo
    $cell.Arc.Visibility = 'Visible'
}


function Sync-Compact($data, $hm) {
    # 实例数决定布局：≤5 个用环，>5 个切列表
    $count = @($data).Count
    $mode  = Get-CompactMode -Count $count

    # 没有实例时给出明确提示，避免面板空白让人以为坏了
    if ($count -eq 0) {
        if (-not $script:cmpEmpty) {
            $tb = New-Object System.Windows.Controls.TextBlock
            $tb.Text = "没有检测到 MuMu 实例`n请先确认模拟器已安装并启动过一次"
            $tb.TextAlignment = "Center"
            $tb.HorizontalAlignment = "Center"
            $tb.VerticalAlignment = "Center"
            $tb.FontSize = 11.5
            $tb.LineHeight = 22
            $tb.Foreground = Brush "#8A94A6"
            [void]$cmpRingsHost.Children.Add($tb)
            $script:cmpEmpty = $tb
        }
        $script:cmpEmpty.Visibility = "Visible"
        if ($cmpRings.Visibility -ne "Collapsed") { $cmpRings.Visibility = "Collapsed" }
        if ($cmpList.Visibility  -ne "Collapsed") { $cmpList.Visibility  = "Collapsed" }
        Sync-CompactFoot $data $hm
        return
    }
    if ($script:cmpEmpty) { $script:cmpEmpty.Visibility = "Collapsed" }

    if ($mode -eq 'list') {
        if ($cmpRings.Visibility -ne 'Collapsed') { $cmpRings.Visibility = 'Collapsed' }
        if ($cmpList.Visibility  -ne 'Visible')   { $cmpList.Visibility  = 'Visible' }
        Sync-CompactList $data
        Sync-CompactFoot $data $hm
        return
    }

    if ($cmpRings.Visibility -ne 'Visible')   { $cmpRings.Visibility = 'Visible' }
    if ($cmpList.Visibility  -ne 'Collapsed') { $cmpList.Visibility = 'Collapsed' }

    # 自适应尺寸：按容器宽度平均分配，环之间留固定间距
    $hostW = 324.0
    try { if ($cmpRingsHost -and $cmpRingsHost.ActualWidth -gt 20) { $hostW = $cmpRingsHost.ActualWidth } } catch { }
    $gap  = if ($count -le 2) { 22.0 } elseif ($count -le 3) { 18.0 } else { 12.0 }
    $size = [math]::Floor(($hostW - $gap * [math]::Max(0, $count - 1)) / [math]::Max(1, $count))
    $size = [math]::Min(96.0, [math]::Max(40.0, $size))

    # 紧凑窗口高度随内容自适应，避免底部按钮被裁掉
    $needH = 30 + 18 + 8 + [math]::Ceiling($size * 1.02) + 23 + 20 + 37
    $curH = if ($win) { $win.Height } else { 214 }
    if ($script:compactMode -eq 'rings' -and $needH -gt $curH - 0.5) {
        try { $win.Height = $needH } catch { }
    }
    $shortMap = if ($script:shortLabels) { $script:shortLabels } else { @{} }

    # ---- 环形（仅在数据变化时更新控件，避免每轮触发 WPF 重排）----
    $alive = @{}
    foreach ($r in $data) {
        $key = "$($r.PID)"
        $alive[$key] = $true
        if (-not $script:cmpMap.ContainsKey($key)) {
            $cell = New-RingCell
            $script:cmpMap[$key] = $cell
            [void]$cmpRings.Children.Add($cell.Panel)
        }
        $c = $script:cmpMap[$key]

        $rv = Get-RingView $r 'compact'
        $label = if ($shortMap.ContainsKey("$($r.Index)")) { $shortMap["$($r.Index)"] } else { $r.Name }
        $sig = "$($rv.Mode)|$($r.Index)|$($rv.CenterText)|$($r.Level)|$label|$size"
        if ($c.Sig -eq $sig) { continue }
        $c.Sig = $sig

        $c.Num.Text = $label
        $c.Box.Width  = $size
        $c.Box.Height = [math]::Round($size * 1.02)
        $c.Box.Margin = [System.Windows.Thickness]::new(($gap / 2), 0, ($gap / 2), 0)
        Set-RingBase $c $rv
        if ($rv.Mode -eq 'on') {
            Set-RingArc $c $rv.Pct $rv.ArcColor
            $c.Pct.ToolTip = ('{0:N0} MB / 刻度 {1:N0} MB' -f $r.Private, $r.MemBase)
        }
    }
    foreach ($k in @($script:cmpMap.Keys)) {
        if (-not $alive.ContainsKey($k)) {
            [void]$cmpRings.Children.Remove($script:cmpMap[$k].Panel)
            $script:cmpMap.Remove($k)
        }
    }
    Sync-CompactFoot $data $hm
}

# 紧凑面板底部：内存格 + 文字 + 看护状态（环形/列表两种模式共用）
function Sync-CompactFoot($data, $hm) {
    # ---- 16 格内存 ----
    if ($script:cellMap.Count -eq 0) {
        for ($i = 0; $i -lt 16; $i++) {
            $b = New-Object System.Windows.Controls.Border
            $b.Width  = 18
            $b.Height = 14
            $b.CornerRadius = [System.Windows.CornerRadius]::new(3)
            $b.Margin = [System.Windows.Thickness]::new(0,0,2,0)
            $b.Background = Brush '#2A3650'
            [void]$cmpCells.Children.Add($b)
            $script:cellMap += $b
        }
    }

    $usedGB = ($script:totalMB - $hm.AvailableMB) / 1024.0
    $freeCells = [int][math]::Round($hm.AvailableMB / 1024.0)
    if ($freeCells -lt 0) { $freeCells = 0 }
    if ($freeCells -gt 16) { $freeCells = 16 }
    $filled = 16 - $freeCells

    if ($script:lastFilled -ne $filled) {
        $script:lastFilled = $filled
        for ($i = 0; $i -lt 16; $i++) {
            $b = $script:cellMap[$i]
            if ($i -lt $filled) {
                if ($freeCells -eq 0 -and $i -eq 15) {
                    $b.Background = Brush '#F26D6D'
                    $b.BorderThickness = [System.Windows.Thickness]::new(0)
                } else {
                    $b.Background = Brush '#2A3650'
                    $b.BorderThickness = [System.Windows.Thickness]::new(0)
                }
            } else {
                $b.Background = Brush '#00000000'
                $b.BorderBrush = Brush '#F26D6D'
                $b.BorderThickness = [System.Windows.Thickness]::new(1)
            }
        }
    }

    $memText = ('已用 {0:N1} GB / {1:N1} GB' -f $usedGB, ($script:totalMB / 1024.0))
    if ($cmpMemText.Text -ne $memText) { $cmpMemText.Text = $memText }

    # ---- 看护状态 ----
    if ($script:lastGuardState -ne $script:guardRunning) {
        $script:lastGuardState = $script:guardRunning
        if ($script:guardRunning) {
            $cmpGuardDot.Fill = Brush '#3DDC84'
            $cmpGuardText.Text = '看护中'
            $cmpGuardText.Foreground = Brush '#3DDC84'
            $cmpGuardBtn.Content = '停止看护'
            $cmpGuardBtn.Background = Brush '#1B2A22'
            $cmpGuardBtn.Foreground = Brush '#3DDC84'
        } else {
            $cmpGuardDot.Fill = Brush '#414B5E'
            $cmpGuardText.Text = '已停止'
            $cmpGuardText.Foreground = Brush '#414B5E'
            $cmpGuardBtn.Content = '启动看护'
            $cmpGuardBtn.Background = Brush '#E8EDF5'
            $cmpGuardBtn.Foreground = Brush '#0A0D14'
        }
    }
}

# 紧凑面板列表模式：实例多时每行显示 名称 / 内存条 / 状态
function Sync-CompactList($data) {
    if (-not $script:listRows) { $script:listRows = @{} }
    $alive = @{}
    $i = 0
    foreach ($r in $data) {
        $key = "$($r.PID)"
        $alive[$key] = $true
        if (-not $script:listRows.ContainsKey($key)) {
            $panel = New-Object System.Windows.Controls.Grid
            $panel.Margin = [System.Windows.Thickness]::new(0,2,0,2)
            $c0 = New-Object System.Windows.Controls.ColumnDefinition
            $c0.Width = [System.Windows.GridLength]::new(96)
            $c1 = New-Object System.Windows.Controls.ColumnDefinition
            $c1.Width = [System.Windows.GridLength]::new(1, [System.Windows.GridUnitType]::Star)
            $c2 = New-Object System.Windows.Controls.ColumnDefinition
            $c2.Width = [System.Windows.GridLength]::new(46)
            [void]$panel.ColumnDefinitions.Add($c0)
            [void]$panel.ColumnDefinitions.Add($c1)
            [void]$panel.ColumnDefinitions.Add($c2)

            $nm = New-Object System.Windows.Controls.TextBlock
            $nm.FontSize = 9.5
            $nm.VerticalAlignment = 'Center'
            $nm.TextTrimming = 'CharacterEllipsis'
            [System.Windows.Controls.Grid]::SetColumn($nm, 0)

            $barBg = New-Object System.Windows.Controls.Border
            $barBg.Height = 6
            $barBg.CornerRadius = [System.Windows.CornerRadius]::new(3)
            $barBg.Background = Brush '#1A2130'
            $barBg.VerticalAlignment = 'Center'
            $barBg.Margin = [System.Windows.Thickness]::new(6,0,6,0)
            $barInner = New-Object System.Windows.Controls.Border
            $barInner.CornerRadius = [System.Windows.CornerRadius]::new(3)
            $barInner.HorizontalAlignment = 'Left'
            $barInner.Background = Brush '#3DDC84'
            $barBg.Child = $barInner
            [System.Windows.Controls.Grid]::SetColumn($barBg, 1)

            $st = New-Object System.Windows.Controls.TextBlock
            $st.FontSize = 9.5
            $st.VerticalAlignment = 'Center'
            $st.HorizontalAlignment = 'Right'
            $st.FontFamily = New-Object System.Windows.Media.FontFamily('Consolas')
            [System.Windows.Controls.Grid]::SetColumn($st, 2)

            [void]$panel.Children.Add($nm)
            [void]$panel.Children.Add($barBg)
            [void]$panel.Children.Add($st)
            [void]$cmpList.Children.Add($panel)
            $script:listRows[$key] = [pscustomobject]@{ Panel=$panel; Name=$nm; BarBg=$barBg; Bar=$barInner; State=$st }
        }
        $c = $script:listRows[$key]
        $rv = Get-RingView $r 'list'
        $short = if ($script:shortLabels -and $script:shortLabels.ContainsKey("$($r.Index)")) { $script:shortLabels["$($r.Index)"] } else { $r.Name }
        $sig = "$($rv.Mode)|$($rv.Pct)|$($rv.CenterText)|$short"
        if ($c.Panel.Tag -ne $sig) {
            $c.Panel.Tag = $sig
            $c.Name.Text = $short
            $c.Name.Foreground = Brush $(if ($rv.Mode -eq 'on') { '#C9D2E0' } else { '#7C8BA8' })
            $bw = if ($c.BarBg.ActualWidth -gt 10) { $c.BarBg.ActualWidth } else { 160 }
            $c.Bar.Width = if ($rv.Mode -eq 'on') { [math]::Max(2, $bw * $rv.Pct / 100) } else { 0 }
            $c.Bar.Background = Brush $rv.ArcColor
            $c.State.Text = $rv.CenterText
            $c.State.Foreground = Brush $rv.CenterColor
        }
        $i++
    }
    foreach ($k in @($script:listRows.Keys)) {
        if (-not $alive.ContainsKey($k)) {
            [void]$cmpList.Children.Remove($script:listRows[$k].Panel)
            $script:listRows.Remove($k)
        }
    }
}



function Set-View([string]$mode) {
    if ($mode -eq 'compact') {
        $win.Content = $compact
        $win.Width = 360
        $win.Height = 214
        $script:viewMode = 'compact'
    } else {
        $win.Content = $script:detailContent
        # 按屏幕工作区自适应：小屏 / 高缩放时不能超出可用区域，否则底部按钮点不到
        $waD  = [System.Windows.SystemParameters]::WorkArea
        $maxW = [math]::Max(680, $waD.Width  - 60)
        $maxH = [math]::Max(440, $waD.Height - 60)
        $win.Width  = [math]::Min(1000, $maxW)
        $win.Height = [math]::Min(700,  $maxH)
        $script:viewMode = 'detail'
    }
    try {
        $wa = [System.Windows.SystemParameters]::WorkArea
        if ($win.Left -lt $wa.Left) { $win.Left = $wa.Left }
        if ($win.Top -lt $wa.Top) { $win.Top = $wa.Top }
        if (($win.Left + $win.Width) -gt $wa.Right)  { $win.Left = [math]::Max($wa.Left, $wa.Right - $win.Width) }
        if (($win.Top + $win.Height) -gt $wa.Bottom) { $win.Top  = [math]::Max($wa.Top, $wa.Bottom - $win.Height) }
    } catch { }
}


function New-InstanceCard {
    $border = New-Object System.Windows.Controls.Border
    $border.CornerRadius = [System.Windows.CornerRadius]::new(12)
    $border.Background   = Brush '#0F141C'
    $border.BorderBrush  = Brush '#161C26'
    $border.BorderThickness = [System.Windows.Thickness]::new(1)
    $border.Margin  = [System.Windows.Thickness]::new(0,0,0,10)
    $border.Padding = [System.Windows.Thickness]::new(16,14,16,14)

    $root = New-Object System.Windows.Controls.Grid
    $border.Child = $root
    $c0 = New-Object System.Windows.Controls.ColumnDefinition
    $c0.Width = [System.Windows.GridLength]::new(46)
    $c1 = New-Object System.Windows.Controls.ColumnDefinition
    $c1.Width = [System.Windows.GridLength]::new(1, [System.Windows.GridUnitType]::Star)
    [void]$root.ColumnDefinitions.Add($c0)
    [void]$root.ColumnDefinitions.Add($c1)

    # 小环
    $ringGrid = New-Object System.Windows.Controls.Grid
    $ringGrid.Width  = 46
    $ringGrid.Height = 46
    $ringGrid.VerticalAlignment = 'Center'

    $track = New-Object System.Windows.Shapes.Ellipse
    $track.Width  = 46
    $track.Height = 46
    $track.Stroke = Brush '#1A2130'
    $track.StrokeThickness = 5
    [void]$ringGrid.Children.Add($track)

    $arc = New-Object System.Windows.Shapes.Path
    $arc.Stroke = Brush '#3DDC84'
    $arc.StrokeThickness = 5
    $arc.StrokeStartLineCap = 'Round'
    $arc.StrokeEndLineCap   = 'Round'
    $arc.Visibility = 'Collapsed'
    [void]$ringGrid.Children.Add($arc)

    $pct = New-Object System.Windows.Controls.TextBlock
    $pct.FontSize = 11
    $pct.FontWeight = 'Bold'
    $pct.Foreground = Brush '#8A94A6'
    $pct.HorizontalAlignment = 'Center'
    $pct.VerticalAlignment   = 'Center'
    [void]$ringGrid.Children.Add($pct)

    [System.Windows.Controls.Grid]::SetColumn($ringGrid, 0)
    [void]$root.Children.Add($ringGrid)

    # 右侧内容
    $stack = New-Object System.Windows.Controls.StackPanel
    $stack.Margin = [System.Windows.Thickness]::new(14,0,0,0)
    $stack.VerticalAlignment = 'Center'
    [System.Windows.Controls.Grid]::SetColumn($stack, 1)
    [void]$root.Children.Add($stack)

    $head = New-Object System.Windows.Controls.DockPanel
    $name = New-Object System.Windows.Controls.TextBlock
    $name.Text = '实例 -'
    $name.Foreground = Brush '#E6EAF2'
    $name.FontSize = 12
    $name.FontWeight = 'Bold'

    $judge = New-Object System.Windows.Controls.TextBlock
    $judge.Text = '--'
    $judge.Foreground = Brush '#3DDC84'
    $judge.FontSize = 9
    $judge.FontWeight = 'Bold'
    [void][System.Windows.Controls.DockPanel]::SetDock($judge, 'Right')

    [void]$head.Children.Add($judge)

    # 升级时间上号标记（紫孔雀里开启该功能时点亮）
    $sched = New-Object System.Windows.Controls.TextBlock
    $sched.Text = '上号'
    $sched.Foreground = Brush '#F5A524'
    $sched.FontSize = 9
    $sched.FontWeight = 'Bold'
    $sched.Margin = [System.Windows.Thickness]::new(0, 0, 8, 0)
    $sched.ToolTip = '紫孔雀已开启「升级时间上号」'
    $sched.Visibility = 'Collapsed'
    [void][System.Windows.Controls.DockPanel]::SetDock($sched, 'Right')
    [void]$head.Children.Add($sched)
    [void]$head.Children.Add($name)
    [void]$stack.Children.Add($head)

    $game = New-Object System.Windows.Controls.TextBlock
    $game.Text = '检测中'
    $game.Foreground = Brush '#8A94A6'
    $game.FontSize = 9.5
    $game.Margin = [System.Windows.Thickness]::new(0,3,0,0)
    [void]$stack.Children.Add($game)

    # 升级倒计时（没有升级时整行隐藏）
    $upgrade = New-Object System.Windows.Controls.TextBlock
    $upgrade.FontSize = 9.5
    $upgrade.Margin = [System.Windows.Thickness]::new(0,4,0,0)
    $upgrade.Visibility = 'Collapsed'
    [void]$stack.Children.Add($upgrade)

    $foot = New-Object System.Windows.Controls.DockPanel
    $foot.Margin = [System.Windows.Thickness]::new(0,6,0,0)

    $restart = New-Object System.Windows.Controls.Button
    $restart.Content = '重启'
    $restart.Style = $win.Resources['Mini']
    $restart.Padding = [System.Windows.Thickness]::new(10,2,10,2)
    [void][System.Windows.Controls.DockPanel]::SetDock($restart, 'Right')

    # 检测开关：暂停该实例的掉线检测与自动恢复
    $detectBtn = New-Object System.Windows.Controls.Button
    $detectBtn.Content = '检测中'
    $detectBtn.Style = $win.Resources['Mini']
    $detectBtn.Padding = [System.Windows.Thickness]::new(10,2,10,2)
    $detectBtn.Margin = [System.Windows.Thickness]::new(0,0,6,0)
    $detectBtn.ToolTip = '点击暂停该实例的掉线检测'
    [void][System.Windows.Controls.DockPanel]::SetDock($detectBtn, 'Right')

    $metrics = New-Object System.Windows.Controls.TextBlock
    $metrics.Text = '--'
    $metrics.Foreground = Brush '#414B5E'
    $metrics.FontSize = 9.5
    $metrics.VerticalAlignment = 'Center'

    [void]$foot.Children.Add($restart)
    [void]$foot.Children.Add($detectBtn)
    [void]$foot.Children.Add($metrics)
    [void]$stack.Children.Add($foot)

    return [pscustomobject]@{
        Border = $border; Name = $name; Judge = $judge; Game = $game
        Upgrade = $upgrade
        Metrics = $metrics; Restart = $restart; Detect = $detectBtn
        Track = $track; Arc = $arc; Pct = $pct; Sched = $sched
    }
}


function Set-CardArc($card, [double]$pct, [string]$color) {
    $card.Arc.Stroke = Brush $color
    if ($pct -lt 0.5) {
        $card.Arc.Visibility = 'Collapsed'
        $card.Arc.Data = $null
        return
    }
    $sweep = 359.9 * $pct / 100
    if ($pct -ge 99.5) {
        $card.Arc.Visibility = 'Collapsed'
        $card.Arc.Data = $null
        $card.Track.Stroke = Brush $color
        return
    }
    $c = 23.0; $r = 18.0
    $a1 = -90.0
    $a2 = $a1 + $sweep
    $sx = $c + $r * [math]::Cos($a1 * [math]::PI / 180)
    $sy = $c + $r * [math]::Sin($a1 * [math]::PI / 180)
    $ex = $c + $r * [math]::Cos($a2 * [math]::PI / 180)
    $ey = $c + $r * [math]::Sin($a2 * [math]::PI / 180)

    $fig = New-Object System.Windows.Media.PathFigure
    $fig.StartPoint = New-Object System.Windows.Point($sx, $sy)
    $seg = New-Object System.Windows.Media.ArcSegment
    $seg.Point = New-Object System.Windows.Point($ex, $ey)
    $seg.Size  = New-Object System.Windows.Size($r, $r)
    $seg.IsLargeArc = ($sweep -gt 180)
    $seg.SweepDirection = 'Clockwise'
    [void]$fig.Segments.Add($seg)
    $geo = New-Object System.Windows.Media.PathGeometry
    [void]$geo.Figures.Add($fig)
    $card.Arc.Data = $geo
    $card.Arc.Visibility = 'Visible'
}


function Sync-Cards($data) {
    if ($data.Count -eq 0) {
        if (-not $script:placeholder) {
            $t = New-Object System.Windows.Controls.TextBlock
            $t.Text = '未检测到 MuMu 实例'
            $t.Foreground = Brush '#414B5E'
            $t.FontSize = 11.5
            $t.Margin = [System.Windows.Thickness]::new(4,10,0,0)
            [void]$pnlCards.Children.Add($t)
            $script:placeholder = $t
        }
        return
    }
    if ($script:placeholder) {
        [void]$pnlCards.Children.Remove($script:placeholder)
        $script:placeholder = $null
    }

    $alive = @{}
    foreach ($r in $data) {
        $key = "$($r.PID)"
        $alive[$key] = $true

        if (-not $script:cardMap.ContainsKey($key)) {
            $card = New-InstanceCard
            $card.Restart.Tag = $r.Index
            $card.Restart.Add_Click({
                param($s, $e)
                $i = "$($s.Tag)"

                # 休眠中的实例：按钮是「唤醒」
                if ($s.Content -eq '唤醒') {
                    $res = [System.Windows.MessageBox]::Show(
                        "立即唤醒实例 $i 并启动紫孔雀？`n`n唤醒后会取消该实例的休眠计划。",
                        'MuMuGuard', 'YesNo', 'Question')
                    if ($res -ne 'Yes') { return }
                    try {
                        $list = @(Get-SleepList | Where-Object { "$($_.Index)" -ne $i })
                        Save-SleepList $list
                        # 交给唤醒器立即执行
                        $nowStr = (Get-Date).ToString('yyyy-MM-ddTHH:mm:ss')
                        $list2 = @(Get-SleepList)
                        $list2 += [pscustomobject]@{
                            Index = $i; WakeAt = $nowStr; DoneAt = $nowStr
                            Upgrade = '手动唤醒'; Since = $nowStr
                        }
                        Save-SleepList $list2
                        Start-Waker
                        Write-GuardLog 'WAKE_MANUAL' "实例$i" '手动唤醒'
                        $txtInfo.Text = "正在唤醒实例 $i"
                    } catch {
                        Write-Diag "手动唤醒失败: $($_.Exception.Message)"
                        $txtInfo.Text = "唤醒失败：$($_.Exception.Message)"
                    }
                    return
                }

                $res = [System.Windows.MessageBox]::Show(
                    "重启实例 $i，并在开机完成后自动启动紫孔雀？`n`n过程约需 1-2 分钟，期间该号会掉线。",
                    'MuMuGuard', 'YesNo', 'Warning')
                if ($res -ne 'Yes') { return }
                try {
                    $log = Join-Path $LogDir 'restart.log'
                    Start-Process -FilePath 'C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe' `
                        -ArgumentList '-NoProfile', '-ExecutionPolicy', 'Bypass', '-WindowStyle', 'Hidden',
                                      '-File', (Get-HelperScript 'Restart-Instance.ps1'),
                                      '-Index', "$i", '-LogFile', $log `
                        -WindowStyle Hidden | Out-Null
                    $txtInfo.Text = "已开始重启实例 $i，完成后会自动启动紫孔雀"
                } catch {
                    Write-Diag "重启实例失败: $($_.Exception.Message)"
                    $txtInfo.Text = "重启失败：$($_.Exception.Message)"
                }
            })
            $script:cardMap[$key] = $card

            # 检测开关
            $card.Detect.Tag = $r.Index
            $card.Detect.Add_Click({
                param($s, $e)
                $i = "$($s.Tag)"
                $off = @($script:cfg.DetectOff | Where-Object { $_ -ne $null -and "$_" -ne '' })
                if ($off -contains $i) {
                    $script:cfg.DetectOff = @($off | Where-Object { "$_" -ne $i })
                } else {
                    $script:cfg.DetectOff = @($off + $i)
                }
                Save-Config
                $script:lastGuardState = $null
                Update-Ui
            })

            [void]$pnlCards.Children.Add($card.Border)
        }
        $c = $script:cardMap[$key]

        # 检测开关状态
        $isOff = (@($script:cfg.DetectOff | Where-Object { $_ -ne $null }) -contains "$($r.Index)")
        $c.Detect.Content = $(if ($isOff) { '已暂停' } else { '检测中' })
        $c.Detect.Foreground = Brush $(if ($isOff) { '#F5A524' } else { '#8A94A6' })
        $c.Detect.Background = Brush $(if ($isOff) { '#2A2110' } else { '#1E293B' })
        $c.Detect.ToolTip = $(if ($isOff) { '该实例的掉线检测已暂停，点击恢复' } else { '点击暂停该实例的掉线检测' })

        $c.Name.Text = $r.Name
        $c.Judge.Text = $r.Judge
        $c.Sched.Visibility = $(if ($r.Sched -eq $true) { 'Visible' } else { 'Collapsed' })
                if ($r.PSObject.Properties.Name -contains 'AdbErr' -and $r.AdbErr) { $c.Judge.ToolTip = "adb: $($r.AdbErr)"; if ($r.PSObject.Properties.Name -contains 'Chan' -and $r.Chan) { $c.Judge.ToolTip += "
通道: $($r.Chan)" } }

        # 休眠中：把「重启」换成「唤醒」
        if ($r.Sleeping) {
            if ($c.Restart.Content -ne '唤醒') {
                $c.Restart.Content = '唤醒'
                $c.Restart.Foreground = Brush '#3DDC84'
                $c.Restart.ToolTip = '立即唤醒该实例并启动紫孔雀'
            }
            $c.Detect.IsEnabled = $false
            $c.Detect.Opacity = 0.4
        } else {
            if ($c.Restart.Content -ne '重启') {
                $c.Restart.Content = '重启'
                $c.Restart.Foreground = Brush '#E6EAF2'
                $c.Restart.ToolTip = '重启该实例并自动启动紫孔雀'
            }
            $c.Detect.IsEnabled = $true
            $c.Detect.Opacity = 1
        }
        if ($r.Sleeping) {
            $c.Judge.Foreground = Brush '#7C8BA8'
        } else {
            switch ($r.Level) {
                0 { $c.Judge.Foreground = Brush '#3DDC84' }
                1 { $c.Judge.Foreground = Brush '#F5A524' }
                2 { $c.Judge.Foreground = Brush '#F26D6D' }
            }
        }

        # 环的状态（与紧凑视图共用同一套判定）
        $rv = Get-RingView $r 'card'
        Set-RingBase $c $rv
        if ($rv.Mode -eq 'on') { Set-CardArc $c $rv.Pct $rv.ArcColor }

        if ($r.Sleeping) {
            # 升级项目名按本实例的编号去休眠列表里取，避免多条休眠记录互相串字
            $sleepUp = "$($r.SleepUpgrade)"
            try {
                $ent = @(Get-SleepList | Where-Object { "$($_.Index)" -eq "$($r.Index)" }) | Select-Object -First 1
                if ($ent -and "$($ent.Upgrade)".Trim()) { $sleepUp = "$($ent.Upgrade)".Trim() }
            } catch { }
            $c.Game.Text = $(if ($sleepUp) { "休眠中 · $sleepUp" } else { '休眠中' })
            $c.Game.Foreground = Brush '#7C8BA8'
        } elseif ($r.Online -eq $null) {
            $c.Game.Text = 'adb 未连接'
            $c.Game.Foreground = Brush '#414B5E'
        } elseif ($r.Script -eq $false) {
            $c.Game.Text = '紫孔雀 · 未运行'
            $c.Game.Foreground = Brush '#F26D6D'
        } elseif ($r.Game -eq $true) {
            $c.Game.Text = '紫孔雀 · 运行中　游戏 · 运行中'
            $c.Game.Foreground = Brush '#8A94A6'
        } else {
            $c.Game.Text = '紫孔雀 · 运行中'
            $c.Game.Foreground = Brush '#8A94A6'
        }

        $cpuText = if ($r.Cores -ge 0) { '{0:N2} 核' -f $r.Cores } else { '--' }
        if ($r.Sleeping) {
            $c.Metrics.Text = $(if ($r.WakeAt) { '内存已释放' } else { '--' })
        } else {
            $c.Metrics.Text = ('{0}  ·  {1:N0} MB  ·  CEF {2}' -f $cpuText, $r.Private, $r.CEF)
        }

        # 休眠时，升级行改成唤醒提示
        if ($r.Sleeping) {
            $sig = "sleep|$($r.WakeAt)"
            if ($c.Upgrade.Tag -ne $sig) {
                $c.Upgrade.Tag = $sig
                $c.Upgrade.Inlines.Clear()
                $a = New-Object System.Windows.Documents.Run('将在 ')
                $a.Foreground = Brush '#4B566B'
                [void]$c.Upgrade.Inlines.Add($a)
                $b = New-Object System.Windows.Documents.Run($(if ($r.WakeAt) { $r.WakeAt.ToString('HH:mm') } else { '--:--' }))
                $b.Foreground = Brush '#7C8BA8'
                $b.FontWeight = 'Bold'
                [void]$c.Upgrade.Inlines.Add($b)
                $d = New-Object System.Windows.Documents.Run(' 自动开机并启动脚本')
                $d.Foreground = Brush '#4B566B'
                [void]$c.Upgrade.Inlines.Add($d)
            }
            $c.Upgrade.Visibility = 'Visible'
        } elseif ($r.UpName) {
            $sig = "$($r.UpName)|$($r.UpLvl)|$($r.UpLeft)"
            if ($c.Upgrade.Tag -ne $sig) {
                $c.Upgrade.Tag = $sig
                $c.Upgrade.Inlines.Clear()

                $r1 = New-Object System.Windows.Documents.Run('升级 · ')
                $r1.Foreground = Brush '#4B566B'
                [void]$c.Upgrade.Inlines.Add($r1)

                $r2 = New-Object System.Windows.Documents.Run(('{0} Lv.{1}' -f $r.UpName, $r.UpLvl))
                $r2.Foreground = Brush '#C9D2E0'
                [void]$c.Upgrade.Inlines.Add($r2)

                $r3 = New-Object System.Windows.Documents.Run(('  ·  {0:HH:mm} 完成  ·  剩 ' -f $r.UpDone))
                $r3.Foreground = Brush '#4B566B'
                [void]$c.Upgrade.Inlines.Add($r3)

                $r4 = New-Object System.Windows.Documents.Run($r.UpLeft)
                $r4.Foreground = Brush '#F5A524'
                $r4.FontWeight = 'Bold'
                [void]$c.Upgrade.Inlines.Add($r4)
            }
            $c.Upgrade.Visibility = 'Visible'
        } elseif ($r.UpName -eq '' -and $c.Upgrade.Visibility -ne 'Collapsed') {
            $c.Upgrade.Visibility = 'Collapsed'
        }

        $c.Arc.ToolTip = "nemuinit 占用 $($r.Spin)%"
    }

    foreach ($k in @($script:cardMap.Keys)) {
        if (-not $alive.ContainsKey($k)) {
            [void]$pnlCards.Children.Remove($script:cardMap[$k].Border)
            $script:cardMap.Remove($k)
        }
    }
}


function Sync-Events {
    $file = Get-LogFile
    $rows = @()
    if (Test-Path $file) { try { $rows = @(Import-Csv $file -ErrorAction Stop) } catch { } }

    if ($script:eventFilter -eq 'warn') {
        $warnSet = @('LOW_MEM', 'ALERT_SPIN', 'ALERT_MEM', 'ALERT_SCRIPT', 'RECOVER_FAIL')
        $rows = @($rows | Where-Object { $warnSet -contains $_.Action })
    }
    # 最新的排在最上面
    $rows = @($rows)
    if ($rows.Count -gt 1) { [array]::Reverse($rows) }
    $last = @($rows | Select-Object -First 40)

    $sig = $script:eventFilter + '|' + (($last | ForEach-Object { "$($_.Time)|$($_.Action)|$($_.Detail)" }) -join ';')
    if ($sig -eq $script:lastEventSig) { return }
    $script:lastEventSig = $sig

    $pnlEvents.Children.Clear()

    if ($last.Count -eq 0) {
        $t = New-Object System.Windows.Controls.TextBlock
        $t.Text = $(if ($script:eventFilter -eq 'warn') { '没有告警记录' } else { '今天还没有事件' })
        $t.Foreground = Brush '#414B5E'
        $t.FontSize = 11.5
        [void]$pnlEvents.Children.Add($t)
        return
    }

    foreach ($r in $last) {
        $line = New-Object System.Windows.Controls.TextBlock
        $line.FontSize = 11.5
        $line.Margin = [System.Windows.Thickness]::new(0,3,0,0)
        $line.TextTrimming = 'CharacterEllipsis'

        $time = $r.Time
        try { $time = ([datetime]$r.Time).ToString('HH:mm:ss') } catch { }

        switch ($r.Action) {
            'CLEAN_CEF' {
                $n = 0; if ($r.Detail -match 'killed=(\d+)') { $n = [int]$Matches[1] }
                $line.Text = ('{0}   清理 CEF · 回收 {1} 个' -f $time, $n)
                $line.Foreground = Brush '#3DDC84'
            }
            'LOW_MEM' {
                $m = 0; if ($r.Detail -match 'available=(\d+)') { $m = [int]$Matches[1] }
                $line.Text = ('{0}   内存偏低 · 可用 {1:N0} MB' -f $time, $m)
                $line.Foreground = Brush '#F5A524'
            }
            'ALERT_SPIN' {
                $line.Text = ('{0}   实例空转告警' -f $time)
                $line.Foreground = Brush '#F26D6D'
            }
            'ALERT_MEM' {
                $line.Text = ('{0}   实例内存偏高' -f $time)
                $line.Foreground = Brush '#FB923C'
            }
            'ALERT_SCRIPT' {
                $line.Text = ('{0}   {1} · {2}' -f $time, $r.Instance, $r.Detail)
                $line.Foreground = Brush '#F26D6D'
            }
            'AUTO_RECOVER' {
                $line.Text = ('{0}   {1} · 自动拉起脚本' -f $time, $r.Instance)
                $line.Foreground = Brush '#3DDC84'
            }
            'AUTO_RESTART' {
                $line.Text = ('{0}   {1} · 自动重启实例' -f $time, $r.Instance)
                $line.Foreground = Brush '#3DDC84'
            }
            'RECOVER_OK' {
                $line.Text = ('{0}   {1} · {2}' -f $time, $r.Instance, $r.Detail)
                $line.Foreground = Brush '#3DDC84'
            }
            'RECOVER_FAIL' {
                $line.Text = ('{0}   {1} · 恢复失败' -f $time, $r.Instance)
                $line.Foreground = Brush '#F26D6D'
            }
            'SLEEP' {
                $line.Text = ('{0}   {1} · {2}' -f $time, $r.Instance, $r.Detail)
                $line.Foreground = Brush '#7C8BA8'
            }
            'WAKE_MANUAL' {
                $line.Text = ('{0}   {1} · 已恢复运行，撤销休眠' -f $time, $r.Instance)
                $line.Foreground = Brush '#8A94A6'
            }
            'WAKE_LATE' {
                $line.Text = ('{0}   {1} · {2}' -f $time, $r.Instance, $r.Detail)
                $line.Foreground = Brush '#F5A524'
            }
            'WAKE_OK' {
                $line.Text = ('{0}   {1} · 已唤醒并启动脚本' -f $time, $r.Instance)
                $line.Foreground = Brush '#3DDC84'
            }
            'WAKE_FAIL' {
                $line.Text = ('{0}   {1} · 唤醒失败' -f $time, $r.Instance)
                $line.Foreground = Brush '#F26D6D'
            }
            'ROOT_FAIL' {
                $line.Text = ('{0}   模拟器 root 读取失败，升级信息不可用' -f $time)
                $line.Foreground = Brush '#F5A524'
            }
            'SLEEP_FAIL' {
                $line.Text = ('{0}   {1} · 休眠失败' -f $time, $r.Instance)
                $line.Foreground = Brush '#F26D6D'
            }
            default {
                $line.Text = ('{0}   {1}' -f $time, $r.Action)
                $line.Foreground = Brush '#8A94A6'
            }
        }
        [void]$pnlEvents.Children.Add($line)
    }
}


function Sync-Health($hm) {
    $items = Get-Health $hm

    # 首次构建，之后只更新文字
    if ($script:healthRows.Count -ne $items.Count) {
        $pnlHealth.Children.Clear()
        $script:healthRows = @()
        foreach ($it in $items) {
            $row = New-Object System.Windows.Controls.DockPanel
            $row.Margin = [System.Windows.Thickness]::new(0,3,0,0)

            $val = New-Object System.Windows.Controls.TextBlock
            $val.FontSize = 11
            [void][System.Windows.Controls.DockPanel]::SetDock($val, 'Right')

            $lbl = New-Object System.Windows.Controls.TextBlock
            $lbl.Text = $it.Name
            $lbl.FontSize = 11
            $lbl.Foreground = Brush '#8A94A6'

            [void]$row.Children.Add($val)
            [void]$row.Children.Add($lbl)
            [void]$pnlHealth.Children.Add($row)
            $script:healthRows += [pscustomobject]@{ Value = $val }
        }
    }

    for ($i = 0; $i -lt $items.Count; $i++) {
        $it  = $items[$i]
        $val = $script:healthRows[$i].Value
        if ($val.Text -ne $it.Text) { $val.Text = $it.Text }
        $val.Foreground = Brush $(if ($it.Ok) { '#3DDC84' } else { '#F26D6D' })
    }
}


function Add-TrendSample([int]$avail) {
    [void]$script:trend.Add($avail)
    while ($script:trend.Count -gt 120) { $script:trend.RemoveAt(0) }
}


function Save-Trend {
    try {
        @($script:trend) | ConvertTo-Json -Compress | Set-Content -Path $TrendFile -Encoding UTF8
    } catch { }
}


function Load-Trend {
    try {
        if (-not (Test-Path $TrendFile)) { return }
        $raw = Get-Content $TrendFile -Raw -Encoding UTF8
        if (-not $raw) { return }
        $arr = $raw | ConvertFrom-Json
        foreach ($x in @($arr)) {
            if ($null -ne $x) { [void]$script:trend.Add([int]$x) }
        }
        while ($script:trend.Count -gt 120) { $script:trend.RemoveAt(0) }
    } catch { }
}


function Sync-Trend {
    $c = $script:trend
    if ($c.Count -lt 2) {
        $trendLine.Points = New-Object System.Windows.Media.PointCollection
        $txtTrendHint.Visibility = 'Visible'
        return
    }
    $txtTrendHint.Visibility = 'Collapsed'

    $w = $trendCanvas.ActualWidth
    $h = $trendCanvas.ActualHeight
    if ($w -le 1 -or $h -le 1) { return }

    $min = ($c | Measure-Object -Minimum).Minimum
    $max = ($c | Measure-Object -Maximum).Maximum
    if ($max -le $min) { $max = $min + 1 }

    $pts = New-Object System.Windows.Media.PointCollection
    for ($i = 0; $i -lt $c.Count; $i++) {
        $x = $w * $i / ($c.Count - 1)
        $ratio = ($c[$i] - $min) / ($max - $min)
        $y = $h - ($ratio * ($h - 4)) - 2
        $pts.Add((New-Object System.Windows.Point($x, $y)))
    }
    $trendLine.Points = $pts
    $txtTrendMin.Text = ('最低 {0:N0} · 最高 {1:N0} MB' -f $min, $max)
}


function Update-Ui {
    try {
        $data = @(Get-InstanceData)
        $script:lastInstances = $data

        # 休眠中的实例进程已关闭，补进显示列表（不参与检测与恢复）
        $ui = @($data)
        $runIdx = @{}
        foreach ($r in $data) { $runIdx["$($r.Index)"] = $true }
        foreach ($s in @(Get-SleepList)) {
            $si = "$($s.Index)"
            if ($runIdx.ContainsKey($si)) { continue }
            $wakeAt = $null
            try { $wakeAt = [datetime]::Parse("$($s.WakeAt)") } catch { }
            $sic = if ($script:instanceMap -and $script:instanceMap.ContainsKey($si)) { $script:instanceMap[$si] } else { $null }
            $ui += [pscustomobject]@{
                Index = $si; Detect = $false
                Name = (Get-InstanceDisplayName -Config $sic -Aliases $script:cfg.Aliases)
                PID = "sleep-$si"
                Cores = -1; Private = 0; WS = 0; CEF = 0; MemPct = 0
                MemBase = $(if ($sic) { $sic.MemBaseMB } else { 0 })
                GuestGB = $(if ($sic) { $sic.MemoryGB } else { 0 })
                Online = $null; Script = $null; Game = $null; Spin = $null
                UpName = ''; UpLvl = 0; UpDone = $null; UpLeft = ''
                Judge = '休眠中'; Level = 0
                Sleeping = $true; WakeAt = $wakeAt; SleepUpgrade = "$($s.Upgrade)"
            }
        }
        $ui = @($ui | Sort-Object { [int]($_.Index -replace '\D', '0') })
        $data = $ui

        # 名称缩写（自动从公共前缀开始缩短，让环里的标签可读且不重复）
        $shorts = @(Get-ShortLabels -Names @($data | ForEach-Object { $_.Name }))
        $short = @{}
        for ($si = 0; $si -lt $data.Count; $si++) {
            $lbl = if ($si -lt $shorts.Count) { $shorts[$si] } else { $data[$si].Name }
            $short["$($data[$si].Index)"] = $lbl
        }
        $script:shortLabels = $short

        $hm = Get-HostMemory
        $usedPct = 0
        if ($script:totalMB -gt 0) { $usedPct = [int](100 - ($hm.AvailableMB / $script:totalMB * 100)) }
        if ($usedPct -lt 0)   { $usedPct = 0 }
        if ($usedPct -gt 100) { $usedPct = 100 }

        if ($hm.AvailableMB -lt $script:lowestAvail) { $script:lowestAvail = $hm.AvailableMB }

        $txtAvail.Text  = ('{0:N0}' -f $hm.AvailableMB)
        $txtCommit.Text = ('{0:N1} GB' -f $hm.CommitGB)
        $txtPage.Text   = ('{0:N0} MB' -f $hm.PageFileMB)

        $barWidth = $memHost.ActualWidth
        if ($barWidth -gt 0) { $memFill.Width = [math]::Max(0, [math]::Round($barWidth * $usedPct / 100)) }

        if ($usedPct -ge 92)     { $memFill.Background = Brush '#F26D6D'; $txtAvail.Foreground = Brush '#F26D6D' }
        elseif ($usedPct -ge 85) { $memFill.Background = Brush '#F5A524'; $txtAvail.Foreground = Brush '#F5A524' }
        else                     { $memFill.Background = Brush '#3DDC84'; $txtAvail.Foreground = Brush '#E6EAF2' }

        # 逐实例内存告警（持续 3 次）
        foreach ($r in $data) {
            $k = "$($r.PID)"
            if ($r.Private -gt [int]$script:cfg.MemAlertMB) {
                if (-not $script:overMem.ContainsKey($k)) { $script:overMem[$k] = 0 }
                $script:overMem[$k]++
                if ($script:overMem[$k] -ge 3) {
                    $last = [datetime]::MinValue
                    if ($script:memAlertAt.ContainsKey($k)) { $last = $script:memAlertAt[$k] }
                    if (((Get-Date) - $last).TotalMinutes -ge 30) {
                        Write-GuardLog 'ALERT_MEM' ("PID={0}" -f $r.PID) ("private={0}MB" -f $r.Private)
                        $script:memAlertAt[$k] = Get-Date
                    }
                }
            } else {
                $script:overMem[$k] = 0
            }
        }

        Update-LogInfo

        # root 授权失效检测（升级信息会静默消失）
        try {
            if ($script:adbSync.RootOk -eq $false -and -not $script:rootWarned) {
                $script:rootWarned = $true
                Write-Diag 'root 读取失败：升级信息不可用，请检查模拟器内 KernelSU 授权'
                Write-GuardLog 'ROOT_FAIL' '-' 'su 读取失败，升级信息不可用'
            } elseif ($script:adbSync.RootOk -eq $true) {
                $script:rootWarned = $false
            }
        } catch { }

        # 详情页不可见时不更新，省掉大量隐藏控件的重绘
        if ($script:viewMode -eq 'detail') {
            Sync-Cards $data
            Sync-Events
            Sync-Health $hm
            Sync-Trend
        }
        Sync-Compact $data $hm

        # 总体状态
        $worst = 0
        foreach ($r in $data) { if ($r.Level -gt $worst) { $worst = $r.Level } }
        if ($hm.AvailableMB -lt 300) { $worst = 2 }
        elseif ($hm.AvailableMB -lt [int]$script:cfg.LowMemMB -and $worst -lt 1) { $worst = 1 }

        # 采集线程停滞检测：心跳超过 90 秒没更新，说明 adb 采集已经卡住
        $hbTime = $null
        try { $hbTime = $script:adbSync.Heartbeat } catch { }
        $staleSec = 0
        if ($hbTime) { $staleSec = [int]((Get-Date) - $hbTime).TotalSeconds }
        # 窗口收进托盘时轮询是刻意暂停的，不算「数据停滞」
        $winHidden = $false
        try { $winHidden = ($win.WindowState -eq 'Minimized') -or (-not $win.IsVisible) } catch { }
        $isStale = (-not $winHidden) -and ($data.Count -gt 0) -and ((-not $hbTime) -or ($staleSec -gt 90))

        switch ($worst) {
            0 { $txtStatus.Text = '一切正常'; $txtStatus.Foreground = Brush '#3DDC84'; $statusDot.Fill = Brush '#3DDC84'; $statusPill.Background = Brush '#0F2A1C' }
            1 { $txtStatus.Text = '需要注意'; $txtStatus.Foreground = Brush '#F5A524'; $statusDot.Fill = Brush '#F5A524'; $statusPill.Background = Brush '#2A2110' }
            2 { $txtStatus.Text = '存在问题'; $txtStatus.Foreground = Brush '#F26D6D'; $statusDot.Fill = Brush '#F26D6D'; $statusPill.Background = Brush '#2A1214' }
        }

        # 采集停滞的提示优先级最高：数据不可信的时候，说什么都白搭
        if ($isStale) {
            $txtStatus.Text = '数据停滞'
            $txtStatus.Foreground = Brush '#F5A524'
            $statusDot.Fill = Brush '#F5A524'
            $statusPill.Background = Brush '#2A2110'
            if ($statusPill) { $statusPill.ToolTip = $(if ($staleSec -gt 0) { "采集已 $staleSec 秒没有更新，正在重连 adb" } else { '采集线程尚未就绪' }) }
        } elseif ($statusPill) { $statusPill.ToolTip = $null }
        if ($script:guardRunning) {
            $btnGuard.Content = '■ 停止看护'
            $btnGuard.Background = Brush '#1B2A22'
            $btnGuard.Foreground = Brush '#3DDC84'
        } else {
            $btnGuard.Content = '▶ 启动看护'
            $btnGuard.Background = Brush '#E8EDF5'
            $btnGuard.Foreground = Brush '#0A0D14'
        }

        $guardText = if ($script:guardRunning) { '运行中' } else { '已停止' }
        $lastText  = if ($script:lastClean) { $script:lastClean.ToString('HH:mm:ss') } else { '--' }
        $lowText   = if ($script:lowestAvail -ne [int]::MaxValue) { ('{0:N0} MB' -f $script:lowestAvail) } else { '--' }

        # 内存超配预警
        $estGB   = Get-TotalEstimatedGB -Rows $data
        $totalGB = [math]::Round($script:totalMB / 1024.0, 1)
        $level   = Get-OvercommitLevel -EstimatedGB $estGB -TotalGB $totalGB
        $running = @($data | Where-Object { -not $_.Sleeping }).Count
        $overTxt = ''
        if ($level -eq 'danger') {
            $overTxt = ('    已开 {0} 个 · 预计 {1} GB / 本机 {2} GB  ⚠ 内存超配' -f $running, $estGB, $totalGB)
        } elseif ($level -eq 'warn') {
            $overTxt = ('    已开 {0} 个 · 预计 {1} GB / 本机 {2} GB  ⚠ 接近上限' -f $running, $estGB, $totalGB)
        } elseif ($running -gt 1) {
            $overTxt = ('    已开 {0} 个 · 预计 {1} GB / 本机 {2} GB' -f $running, $estGB, $totalGB)
        }

        $txtInfo.Text = ('看护 {0}    上次清理 {1}    今日清理 {2} 次 · 回收 {3} 个 · 告警 {4} 条    本次最低可用 {5}{6}' -f `
            $guardText, $lastText, $script:logClean, $script:logKilled, $script:logAlert, $lowText, $overTxt)
        if ($level -eq 'danger') { $txtInfo.Foreground = Brush '#F26D6D' }
        elseif ($level -eq 'warn') { $txtInfo.Foreground = Brush '#F5A524' }
        else { $txtInfo.Foreground = Brush '#8A94A6' }

        # 批量操作按钮：实例多于 1 个才显示
        $multi = ($running + @($data | Where-Object { $_.Sleeping }).Count) -gt 1
        $vis = if ($multi) { 'Visible' } else { 'Collapsed' }
        if ($btnAllRestart.Visibility.ToString() -ne $vis) {
            $btnAllRestart.Visibility = $vis
            $btnAllSleep.Visibility   = $vis
            $btnAllWake.Visibility    = $vis
        }
    } catch {
        $txtInfo.Text = '刷新出错：' + $_.Exception.Message
    }
}


function Show-Settings {
    $sw = [Windows.Markup.XamlReader]::Parse((Convert-XamlTheme $settingsXaml))
    $sw.Owner = $win
    Set-ThemeResources $sw (Get-ActiveTheme)
    $script:settingsWin = $sw
    $pnl = $sw.FindName('PnlFields')

    # ---- 主题选择（改了立刻生效）----
    $themeRow = New-Object System.Windows.Controls.DockPanel
    $themeRow.Margin = [System.Windows.Thickness]::new(0,0,0,14)

    $themeLbl = New-Object System.Windows.Controls.TextBlock
    $themeLbl.Text = '界面主题'
    Bind-ThemeBrush $themeLbl '#8A94A6' 'Foreground'
    $themeLbl.FontSize = 11.5
    $themeLbl.Width = 190
    $themeLbl.VerticalAlignment = 'Center'
    [void]$themeRow.Children.Add($themeLbl)

    $themePanel = New-Object System.Windows.Controls.StackPanel
    $themePanel.Orientation = 'Horizontal'
    foreach ($opt in @(
        @{ K = 'auto';  T = '跟随系统' },
        @{ K = 'dark';  T = '深色' },
        @{ K = 'light'; T = '浅色' }
    )) {
        $rb = New-Object System.Windows.Controls.RadioButton
        $rb.Content = $opt.T
        $rb.GroupName = 'ThemeGroup'
        $rb.Tag = $opt.K
    Bind-ThemeBrush $rb '#E6EAF2' 'Foreground'
        $rb.Margin = [System.Windows.Thickness]::new(0,0,16,0)
        $rb.VerticalAlignment = 'Center'
        $rb.IsChecked = ("$($script:cfg.Theme)" -eq $opt.K)
        $rb.Add_Checked({
            param($s, $e)
            if ($script:themeApplying) { return }
            try { Set-Theme "$($s.Tag)"; Set-ThemeResources $sw (Get-ActiveTheme) } catch { }
        })
        [void]$themePanel.Children.Add($rb)
    }
    [void]$themeRow.Children.Add($themePanel)
    [void]$pnl.Children.Add($themeRow)

    $fields = @(
        @{ Key = 'CefKeep';      Label = 'CEF 保留数量';      Step = 1 },
        @{ Key = 'CefStaleMin';  Label = '仅清理超过(分钟)';  Step = 1 },
        @{ Key = 'CefAlert';     Label = 'CEF 泄漏阈值';      Step = 1 },
        @{ Key = 'CpuAlert';     Label = 'CPU 告警(核)';      Step = 0.1 },
        @{ Key = 'LowMemMB';     Label = '低内存告警(MB)';    Step = 50 },
        @{ Key = 'GuardMinute';  Label = '清理间隔(分钟)';    Step = 1 },
        @{ Key = 'NemuSpinPct';  Label = '空转阈值(%)';       Step = 5 },
        @{ Key = 'MemAlertMB';   Label = '单实例内存告警(MB)'; Step = 256 },
        @{ Key = 'LogKeepDays';  Label = '日志保留(天)';      Step = 1 },
        @{ Key = 'RecoverCheckSec';  Label = '掉线检测间隔(秒)'; Step = 10 },
        @{ Key = 'RecoverFailCount'; Label = '连续几次判定掉线';  Step = 1 },
        @{ Key = 'RecoverCooldown';  Label = '恢复冷却(分钟)';    Step = 1 },
        @{ Key = 'SleepLeadMin';    Label = '提前唤醒(分钟)';     Step = 1 },
        @{ Key = 'SleepMinHours';   Label = '最短休眠(小时)';     Step = 1 },
        @{ Key = 'SleepMaxHours';   Label = '最长休眠(小时)';     Step = 1 }
    )

    # 文本类设置（路径 / 包名）
    $textFields = @(
        @{ Key = 'MuMuRoot';  Label = 'MuMu 安装路径' },
        @{ Key = 'PkgScript'; Label = '脚本包名' },
        @{ Key = 'PkgGame';   Label = '游戏包名' }
    )

    # 开关类设置
    $toggles = @(
        @{ Key = 'AutoRecover'; Label = '脚本掉线自动恢复' },
        @{ Key = 'AutoSleep';   Label = '升级等待时休眠模拟器' },
        @{ Key = 'StartWithWindows'; Label = '开机自动启动面板（进托盘）' }
    )

    $checks = @{}
    foreach ($t in $toggles) {
        $row = New-Object System.Windows.Controls.DockPanel
        $row.Margin = [System.Windows.Thickness]::new(0,0,0,10)

        $lbl = New-Object System.Windows.Controls.TextBlock
        $lbl.Text = $t.Label
    Bind-ThemeBrush $lbl '#8A94A6' 'Foreground'
        $lbl.FontSize = 11.5
        $lbl.VerticalAlignment = 'Center'
        $lbl.Width = 190

        $cb = New-Object System.Windows.Controls.CheckBox
        $cb.IsChecked = ([bool]$script:cfg[$t.Key])
    Bind-ThemeBrush $cb '#E6EAF2' 'Foreground'
        $cb.VerticalAlignment = 'Center'

        [void]$row.Children.Add($lbl)
        [void]$row.Children.Add($cb)
        [void]$pnl.Children.Add($row)
        $checks[$t.Key] = $cb
    }

    $boxes = @{}
    foreach ($f in $fields) {
        $row = New-Object System.Windows.Controls.DockPanel
        $row.Margin = [System.Windows.Thickness]::new(0,0,0,10)

        $lbl = New-Object System.Windows.Controls.TextBlock
        $lbl.Text = $f.Label
    Bind-ThemeBrush $lbl '#8A94A6' 'Foreground'
        $lbl.FontSize = 11.5
        $lbl.VerticalAlignment = 'Center'
        $lbl.Width = 190

        $tb = New-Object System.Windows.Controls.TextBox
        $tb.Text = [string]$script:cfg[$f.Key]
        $tb.Width = 150
        $tb.Height = 26
        $tb.FontSize = 12
        $tb.FontFamily = New-Object System.Windows.Media.FontFamily('Consolas')
    Bind-ThemeBrush $tb '#0F141C' 'Background'
    Bind-ThemeBrush $tb '#E6EAF2' 'Foreground'
    Bind-ThemeBrush $tb '#161C26' 'BorderBrush'
        $tb.Padding = [System.Windows.Thickness]::new(6,3,6,3)

        [void]$row.Children.Add($lbl)
        [void]$row.Children.Add($tb)
        [void]$pnl.Children.Add($row)
        $boxes[$f.Key] = $tb
    }

    $textBoxes = @{}
    foreach ($f in $textFields) {
        $row = New-Object System.Windows.Controls.DockPanel
        $row.Margin = [System.Windows.Thickness]::new(0,0,0,10)

        $lbl = New-Object System.Windows.Controls.TextBlock
        $lbl.Text = $f.Label
    Bind-ThemeBrush $lbl '#8A94A6' 'Foreground'
        $lbl.FontSize = 11.5
        $lbl.VerticalAlignment = 'Center'
        $lbl.Width = 190

        $tb = New-Object System.Windows.Controls.TextBox
        $tb.Text = [string]$script:cfg[$f.Key]
        $tb.Width = 320
        $tb.Height = 26
        $tb.FontSize = 11
    Bind-ThemeBrush $tb '#0F141C' 'Background'
    Bind-ThemeBrush $tb '#E6EAF2' 'Foreground'
    Bind-ThemeBrush $tb '#161C26' 'BorderBrush'
        $tb.Padding = [System.Windows.Thickness]::new(6,3,6,3)

        [void]$row.Children.Add($lbl)
        [void]$row.Children.Add($tb)
        [void]$pnl.Children.Add($row)
        $textBoxes[$f.Key] = $tb
    }

    $sw.FindName('BtnSave').Add_Click({
        foreach ($k in $boxes.Keys) {
            $v = 0.0
            if ([double]::TryParse($boxes[$k].Text, [ref]$v)) { $script:cfg[$k] = $v }
        }
        foreach ($k in $checks.Keys) {
            $script:cfg[$k] = [bool]$checks[$k].IsChecked
        }
        foreach ($k in $textBoxes.Keys) {
            $v = $textBoxes[$k].Text
            if ($v -and $v.Trim()) { $script:cfg[$k] = $v.Trim() }
        }
        # 开机自启需要同步注册表
        [void](Set-Autostart ([bool]$script:cfg.StartWithWindows))
        Update-TrayMenu
        Save-Config
        $guardTimer.Interval = [TimeSpan]::FromMinutes([double]$script:cfg.GuardMinute)
        $recoverTimer.Interval = [TimeSpan]::FromSeconds([double]$script:cfg.RecoverCheckSec)
        $sw.Close()
    })
    $sw.FindName('BtnCancel').Add_Click({ $sw.Close() })
    $sw.Add_MouseLeftButtonDown({ try { $sw.DragMove() } catch { } })

    [void]$sw.ShowDialog()
    $script:settingsWin = $null
}


function Update-SleepButton {
    if (-not $btnSleep) { return }
    if ([bool]$script:cfg.AutoSleep) {
        $btnSleep.Content = '休眠 开'
        $btnSleep.Foreground = Brush '#3DDC84'
        $btnSleep.Background = Brush '#16241C'
    } else {
        $btnSleep.Content = '休眠 关'
        $btnSleep.Foreground = Brush '#8A94A6'
        $btnSleep.Background = Brush '#141A24'
    }
}


