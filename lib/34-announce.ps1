# 公告：每天第一次打开时弹出，可「今日不提醒」
# 内容在 Get-AnnounceContent 里改

function Get-AnnounceDateKey {
    return (Get-Date).ToString('yyyy-MM-dd')
}

function Test-AnnounceDue {
    try {
        if ($env:MMG_UITEST -eq '1') { return $false }
        if ($env:MMG_ANNOUNCE -eq '1') { return $true }
        return ("$($script:cfg.AnnounceMuteDate)" -ne (Get-AnnounceDateKey))
    } catch { return $false }
}

function Set-AnnounceMuteToday {
    $script:cfg.AnnounceMuteDate = Get-AnnounceDateKey
    Save-Config
}

function Get-AnnounceContent {
    return [pscustomobject]@{
        Title = 'MuMuGuard 已更新'
        Lines = @(
            '界面全部重做：概览、实例管理、健康检查、事件记录、设置五个页面，外加紧凑环视图和手机页。'
            '看护、掉线恢复、升级休眠的判断逻辑没有变，可以照常用。'
            '用得顺手的话，欢迎到群里聊聊，或者直接提需求。'
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
        Title="公告" Width="452" Height="304"
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
          <TextBlock x:Name="AnSub" Text="每天打开时显示一次" FontSize="10.5" Foreground="#6E6E78" Margin="0,2,0,0"/>
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

    # 内容
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
    $dlg.FindName('Root').Add_MouseLeftButtonDown({ try { $dlg.DragMove() } catch { } })

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
        $dlg.ShowDialog() | Out-Null
        Write-Diag '公告已显示'
    } catch {
        Write-Diag "公告显示失败: $($_.Exception.Message)"
    }
}

function Set-AnnounceMuteToday_NoSave {
    # 单纯关闭：不写日期，下次启动仍会显示
}
