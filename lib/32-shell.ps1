# 新界面：侧栏 + 分页 + 概览（v1.6.4 重构）
# 说明：本模块只负责「界面外壳与数据填充」，业务逻辑仍在 20-actions.ps1

$script:shell = @{}

function Get-ShellXaml {
    return @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="MuMuGuard" Width="1000" Height="700"
        WindowStartupLocation="CenterScreen"
        WindowStyle="None" AllowsTransparency="True" Background="Transparent"
        ResizeMode="CanMinimize" FontFamily="Microsoft YaHei UI">
  <Window.Resources>
    <SolidColorBrush x:Key="WinBg" Color="#1F1F23"/>
    <SolidColorBrush x:Key="SideBg" Color="#262629"/>
    <SolidColorBrush x:Key="Card" Color="#2B2B30"/>
    <SolidColorBrush x:Key="Line" Color="#33FFFFFF"/>
    <SolidColorBrush x:Key="T1" Color="#F2F2F5"/>
    <SolidColorBrush x:Key="T2" Color="#9E9EA6"/>
    <SolidColorBrush x:Key="T3" Color="#6E6E78"/>
    <SolidColorBrush x:Key="Green" Color="#34C759"/>
    <SolidColorBrush x:Key="Amber" Color="#FF9F0A"/>
    <SolidColorBrush x:Key="Blue" Color="#0A84FF"/>
    <SolidColorBrush x:Key="Red" Color="#FF453A"/>

    <Style x:Key="NavItem" TargetType="Border">
      <Setter Property="Height" Value="36"/>
      <Setter Property="CornerRadius" Value="8"/>
      <Setter Property="Margin" Value="0,1,0,1"/>
      <Setter Property="Background" Value="Transparent"/>
    </Style>
  </Window.Resources>

  <Border x:Name="Root" CornerRadius="14" Background="{StaticResource WinBg}" BorderBrush="#1AFFFFFF" BorderThickness="1">
    <Grid>
      <Grid.ColumnDefinitions>
        <ColumnDefinition Width="168"/>
        <ColumnDefinition Width="*"/>
      </Grid.ColumnDefinitions>

      <!-- 侧栏 -->
      <Border Grid.Column="0" Background="{StaticResource SideBg}" CornerRadius="14,0,0,14">
        <StackPanel Margin="14,26,14,14">
          <StackPanel Margin="0,0,0,24">
            <Border Width="56" Height="56" CornerRadius="15" HorizontalAlignment="Center">
              <Border.Background>
                <LinearGradientBrush StartPoint="0,0" EndPoint="0,1">
                  <GradientStop Color="#3C3C43" Offset="0"/>
                  <GradientStop Color="#2A2A30" Offset="1"/>
                </LinearGradientBrush>
              </Border.Background>
              <Border.BorderBrush>
                <LinearGradientBrush StartPoint="0,0" EndPoint="1,1">
                  <GradientStop Color="#40FFFFFF" Offset="0"/>
                  <GradientStop Color="#10FFFFFF" Offset="1"/>
                </LinearGradientBrush>
              </Border.BorderBrush>
              <Border BorderThickness="1" Padding="0">
                <Image x:Name="LogoImg" Stretch="UniformToFill"/>
              </Border>
            </Border>
            <TextBlock Text="MuMuGuard" Foreground="{StaticResource T1}" FontSize="15" FontWeight="SemiBold"
                       HorizontalAlignment="Center" Margin="0,9,0,0"/>
            <TextBlock x:Name="TxtVersion" Text="v1.6.3" Foreground="{StaticResource T3}" FontSize="10.5"
                       HorizontalAlignment="Center" Margin="0,2,0,0"/>
          </StackPanel>

          <Border x:Name="Nav1" Style="{StaticResource NavItem}" Background="#24FFFFFF" Padding="12,0">
            <StackPanel Orientation="Horizontal" VerticalAlignment="Center">
              <TextBlock x:Name="Nav1Ico" Text="▤" FontSize="13" Foreground="{StaticResource T1}" Width="20"/>
              <TextBlock x:Name="Nav1Txt" Text="概览" FontSize="12.5" Foreground="{StaticResource T1}" FontWeight="SemiBold"/>
            </StackPanel>
          </Border>
          <Border x:Name="Nav2" Style="{StaticResource NavItem}" Padding="12,0" Background="Transparent">
            <StackPanel Orientation="Horizontal" VerticalAlignment="Center">
              <TextBlock x:Name="Nav2Ico" Text="☰" FontSize="13" Foreground="{StaticResource T2}" Width="20"/>
              <TextBlock x:Name="Nav2Txt" Text="实例管理" FontSize="12.5" Foreground="{StaticResource T2}"/>
            </StackPanel>
          </Border>
          <Border x:Name="Nav3" Style="{StaticResource NavItem}" Padding="12,0" Background="Transparent">
            <StackPanel Orientation="Horizontal" VerticalAlignment="Center">
              <TextBlock x:Name="Nav3Ico" Text="♡" FontSize="13" Foreground="{StaticResource T2}" Width="20"/>
              <TextBlock x:Name="Nav3Txt" Text="健康检查" FontSize="12.5" Foreground="{StaticResource T2}"/>
            </StackPanel>
          </Border>
          <Border x:Name="Nav4" Style="{StaticResource NavItem}" Padding="12,0" Background="Transparent">
            <StackPanel Orientation="Horizontal" VerticalAlignment="Center">
              <TextBlock x:Name="Nav4Ico" Text="≡" FontSize="13" Foreground="{StaticResource T2}" Width="20"/>
              <TextBlock x:Name="Nav4Txt" Text="事件记录" FontSize="12.5" Foreground="{StaticResource T2}"/>
            </StackPanel>
          </Border>
          <Border x:Name="Nav5" Style="{StaticResource NavItem}" Padding="12,0" Background="Transparent">
            <StackPanel Orientation="Horizontal" VerticalAlignment="Center">
              <TextBlock x:Name="Nav5Ico" Text="⚙" FontSize="13" Foreground="{StaticResource T2}" Width="20"/>
              <TextBlock x:Name="Nav5Txt" Text="设置" FontSize="12.5" Foreground="{StaticResource T2}"/>
            </StackPanel>
          </Border>
        </StackPanel>
      </Border>

      <!-- 主区 -->
      <Grid Grid.Column="1" Margin="18,14,16,12">
        <Grid.RowDefinitions>
          <RowDefinition Height="Auto"/>
          <RowDefinition Height="Auto"/>
          <RowDefinition Height="*"/>
        </Grid.RowDefinitions>

        <!-- 标题 -->
        <Grid Grid.Row="0" x:Name="TitleBar">
          <StackPanel>
            <TextBlock x:Name="TxtTitle" Text="概览" FontSize="22" FontWeight="SemiBold" Foreground="{StaticResource T1}"/>
            <TextBlock x:Name="TxtSub" Text="" FontSize="11.5" Foreground="{StaticResource T3}" Margin="0,4,0,0"/>
          </StackPanel>
          <StackPanel Orientation="Horizontal" HorizontalAlignment="Right" VerticalAlignment="Top">
            <Border x:Name="BtnRefresh" Width="30" Height="30" CornerRadius="9" Background="#14FFFFFF" Margin="0,0,8,0">
              <TextBlock Text="↻" FontSize="14" Foreground="{StaticResource T2}" HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
            <Border x:Name="BtnMin" Width="30" Height="30" CornerRadius="9" Background="#14FFFFFF" Margin="0,0,8,0">
              <TextBlock Text="—" FontSize="12" Foreground="{StaticResource T2}" HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
            <Border x:Name="BtnHide" Width="30" Height="30" CornerRadius="9" Background="#14FFFFFF">
              <TextBlock Text="✕" FontSize="12" Foreground="{StaticResource T2}" HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
          </StackPanel>
        </Grid>

        <!-- 概览页 -->
        <Grid x:Name="Page1" Grid.Row="1" Grid.RowSpan="2" Visibility="Visible">
          <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="*"/>
          </Grid.RowDefinitions>

          <Grid Grid.Row="0" Margin="0,14,0,12">
            <Grid.ColumnDefinitions>
              <ColumnDefinition Width="*"/><ColumnDefinition Width="10"/>
              <ColumnDefinition Width="*"/><ColumnDefinition Width="10"/>
              <ColumnDefinition Width="*"/><ColumnDefinition Width="10"/>
              <ColumnDefinition Width="*"/>
            </Grid.ColumnDefinitions>

            <Border Grid.Column="0" CornerRadius="11" BorderBrush="{StaticResource Line}" BorderThickness="1" Height="86">
              <Border.Background>
                <LinearGradientBrush StartPoint="0,0" EndPoint="1,1">
                  <GradientStop Color="#33333A" Offset="0"/><GradientStop Color="#2A2A2F" Offset="1"/>
                </LinearGradientBrush>
              </Border.Background>
              <Grid Margin="12,11,12,11">
                <Border Width="22" Height="22" CornerRadius="7" Background="#18FFFFFF" VerticalAlignment="Top" HorizontalAlignment="Left">
                  <TextBlock Text="▤" FontSize="11" Foreground="#D8D8E0" HorizontalAlignment="Center" VerticalAlignment="Center"/>
                </Border>
                <StackPanel VerticalAlignment="Bottom">
                  <TextBlock Text="实例总数" FontSize="10.5" Foreground="{StaticResource T3}"/>
                  <TextBlock x:Name="StatTotal" Text="0" FontSize="19" FontWeight="SemiBold" Foreground="{StaticResource T1}" Margin="0,2,0,0"/>
                </StackPanel>
              </Grid>
            </Border>

            <Border Grid.Column="2" CornerRadius="11" BorderBrush="{StaticResource Line}" BorderThickness="1" Height="86">
              <Border.Background>
                <LinearGradientBrush StartPoint="0,0" EndPoint="1,1">
                  <GradientStop Color="#2E3A34" Offset="0"/><GradientStop Color="#2A2A2F" Offset="1"/>
                </LinearGradientBrush>
              </Border.Background>
              <Grid Margin="12,11,12,11">
                <Border Width="22" Height="22" CornerRadius="7" Background="#18FFFFFF" VerticalAlignment="Top" HorizontalAlignment="Left">
                  <TextBlock Text="▷" FontSize="11" Foreground="#D8D8E0" HorizontalAlignment="Center" VerticalAlignment="Center"/>
                </Border>
                <StackPanel VerticalAlignment="Bottom">
                  <TextBlock Text="运行中" FontSize="10.5" Foreground="{StaticResource T3}"/>
                  <TextBlock x:Name="StatRun" Text="0" FontSize="19" FontWeight="SemiBold" Foreground="{StaticResource T1}" Margin="0,2,0,0"/>
                </StackPanel>
              </Grid>
            </Border>

            <Border Grid.Column="4" CornerRadius="11" BorderBrush="{StaticResource Line}" BorderThickness="1" Height="86">
              <Border.Background>
                <LinearGradientBrush StartPoint="0,0" EndPoint="1,1">
                  <GradientStop Color="#33333A" Offset="0"/><GradientStop Color="#2A2A2F" Offset="1"/>
                </LinearGradientBrush>
              </Border.Background>
              <Grid Margin="12,11,12,11">
                <Border Width="22" Height="22" CornerRadius="7" Background="#18FFFFFF" VerticalAlignment="Top" HorizontalAlignment="Left">
                  <TextBlock Text="☾" FontSize="11" Foreground="#D8D8E0" HorizontalAlignment="Center" VerticalAlignment="Center"/>
                </Border>
                <StackPanel VerticalAlignment="Bottom">
                  <TextBlock Text="休眠中" FontSize="10.5" Foreground="{StaticResource T3}"/>
                  <TextBlock x:Name="StatSleep" Text="0" FontSize="19" FontWeight="SemiBold" Foreground="{StaticResource T1}" Margin="0,2,0,0"/>
                </StackPanel>
              </Grid>
            </Border>

            <Border Grid.Column="6" CornerRadius="11" BorderBrush="{StaticResource Line}" BorderThickness="1" Height="86">
              <Border.Background>
                <LinearGradientBrush StartPoint="0,0" EndPoint="1,1">
                  <GradientStop Color="#33333A" Offset="0"/><GradientStop Color="#2A2A2F" Offset="1"/>
                </LinearGradientBrush>
              </Border.Background>
              <Grid Margin="12,11,12,11">
                <Border Width="22" Height="22" CornerRadius="7" Background="#18FFFFFF" VerticalAlignment="Top" HorizontalAlignment="Left">
                  <TextBlock Text="⏻" FontSize="11" Foreground="#D8D8E0" HorizontalAlignment="Center" VerticalAlignment="Center"/>
                </Border>
                <StackPanel VerticalAlignment="Bottom">
                  <TextBlock Text="已关闭" FontSize="10.5" Foreground="{StaticResource T3}"/>
                  <TextBlock x:Name="StatOff" Text="0" FontSize="19" FontWeight="SemiBold" Foreground="{StaticResource T1}" Margin="0,2,0,0"/>
                </StackPanel>
              </Grid>
            </Border>
          </Grid>

          <Grid Grid.Row="1">
            <Grid.ColumnDefinitions>
              <ColumnDefinition Width="*"/><ColumnDefinition Width="12"/><ColumnDefinition Width="236"/>
            </Grid.ColumnDefinitions>

            <Grid Grid.Column="0">
              <Grid.RowDefinitions>
                <RowDefinition Height="Auto"/>
                <RowDefinition Height="12"/>
                <RowDefinition Height="*"/>
              </Grid.RowDefinitions>

              <!-- 实例监控 -->
              <Border Grid.Row="0" Background="{StaticResource Card}" CornerRadius="11" BorderBrush="{StaticResource Line}" BorderThickness="1">
                <StackPanel>
                  <Grid Margin="12,10,12,4">
                    <TextBlock Text="实例监控" FontSize="12.5" FontWeight="SemiBold" Foreground="{StaticResource T1}"/>
                    <TextBlock x:Name="TxtInstanceMore" Text="管理 ›" FontSize="10.5" Foreground="{StaticResource T3}" HorizontalAlignment="Right"/>
                  </Grid>
                  <StackPanel x:Name="PnlInstances"/>
                </StackPanel>
              </Border>

              <!-- 事件记录 -->
              <Border Grid.Row="2" Background="{StaticResource Card}" CornerRadius="11" BorderBrush="{StaticResource Line}" BorderThickness="1">
                <StackPanel>
                  <Grid Margin="12,10,12,4">
                    <TextBlock Text="事件记录" FontSize="12.5" FontWeight="SemiBold" Foreground="{StaticResource T1}"/>
                    <TextBlock x:Name="TxtEventMore" Text="查看全部 ›" FontSize="10.5" Foreground="{StaticResource T3}" HorizontalAlignment="Right"/>
                  </Grid>
                  <StackPanel x:Name="PnlEvents"/>
                </StackPanel>
              </Border>
            </Grid>

            <!-- 右栏 -->
            <StackPanel Grid.Column="2">
              <Border Background="{StaticResource Card}" CornerRadius="11" BorderBrush="{StaticResource Line}" BorderThickness="1">
                <StackPanel Margin="12,11,12,12">
                  <TextBlock Text="主机内存" FontSize="11" Foreground="{StaticResource T3}"/>
                  <StackPanel Orientation="Horizontal" Margin="0,3,0,0">
                    <TextBlock x:Name="TxtMemUsed" Text="0.0" FontSize="24" FontWeight="SemiBold" Foreground="{StaticResource T1}"/>
                    <TextBlock x:Name="TxtMemTotal" Text="/ 0 GB" FontSize="11" Foreground="{StaticResource T3}" VerticalAlignment="Bottom" Margin="4,0,0,4"/>
                  </StackPanel>
                  <Viewbox Height="46" Stretch="Fill" Margin="0,6,0,0">
                    <Canvas Width="240" Height="46" ClipToBounds="True">
                      <Path x:Name="TrendFill" Opacity="0.28">
                        <Path.Fill>
                          <LinearGradientBrush StartPoint="0,0" EndPoint="0,1">
                            <GradientStop Color="#0A84FF" Offset="0"/>
                            <GradientStop Color="#000A84FF" Offset="1"/>
                          </LinearGradientBrush>
                        </Path.Fill>
                      </Path>
                      <Path x:Name="TrendLine" Stroke="{StaticResource Blue}" StrokeThickness="1.6"/>
                    </Canvas>
                  </Viewbox>
                  <Border Height="5" CornerRadius="3" Background="#24FFFFFF" Margin="0,6,0,0">
                    <Border x:Name="MemBar" Width="0" Height="5" CornerRadius="3" Background="{StaticResource Blue}" HorizontalAlignment="Left"/>
                  </Border>
                  <StackPanel Orientation="Horizontal" Margin="0,8,0,0">
                    <Ellipse Width="5" Height="5" Fill="{StaticResource Blue}" VerticalAlignment="Center"/>
                    <TextBlock x:Name="TxtMemUsedLg" Text="已用 0 GB" FontSize="9.5" Foreground="{StaticResource T3}" Margin="4,0,12,0"/>
                    <Ellipse Width="5" Height="5" Fill="{StaticResource T3}" VerticalAlignment="Center"/>
                    <TextBlock x:Name="TxtMemFreeLg" Text="可用 0 GB" FontSize="9.5" Foreground="{StaticResource T3}" Margin="4,0,0,0"/>
                  </StackPanel>
                </StackPanel>
              </Border>

              <Border Background="{StaticResource Card}" CornerRadius="11" BorderBrush="{StaticResource Line}" BorderThickness="1" Margin="0,12,0,0">
                <StackPanel>
                  <TextBlock Text="系统健康" FontSize="12.5" FontWeight="SemiBold" Foreground="{StaticResource T1}" Margin="12,14,12,0"/>
                  <Grid Margin="12,10,12,14">
                    <Grid.ColumnDefinitions>
                      <ColumnDefinition Width="Auto"/><ColumnDefinition Width="*"/><ColumnDefinition Width="16"/>
                    </Grid.ColumnDefinitions>
                    <Border x:Name="HealthDot" Grid.Column="0" Width="26" Height="26" CornerRadius="13" Background="#2934C759" VerticalAlignment="Center">
                      <TextBlock x:Name="HealthGlyph" Text="✓" FontSize="13" Foreground="{StaticResource Green}" HorizontalAlignment="Center" VerticalAlignment="Center"/>
                    </Border>
                    <StackPanel Grid.Column="1" Margin="10,0,0,0" VerticalAlignment="Center">
                      <TextBlock x:Name="TxtHealthTitle" Text="检查通过" FontSize="12.5" Foreground="{StaticResource T1}"/>
                      <TextBlock x:Name="TxtHealthSub" Text="系统服务与资源状态正常" FontSize="10" Foreground="{StaticResource T3}" Margin="0,1,0,0"/>
                    </StackPanel>
                    <TextBlock Grid.Column="2" Text="›" FontSize="12" Foreground="#40FFFFFF" VerticalAlignment="Center" HorizontalAlignment="Right"/>
                  </Grid>
                </StackPanel>
              </Border>

              <Border Background="{StaticResource Card}" CornerRadius="11" BorderBrush="{StaticResource Line}" BorderThickness="1" Margin="0,12,0,0">
                <StackPanel>
                  <Grid Margin="12,9,12,9">
                    <TextBlock Text="下一次唤醒" FontSize="11" Foreground="{StaticResource T2}"/>
                    <TextBlock x:Name="TxtNextWake" Text="—" FontSize="11" Foreground="{StaticResource T1}" HorizontalAlignment="Right"/>
                  </Grid>
                  <Border Height="1" Background="#0DFFFFFF" Margin="12,0,12,0"/>
                  <Grid Margin="12,9,12,9">
                    <TextBlock Text="今日休眠" FontSize="11" Foreground="{StaticResource T2}"/>
                    <TextBlock x:Name="TxtSleepToday" Text="0 次" FontSize="11" Foreground="{StaticResource T1}" HorizontalAlignment="Right"/>
                  </Grid>
                </StackPanel>
              </Border>

              <Border Background="{StaticResource Card}" CornerRadius="11" BorderBrush="{StaticResource Line}" BorderThickness="1" Margin="0,12,0,0">
                <StackPanel>
                  <TextBlock Text="今日统计" FontSize="12.5" FontWeight="SemiBold" Foreground="{StaticResource T1}" Margin="12,10,12,4"/>
                  <Grid Margin="12,6,12,0">
                    <TextBlock Text="自动唤醒" FontSize="11" Foreground="{StaticResource T2}"/>
                    <TextBlock x:Name="TxtWakeToday" Text="0 次" FontSize="11" Foreground="{StaticResource T1}" HorizontalAlignment="Right"/>
                  </Grid>
                  <Grid Margin="12,8,12,0">
                    <TextBlock Text="内存清理" FontSize="11" Foreground="{StaticResource T2}"/>
                    <TextBlock x:Name="TxtCleanToday" Text="0 次" FontSize="11" Foreground="{StaticResource T1}" HorizontalAlignment="Right"/>
                  </Grid>
                  <Grid Margin="12,8,12,10">
                    <TextBlock Text="异常恢复" FontSize="11" Foreground="{StaticResource T2}"/>
                    <TextBlock x:Name="TxtRecoverToday" Text="0 次" FontSize="11" Foreground="{StaticResource T1}" HorizontalAlignment="Right"/>
                  </Grid>
                </StackPanel>
              </Border>
            </StackPanel>
          </Grid>
        </Grid>

        <!-- 其余页面占位（后续填充） -->
        <Grid x:Name="Page2" Grid.Row="1" Grid.RowSpan="2" Visibility="Collapsed">
          <Border Background="{StaticResource Card}" CornerRadius="11" BorderBrush="{StaticResource Line}" BorderThickness="1" Margin="0,14,0,0">
            <StackPanel>
              <TextBlock Text="实例管理" FontSize="18" FontWeight="SemiBold" Foreground="{StaticResource T1}" Margin="16,14,16,6"/>
              <TextBlock Text="每个实例的启动、唤醒、重启、检测开关。" FontSize="11.5" Foreground="{StaticResource T3}" Margin="16,0,16,10"/>
              <StackPanel x:Name="PnlManage" Margin="8,0,8,10"/>
            </StackPanel>
          </Border>
        </Grid>

        <Grid x:Name="Page3" Grid.Row="1" Grid.RowSpan="2" Visibility="Collapsed">
          <Border Background="{StaticResource Card}" CornerRadius="11" BorderBrush="{StaticResource Line}" BorderThickness="1" Margin="0,14,0,0">
            <StackPanel>
              <TextBlock Text="健康检查" FontSize="18" FontWeight="SemiBold" Foreground="{StaticResource T1}" Margin="16,14,16,6"/>
              <TextBlock Text="系统层面的内存、服务与权限状态。" FontSize="11.5" Foreground="{StaticResource T3}" Margin="16,0,16,10"/>
              <StackPanel x:Name="PnlHealthDetail" Margin="16,0,16,14"/>
            </StackPanel>
          </Border>
        </Grid>

        <Grid x:Name="Page4" Grid.Row="1" Grid.RowSpan="2" Visibility="Collapsed">
          <Border Background="{StaticResource Card}" CornerRadius="11" BorderBrush="{StaticResource Line}" BorderThickness="1" Margin="0,14,0,0">
            <StackPanel>
              <TextBlock Text="事件记录" FontSize="18" FontWeight="SemiBold" Foreground="{StaticResource T1}" Margin="16,14,16,6"/>
              <TextBlock Text="最近的守护动作与异常。" FontSize="11.5" Foreground="{StaticResource T3}" Margin="16,0,16,10"/>
              <ScrollViewer Height="460" VerticalScrollBarVisibility="Auto">
                <StackPanel x:Name="PnlEventDetail" Margin="16,0,16,14"/>
              </ScrollViewer>
            </StackPanel>
          </Border>
        </Grid>

        <Grid x:Name="Page5" Grid.Row="1" Grid.RowSpan="2" Visibility="Collapsed">
          <Border Background="{StaticResource Card}" CornerRadius="11" BorderBrush="{StaticResource Line}" BorderThickness="1" Margin="0,14,0,0">
            <StackPanel>
              <TextBlock Text="设置" FontSize="18" FontWeight="SemiBold" Foreground="{StaticResource T1}" Margin="16,14,16,6"/>
              <TextBlock Text="阈值、路径与休眠规则。" FontSize="11.5" Foreground="{StaticResource T3}" Margin="16,0,16,10"/>
              <StackPanel x:Name="PnlSettings" Margin="16,0,16,14"/>
            </StackPanel>
          </Border>
        </Grid>
      </Grid>
    </Grid>
  </Border>
</Window>
'@
}

