#Requires -Version 5.1
#
# 托盘：显示/隐藏、菜单、彻底退出、告警扫描
# 本文件由拆分脚本生成，供 MuMuGuardApp.ps1 dot-source（共享同一 $script: 作用域）

function Show-Panel {
    try {
        $win.ShowInTaskbar = $true
        $win.Show()
        $win.WindowState = 'Normal'
        $win.Activate()
        $win.Topmost = $true
        $win.Topmost = $false
    } catch { Write-Diag "显示面板失败: $($_.Exception.Message)" }
}


function Hide-Panel {
    try {
        $win.WindowState  = 'Minimized'
        $win.ShowInTaskbar = $false
    } catch { Write-Diag "隐藏面板失败: $($_.Exception.Message)" }
}


function Stop-AllWakers {
    try {
        Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -ErrorAction SilentlyContinue |
            Where-Object { $_.CommandLine -like '*Waker.ps1*' } |
            ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
    } catch { }
}


function Exit-App {
    $sleeping = @(Get-SleepList)
    if ($sleeping.Count -gt 0) {
        $names = ($sleeping | ForEach-Object { "实例 $($_.Index)（$($_.WakeAt.ToString().Substring(11)) 唤醒）" }) -join "`n"
        $msg = "以下实例正在休眠等待唤醒：`n`n$names`n`n彻底退出后唤醒器会一并关闭，这些实例将不会被自动唤醒。`n`n确定要退出吗？"
        $res = [System.Windows.MessageBox]::Show($msg, 'MuMuGuard', 'YesNo', 'Warning')
        if ($res -ne 'Yes') { return }
    }
    $script:reallyExit = $true
    try { $win.Close() } catch { }
}


function New-Tray {
    $iconPath = Join-Path $Root 'MuMuGuard.ico'
    $ni = New-Object System.Windows.Forms.NotifyIcon
    try {
        $ni.Icon = New-Object System.Drawing.Icon($iconPath)
    } catch {
        $ni.Icon = [System.Drawing.SystemIcons]::Application
    }
    $ni.Text = 'MuMuGuard 看护面板'
    $ni.Visible = $true

    $menu = New-Object System.Windows.Forms.ContextMenuStrip
    $menu.ShowImageMargin = $false
    $menu.Font = New-Object System.Drawing.Font('Microsoft YaHei UI', 9)

    # 顶部标题（不可点击，纯标识）
    $miTitle = New-Object System.Windows.Forms.ToolStripMenuItem('MuMuGuard')
    $miTitle.Enabled = $false
    $miTitle.ForeColor = [System.Drawing.Color]::FromArgb(120, 130, 150)
    $miTitle.Font = New-Object System.Drawing.Font('Microsoft YaHei UI', 8)

    $miShow = New-Object System.Windows.Forms.ToolStripMenuItem('显示面板')
    $miShow.Add_Click({ Show-Panel })

    # 分组标题：开关类
    $miGroupSwitch = New-Object System.Windows.Forms.ToolStripMenuItem('  开关')
    $miGroupSwitch.Enabled = $false
    $miGroupSwitch.ForeColor = [System.Drawing.Color]::FromArgb(95, 105, 125)
    $miGroupSwitch.Font = New-Object System.Drawing.Font('Microsoft YaHei UI', 8)

    $miGuard = New-Object System.Windows.Forms.ToolStripMenuItem('看护')
    $miGuard.Add_Click({ Set-GuardState; Update-TrayMenu })

    $miSleep = New-Object System.Windows.Forms.ToolStripMenuItem('升级休眠')
    $miSleep.Add_Click({
        $script:cfg.AutoSleep = -not ([bool]$script:cfg.AutoSleep)
        Save-Config
        Update-SleepButton
        Update-TrayMenu
        Update-Ui
    })

    $miStart = New-Object System.Windows.Forms.ToolStripMenuItem('开机自启')
    $miStart.Add_Click({
        $script:cfg.StartWithWindows = -not ([bool]$script:cfg.StartWithWindows)
        [void](Set-Autostart ([bool]$script:cfg.StartWithWindows))
        Save-Config
        Update-TrayMenu
    })

    # 退出：单独分组 + 红色 + 二次确认，防止误点
    $sep = New-Object System.Windows.Forms.ToolStripSeparator
    $miExit = New-Object System.Windows.Forms.ToolStripMenuItem('退出程序…')
    $miExit.ForeColor = [System.Drawing.Color]::FromArgb(242, 109, 109)
    $miExit.Add_Click({ Exit-App })

    $miUpdate = New-Object System.Windows.Forms.ToolStripMenuItem('检查更新…')
    $miUpdate.Add_Click({ Invoke-UpdateCheckUI -Silent $false })

    [void]$menu.Items.Add($miTitle)
    [void]$menu.Items.Add($miShow)
    [void]$menu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator))
    [void]$menu.Items.Add($miGroupSwitch)
    [void]$menu.Items.Add($miGuard)
    [void]$menu.Items.Add($miSleep)
    [void]$menu.Items.Add($miStart)
    [void]$menu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator))
    [void]$menu.Items.Add($miUpdate)
    [void]$menu.Items.Add($sep)
    [void]$menu.Items.Add($miExit)

    $ni.ContextMenuStrip = $menu
    $ni.Add_MouseDoubleClick({ Show-Panel })
    $ni.Add_MouseClick({
        param($s, $e)
        if ($e.Button -eq [System.Windows.Forms.MouseButtons]::Left) { Show-Panel }
    })

    $script:trayMenu = $menu
    $script:miGuard = $miGuard
    $script:miSleep = $miSleep
    $script:miStart = $miStart
    return $ni
}


function Update-TrayMenu {
    try {
        if ($script:guardRunning) {
            $script:miGuard.Text = '看护：运行中（点击停止）'
        } else {
            $script:miGuard.Text = '看护：已停止（点击启动）'
        }
        if ([bool]$script:cfg.AutoSleep) {
            $script:miSleep.Text = '升级休眠：开（点击关闭）'
        } else {
            $script:miSleep.Text = '升级休眠：关（点击开启）'
        }
        if ([bool]$script:cfg.StartWithWindows) {
            $script:miStart.Text = '开机自启：开（点击关闭）'
        } else {
            $script:miStart.Text = '开机自启：关（点击开启）'
        }
    } catch { }
}


function Invoke-AlertScan {
    $file = Get-LogFile
    if (-not (Test-Path $file)) { return }
    try {
        $fi = Get-Item $file
        if (-not $script:alertCache) {
            $script:alertCache = @{ Len = $fi.Length; Time = $fi.LastWriteTime }
            return
        }
        if ($fi.Length -eq $script:alertCache.Len -and $fi.LastWriteTime -eq $script:alertCache.Time) { return }
        $script:alertCache = @{ Len = $fi.Length; Time = $fi.LastWriteTime }

        $rows = @(Import-Csv $file -ErrorAction Stop)
        $fails = @($rows | Where-Object { $_.Action -eq 'WAKE_FAIL' } | Select-Object -Last 1)
        if ($fails.Count -eq 0) { return }
        $f = $fails[0]
        $key = "$($f.Time)|$($f.Instance)"
        if ($script:lastWakeFail -eq $key) { return }
        $script:lastWakeFail = $key

        try {
            $tray.ShowBalloonTip(8000, 'MuMuGuard 唤醒失败',
                ("{0} 未能自动唤醒，请检查。" -f $f.Instance),
                [System.Windows.Forms.ToolTipIcon]::Error)
        } catch { }
        try { Show-Panel } catch { }
    } catch { }
}


