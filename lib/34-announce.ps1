# 公告：每天第一次打开时弹出，可「今日不提醒」
# 内容在 Get-AnnounceContent 里改

function Get-AnnounceDateKey {
    return (Get-Date).ToString('yyyy-MM-dd')
}

function Test-AnnounceDue {
    try {
        if ($env:MMG_UITEST -eq '1') { return $false }
        if ($env:MMG_ANNOUNCE -eq '1') { return $true }
        # 每天第一次打开会弹；装了新版本后再弹一次（同一版本点了不再提醒就不会再出现）
        if ("$($script:cfg.AnnounceMuteDate)" -ne (Get-AnnounceDateKey)) { return $true }
        $seen = ''
        try { $seen = [string]$script:cfg.AnnounceSeenVer } catch { }
        return ($seen -ne [string]$script:appVersion)
    } catch { return $false }
}

function Set-AnnounceMuteToday {
    $script:cfg.AnnounceMuteDate = Get-AnnounceDateKey
    try { $script:cfg.AnnounceSeenVer = [string]$script:appVersion } catch { }
    Save-Config
}

function Get-AnnounceContent {
    return [pscustomobject]@{
        Title = 'MuMuGuard 2.0.23'
        Lines = @(
            '修好了「有休眠任务但到点不唤醒」：公告弹窗是模态的，以前会挡住后面的启动流程，'
            '没点掉公告时唤醒器根本没启动。现在先启动唤醒器和看护计时器，再弹公告。'
            '另外收紧了唤醒器进程检测，不会被命令行里带 Waker.ps1 的无关进程误判。'
            '2.0.22 已修前台误睡、休假记录被误撤销、唤醒器覆盖记录，建议一起升级。'
        )
        Repo = 'github.com/suuk324/MuMuGuard'
        RepoUrl = 'https://github.com/suuk324/MuMuGuard'
        QQ = '1128379535'
    }
}