# 生成一行实例（概览）
function New-InstanceRowShell {
    param($Row, $Icon, $IsSleep, $IsOff)

    $grid = New-Object System.Windows.Controls.Grid
    $grid.Height = 54
    $grid.Margin = New-Object System.Windows.Thickness(12, 0, 10, 0)

    foreach ($w in @('Auto', '*', 'Auto', '92', '68', '16')) {
        $cd = New-Object System.Windows.Controls.ColumnDefinition
        if ($w -eq '*') { $cd.Width = [System.Windows.GridLength]::new(1, [System.Windows.GridUnitType]::Star) }
        elseif ($w -eq 'Auto') { $cd.Width = [System.Windows.GridLength]::Auto }
        else { $cd.Width = [System.Windows.GridLength]::new([double]$w) }
        [void]$grid.ColumnDefinitions.Add($cd)
    }

    # 图标
    $tile = New-Object System.Windows.Controls.Border
    $tile.Width = 26; $tile.Height = 26; $tile.CornerRadius = [System.Windows.CornerRadius]::new(8)
    $tile.Background = New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.ColorConverter]::ConvertFromString('#00000000'))
    $tile.VerticalAlignment = 'Center'
    $img = New-Object System.Windows.Controls.Image
    $img.Width = 26; $img.Height = 26
    $img.Stretch = 'UniformToFill'
    if ($Icon) { $img.Source = $Icon }
    if ($IsOff) { $img.Opacity = 0.45 }
    $tile.Child = $img
    [System.Windows.Controls.Grid]::SetColumn($tile, 0)
    [void]$grid.Children.Add($tile)

    # 名称 + 副行
    $sp = New-Object System.Windows.Controls.StackPanel
    $sp.Margin = New-Object System.Windows.Thickness(10, 0, 0, 0)
    $sp.VerticalAlignment = 'Center'
    $nm = New-Object System.Windows.Controls.TextBlock
    $nm.Text = "$($Row.Name)"; $nm.FontSize = 12.5
    $nm.Foreground = New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.ColorConverter]::ConvertFromString('#F2F2F5'))
    $sub = New-Object System.Windows.Controls.TextBlock
    $sub.Text = "$($Row.Judge)"; $sub.FontSize = 10.5
    $sub.Foreground = New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.ColorConverter]::ConvertFromString('#6E6E78'))
    $sub.Margin = New-Object System.Windows.Thickness(0, 1, 0, 0)
    [void]$sp.Children.Add($nm); [void]$sp.Children.Add($sub)
    [System.Windows.Controls.Grid]::SetColumn($sp, 1)
    [void]$grid.Children.Add($sp)

    # 状态胶囊
    $pill = New-Object System.Windows.Controls.Border
    $pill.CornerRadius = [System.Windows.CornerRadius]::new(20)
    $pill.Padding = New-Object System.Windows.Thickness(8, 3, 8, 3)
    $pill.VerticalAlignment = 'Center'
    $pt = New-Object System.Windows.Controls.TextBlock
    $pt.FontSize = 10
    if ($IsSleep -and $Row.WakeAt) {
        $pill.Background = New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.ColorConverter]::ConvertFromString('#29FF9F0A'))
        $pt.Foreground = New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.ColorConverter]::ConvertFromString('#FF9F0A'))
        $pt.Text = '休眠'
    } elseif ($IsOff) {
        $pill.Background = New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.ColorConverter]::ConvertFromString('#14FFFFFF'))
        $pt.Foreground = New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.ColorConverter]::ConvertFromString('#9E9EA6'))
        $pt.Text = '关闭'
    } else {
        $pill.Background = New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.ColorConverter]::ConvertFromString('#2934C759'))
        $pt.Foreground = New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.ColorConverter]::ConvertFromString('#34C759'))
        $pt.Text = '运行中'
    }
    $pill.Child = $pt
    [System.Windows.Controls.Grid]::SetColumn($pill, 2)
    [void]$grid.Children.Add($pill)

    # 内存
    $msp = New-Object System.Windows.Controls.StackPanel
    $msp.Margin = New-Object System.Windows.Thickness(10, 0, 0, 0)
    $msp.VerticalAlignment = 'Center'
    $mt = New-Object System.Windows.Controls.TextBlock
    $mt.Text = $(if ($IsOff -or $IsSleep) { '—' } else { ('{0:N1} GB' -f ($Row.Private / 1024.0)) })
    $mt.FontSize = 10.5
    $mt.Foreground = New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.ColorConverter]::ConvertFromString('#9E9EA6'))
    $track = New-Object System.Windows.Controls.Border
    $track.Height = 3; $track.CornerRadius = [System.Windows.CornerRadius]::new(2)
    $track.Background = New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.ColorConverter]::ConvertFromString('#22FFFFFF'))
    $track.Margin = New-Object System.Windows.Thickness(0, 4, 0, 0)
    if (-not $IsOff -and $Row.Private -gt 0) {
        $fill = New-Object System.Windows.Controls.Border
        $fill.Height = 3; $fill.CornerRadius = [System.Windows.CornerRadius]::new(2)
        $fill.Background = New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.ColorConverter]::ConvertFromString('#0A84FF'))
        $fill.HorizontalAlignment = 'Left'
        $pct = [math]::Min(100, [math]::Max(4, ($Row.Private / 6144.0) * 100))
        $fill.Width = 56 * $pct / 100
        $track.Child = $fill
    }
    [void]$msp.Children.Add($mt); [void]$msp.Children.Add($track)
    [System.Windows.Controls.Grid]::SetColumn($msp, 3)
    [void]$grid.Children.Add($msp)

    # 时间
    $tsp = New-Object System.Windows.Controls.StackPanel
    $tsp.VerticalAlignment = 'Center'
    $tsp.HorizontalAlignment = 'Right'
    $tt = New-Object System.Windows.Controls.TextBlock
    $tt.FontSize = 12
    $tt.HorizontalAlignment = 'Right'
    $tt.Foreground = New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.ColorConverter]::ConvertFromString('#F2F2F5'))
    $ts = New-Object System.Windows.Controls.TextBlock
    $ts.FontSize = 9.5
    $ts.HorizontalAlignment = 'Right'
    $ts.Margin = New-Object System.Windows.Thickness(0, 1, 0, 0)
    $ts.Foreground = New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.ColorConverter]::ConvertFromString('#6E6E78'))
    if ($IsSleep -and $Row.WakeAt) {
        $tt.Text = $Row.WakeAt.ToString('HH:mm'); $ts.Text = '自动唤醒'
    } elseif ($IsOff) {
        $tt.Text = '—'; $ts.Text = '无任务'
    } else {
        $tt.Text = $(if ($Row.UpLeft) { $Row.UpLeft -replace '^剩\s*', '' } else { '—' })
        $ts.Text = $(if ($Row.UpDone) { $Row.UpDone.ToString('HH:mm') + ' 完成' } else { '无任务' })
    }
    [void]$tsp.Children.Add($tt); [void]$tsp.Children.Add($ts)
    [System.Windows.Controls.Grid]::SetColumn($tsp, 4)
    [void]$grid.Children.Add($tsp)

    # 箭头
    $ch = New-Object System.Windows.Controls.TextBlock
    $ch.Text = '›'; $ch.FontSize = 12
    $ch.Foreground = New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.ColorConverter]::ConvertFromString('#40FFFFFF'))
    $ch.VerticalAlignment = 'Center'; $ch.HorizontalAlignment = 'Right'
    [System.Windows.Controls.Grid]::SetColumn($ch, 5)
    [void]$grid.Children.Add($ch)

    return $grid
}

# 生成一条事件
function New-EventRowShell {
    param([string]$Time, [string]$Text, [string]$Level = 'info')
    $g = New-Object System.Windows.Controls.Grid
    $g.Height = 34
    $g.Margin = New-Object System.Windows.Thickness(12, 0, 12, 0)
    foreach ($w in @('46', '16', '*')) {
        $cd = New-Object System.Windows.Controls.ColumnDefinition
        if ($w -eq '*') { $cd.Width = [System.Windows.GridLength]::new(1, [System.Windows.GridUnitType]::Star) }
        else { $cd.Width = [System.Windows.GridLength]::new([double]$w) }
        [void]$g.ColumnDefinitions.Add($cd)
    }
    $t = New-Object System.Windows.Controls.TextBlock
    $t.Text = $Time; $t.FontSize = 10.5; $t.VerticalAlignment = 'Center'
    $t.Foreground = New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.ColorConverter]::ConvertFromString('#6E6E78'))
    [System.Windows.Controls.Grid]::SetColumn($t, 0); [void]$g.Children.Add($t)

    $dotColor = switch ($Level) { 'ok' { '#34C759' } 'warn' { '#FF9F0A' } 'err' { '#FF453A' } default { '#5A5A64' } }
    $e = New-Object System.Windows.Shapes.Ellipse
    $e.Width = 5; $e.Height = 5; $e.VerticalAlignment = 'Center'; $e.HorizontalAlignment = 'Left'
    $e.Fill = New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.ColorConverter]::ConvertFromString($dotColor))
    [System.Windows.Controls.Grid]::SetColumn($e, 1); [void]$g.Children.Add($e)

    $x = New-Object System.Windows.Controls.TextBlock
    $x.Text = $Text; $x.FontSize = 11; $x.VerticalAlignment = 'Center'
    $x.TextTrimming = 'CharacterEllipsis'
    $x.Foreground = New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.ColorConverter]::ConvertFromString($(if ($Level -eq 'err') { '#FF8078' } else { '#9E9EA6' })))
    [System.Windows.Controls.Grid]::SetColumn($x, 2); [void]$g.Children.Add($x)
    return $g
}