function Show-Announcement {
    param([switch]$Force)

    if (-not $Force -and -not (Test-AnnounceDue)) { return }

    $c = Get-AnnounceContent
    $esc = { param($s) $s -replace '&', '&amp;' -replace '<', '&lt;' -replace '>', '&gt;' }
    $body = ''
    foreach ($ln in $c.Lines) {
        $body += '<TextBlock Text="' + (& $esc $ln) + '" FontSize="12" Foreground="{DynamicResource T_UI_TXT_L}" TextWrapping="Wrap" Margin="0,0,0,8"/>'
    }

    $xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="公告" Width="452" Height="356"
        WindowStyle="None" AllowsTransparency="True" Background="Transparent"
        WindowStartupLocation="CenterScreen" ShowInTaskbar="False"
        FontFamily="Microsoft YaHei UI">
  <Window.Resources>
    <Style x:Key="Plain" TargetType="Border">
      <Setter Property="CornerRadius" Value="9"/>
      <Setter Property="Padding" Value="12,7"/>
      <Setter Property="Cursor" Value="Hand"/>
    </Style>
  </Window.Resources>
  <Border x:Name="Root" CornerRadius="14" Background="#232327" BorderBrush="#33FFFFFF" BorderThickness="1">
    <Grid Margin="22,20,22,16">
      <Grid.RowDefinitions>
        <RowDefinition Height="Auto"/>
        <RowDefinition Height="*"/>
        <RowDefinition Height="Auto"/>
      </Grid.RowDefinitions>

      <StackPanel Grid.Row="0" Orientation="Horizontal">
        <Border Width="34" Height="34" CornerRadius="10" Background="{DynamicResource T_UI_SUB}">
          <Image x:Name="AnLogo" Stretch="UniformToFill"/>
        </Border>
        <StackPanel Margin="10,0,0,0" VerticalAlignment="Center">
          <TextBlock x:Name="AnTitle" Text="公告" FontSize="16" FontWeight="SemiBold" Foreground="#F2F2F5"/>
          <TextBlock x:Name="AnSub" Text="有更新时提示一次" FontSize="10.5" Foreground="#6E6E78" Margin="0,2,0,0"/>
        </StackPanel>
      </StackPanel>

      <StackPanel Grid.Row="1" Margin="0,14,0,0">
        <StackPanel x:Name="AnBody"/>
        <Border Background="#1A1A1E" CornerRadius="10" BorderBrush="{DynamicResource T_UI_CHIP2}" BorderThickness="1" Margin="0,4,0,0">
          <StackPanel Margin="12,10,12,10">
            <Grid x:Name="AnRepoRow" Background="Transparent" Margin="0,0,0,6">
              <TextBlock x:Name="AnRepo" Text="GitHub" FontSize="11.5" Foreground="{DynamicResource T_UI_LINK}"/>
            </Grid>
            <Grid x:Name="AnQQRow" Background="Transparent">
              <TextBlock x:Name="AnQQ" Text="QQ 群" FontSize="11.5" Foreground="{DynamicResource T_UI_TXT_L}"/>
            </Grid>
          </StackPanel>
        </Border>
      </StackPanel>

      <Grid Grid.Row="2" Margin="0,14,0,0">
        <TextBlock x:Name="AnHint" Text="" FontSize="10" Foreground="#6E6E78" VerticalAlignment="Center"/>
        <StackPanel Orientation="Horizontal" HorizontalAlignment="Right">
          <Border x:Name="BtnLater" Style="{StaticResource Plain}" Background="#1AFFFFFF" Margin="0,0,8,0">
            <TextBlock Text="关闭" FontSize="12" Foreground="{DynamicResource T_UI_TXT_B}"/>
          </Border>
          <Border x:Name="BtnMute" Style="{StaticResource Plain}" Background="#F2F2F5">
            <TextBlock Text="今日不提醒" FontSize="12" Foreground="{DynamicResource T_UI_ON_ACC}" FontWeight="SemiBold"/>
          </Border>
        </StackPanel>
      </Grid>
    </Grid>
  </Border>
</Window>
'@

    try {
        $dlg = [Windows.Markup.XamlReader]::Parse((Convert-XamlTheme $xaml))
    } catch {
        Write-Diag "公告窗口构建失败: $($_.Exception.Message)"
        return
    }
        # 关键：把主题色注入这个窗口，否则 DynamicResource 全为空 -> 背景透明、看着像死机
        try { Set-ThemeResources $dlg (Get-ActiveTheme) } catch { Write-Diag "公告主题注入失败: $($_.Exception.Message)" }
        # 兜底：万一资源没进去，至少给个不透明底色，避免又出现「透明窗口」
        try {
            $rootBd = $dlg.FindName('Root')
            if ($rootBd -and -not $rootBd.Background) {
                $rootBd.Background = New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.ColorConverter]::ConvertFromString('#232327'))
            }
            if ($rootBd -and -not $rootBd.BorderBrush) {
                $rootBd.BorderBrush = New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.ColorConverter]::ConvertFromString('#33FFFFFF'))
            }
        } catch { }

    # 内容
    # 公告是模态窗口，必须压在面板上面：否则主窗口被禁用、用户点不到公告，系统会一直叮叮响
    try {
        if ($win -and $win.IsVisible) { $dlg.Owner = $win }
        $dlg.Topmost = $true
        $dlg.Activate()
        $dlg.Add_Loaded({ try { $dlg.Activate(); $dlg.Focus() | Out-Null } catch { } }.GetNewClosure())
    } catch { }

    $dlg.FindName('AnTitle').Text = $c.Title
    $dlg.FindName('AnSub').Text = ('每天第一次打开时显示 · v' + $script:appVersion + ' · ' + (Get-Date).ToString('MM月dd日'))
    $bodyHost = $dlg.FindName('AnBody')
    foreach ($ln in $c.Lines) {
        $tb = New-Object System.Windows.Controls.TextBlock
        $tb.Text = $ln
        $tb.FontSize = 12
        $tb.TextWrapping = 'Wrap'
        $tb.Foreground = Brush '#B9B9C2'
        $tb.Margin = New-Object System.Windows.Thickness(0, 0, 0, 8)
        [void]$bodyHost.Children.Add($tb)
    }
    $dlg.FindName('AnRepo').Text = 'GitHub   ' + $c.Repo
    $dlg.FindName('AnQQ').Text = 'QQ 群    ' + $c.QQ + '（点击复制）'

    try {
        $lg = $dlg.FindName('AnLogo')
        if ($script:IconPng -and (Test-Path $script:IconPng)) {
            $lg.Source = [System.Windows.Media.Imaging.BitmapFrame]::Create([Uri]$script:IconPng)
        } elseif ($script:IconIco -and (Test-Path $script:IconIco)) {
            $lg.Source = [System.Windows.Media.Imaging.BitmapFrame]::Create([Uri]$script:IconIco)
        }
    } catch { }

    # 拖动
    Enable-WindowDrag ($dlg.FindName('Root')) $dlg

    # 打开仓库
    $openRepo = {
        try { Start-Process $c.RepoUrl } catch { }
    }.GetNewClosure()
    $dlg.FindName('AnRepoRow').Add_MouseLeftButtonUp($openRepo)

    # 复制群号
    $copyQQ = {
        try {
            [System.Windows.Clipboard]::SetText($c.QQ)
            $dlg.FindName('AnHint').Text = '群号已复制'
        } catch { }
    }.GetNewClosure()
    $dlg.FindName('AnQQRow').Add_MouseLeftButtonUp($copyQQ)

    # 关闭（明天还会出现）
    $close = {
        try { Set-AnnounceMuteToday_NoSave } catch { }
        $dlg.Close()
    }.GetNewClosure()
    $dlg.FindName('BtnLater').Add_MouseLeftButtonUp($close)

    # 今日不提醒
    $mute = {
        try { Set-AnnounceMuteToday; $dlg.FindName('AnHint').Text = '今天不再提醒' } catch { }
        $dlg.Close()
    }.GetNewClosure()
    $dlg.FindName('BtnMute').Add_MouseLeftButtonUp($mute)

    try {
        if ($script:dlgAudit) { $script:dlgAuditErrs += (Test-DialogTheme $dlg '公告'); try { $dlg.Close() } catch { }; return }
        $dlg.ShowDialog() | Out-Null
        Write-Diag '公告已显示'
    } catch {
        Write-Diag "公告显示失败: $($_.Exception.Message)"
    }
}

function Set-AnnounceMuteToday_NoSave {
    # 单纯关闭：不写日期，下次启动仍会显示
}
