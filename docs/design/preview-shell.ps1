# 预览：新界面（WPF 真实渲染，假数据）
# 用途：确认视觉效果后再合进 MuMuGuard 主程序
# 运行：powershell -STA -File preview-shell.ps1

Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase

$xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="MuMuGuard 预览" Width="1000" Height="700"
        WindowStartupLocation="CenterScreen"
        WindowStyle="None" AllowsTransparency="True" Background="Transparent"
        FontFamily="Microsoft YaHei UI">
  <Window.Resources>
    <SolidColorBrush x:Key="WinBg" Color="#1F1F23"/>
    <SolidColorBrush x:Key="SideBg" Color="#262629"/>
    <SolidColorBrush x:Key="Card" Color="#2B2B30"/>
    <SolidColorBrush x:Key="Card2" Color="#303035"/>
    <SolidColorBrush x:Key="Line" Color="#33FFFFFF"/>
    <SolidColorBrush x:Key="T1" Color="#F2F2F5"/>
    <SolidColorBrush x:Key="T2" Color="#9E9EA6"/>
    <SolidColorBrush x:Key="T3" Color="#6E6E78"/>
    <SolidColorBrush x:Key="Green" Color="#34C759"/>
    <SolidColorBrush x:Key="Amber" Color="#FF9F0A"/>
    <SolidColorBrush x:Key="Blue" Color="#0A84FF"/>

    <Style x:Key="Nav" TargetType="Border">
      <Setter Property="Height" Value="36"/>
      <Setter Property="CornerRadius" Value="8"/>
      <Setter Property="Margin" Value="0,1,0,1"/>
    </Style>
  </Window.Resources>

  <Border x:Name="Root" CornerRadius="14" Background="{StaticResource WinBg}" BorderBrush="#1AFFFFFF" BorderThickness="1">

    <Grid>
      <Grid.ColumnDefinitions>
        <ColumnDefinition Width="168"/>
        <ColumnDefinition Width="*"/>
      </Grid.ColumnDefinitions>

      <!-- 侧栏 -->
      <Border Grid.Column="0" Background="{StaticResource SideBg}" CornerRadius="14,0,0,14"
             >
        <Border BorderBrush="#1FFFFFFF" BorderThickness="0,0,1,0" CornerRadius="14,0,0,14">
          <StackPanel Margin="14,16,14,14">

            <!-- 品牌 -->
            <StackPanel Margin="0,22,0,26">
              <Border Width="52" Height="52" CornerRadius="14" HorizontalAlignment="Center">
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
                <Border BorderThickness="1">
                  <Image x:Name="LogoImg" Width="36" Height="36" Stretch="Uniform"/>
                </Border>
              </Border>
              <TextBlock Text="MuMuGuard" Foreground="{StaticResource T1}" FontSize="15" FontWeight="SemiBold"
                         HorizontalAlignment="Center" Margin="0,8,0,0"/>
              <TextBlock Text="v1.6.3" Foreground="{StaticResource T3}" FontSize="10.5"
                         HorizontalAlignment="Center" Margin="0,2,0,0"/>
            </StackPanel>

            <!-- 导航 -->
            <Border Style="{StaticResource Nav}" Background="#24FFFFFF" Padding="12,0">
              <StackPanel Orientation="Horizontal" VerticalAlignment="Center">
                <TextBlock Text="▤" FontSize="13" Foreground="{StaticResource T1}" Width="20"/>
                <TextBlock Text="概览" FontSize="12.5" Foreground="{StaticResource T1}" FontWeight="SemiBold"/>
              </StackPanel>
            </Border>
            <Border Style="{StaticResource Nav}" Padding="12,0">
              <StackPanel Orientation="Horizontal" VerticalAlignment="Center">
                <TextBlock Text="☰" FontSize="13" Foreground="{StaticResource T2}" Width="20"/>
                <TextBlock Text="实例管理" FontSize="12.5" Foreground="{StaticResource T2}"/>
              </StackPanel>
            </Border>
            <Border Style="{StaticResource Nav}" Padding="12,0">
              <StackPanel Orientation="Horizontal" VerticalAlignment="Center">
                <TextBlock Text="♡" FontSize="13" Foreground="{StaticResource T2}" Width="20"/>
                <TextBlock Text="健康检查" FontSize="12.5" Foreground="{StaticResource T2}"/>
              </StackPanel>
            </Border>
            <Border Style="{StaticResource Nav}" Padding="12,0">
              <StackPanel Orientation="Horizontal" VerticalAlignment="Center">
                <TextBlock Text="≡" FontSize="13" Foreground="{StaticResource T2}" Width="20"/>
                <TextBlock Text="事件记录" FontSize="12.5" Foreground="{StaticResource T2}"/>
              </StackPanel>
            </Border>
            <Border Style="{StaticResource Nav}" Padding="12,0">
              <StackPanel Orientation="Horizontal" VerticalAlignment="Center">
                <TextBlock Text="⚙" FontSize="13" Foreground="{StaticResource T2}" Width="20"/>
                <TextBlock Text="设置" FontSize="12.5" Foreground="{StaticResource T2}"/>
              </StackPanel>
            </Border>
          </StackPanel>
        </Border>
      </Border>

      <!-- 主区 -->
      <Grid Grid.Column="1" Margin="18,14,16,12">
        <Grid.RowDefinitions>
          <RowDefinition Height="Auto"/>
          <RowDefinition Height="Auto"/>
          <RowDefinition Height="*"/>
        </Grid.RowDefinitions>

        <!-- 标题 -->
        <Grid Grid.Row="0">
          <StackPanel>
            <TextBlock Text="晚上好" FontSize="22" FontWeight="SemiBold" Foreground="{StaticResource T1}"/>
            <TextBlock Text="5 个实例 · 1 个运行 · 2 个休眠" FontSize="11.5" Foreground="{StaticResource T3}" Margin="0,4,0,0"/>
          </StackPanel>
          <StackPanel Orientation="Horizontal" HorizontalAlignment="Right" VerticalAlignment="Top">
            <Border Width="30" Height="30" CornerRadius="9" Background="#14FFFFFF" Margin="0,0,8,0">
              <TextBlock Text="↻" FontSize="14" Foreground="{StaticResource T2}" HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
            <Border Width="30" Height="30" CornerRadius="9" Background="#14FFFFFF">
              <TextBlock Text="⋯" FontSize="14" Foreground="{StaticResource T2}" HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
          </StackPanel>
        </Grid>

        <!-- 统计卡 -->
        <Grid Grid.Row="1" Margin="0,16,0,14">
          <Grid.ColumnDefinitions>
            <ColumnDefinition Width="*"/><ColumnDefinition Width="10"/>
            <ColumnDefinition Width="*"/><ColumnDefinition Width="10"/>
            <ColumnDefinition Width="*"/><ColumnDefinition Width="10"/>
            <ColumnDefinition Width="*"/>
          </Grid.ColumnDefinitions>

          <Border Grid.Column="0" CornerRadius="11" BorderBrush="{StaticResource Line}" BorderThickness="1" Height="88">
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
                <TextBlock Text="5" FontSize="19" FontWeight="SemiBold" Foreground="{StaticResource T1}" Margin="0,2,0,0"/>
              </StackPanel>
            </Grid>
          </Border>

          <Border Grid.Column="2" CornerRadius="11" BorderBrush="{StaticResource Line}" BorderThickness="1" Height="88">
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
                <TextBlock Text="1" FontSize="19" FontWeight="SemiBold" Foreground="{StaticResource T1}" Margin="0,2,0,0"/>
              </StackPanel>
            </Grid>
          </Border>

          <Border Grid.Column="4" CornerRadius="11" BorderBrush="{StaticResource Line}" BorderThickness="1" Height="88">
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
                <TextBlock Text="2" FontSize="19" FontWeight="SemiBold" Foreground="{StaticResource T1}" Margin="0,2,0,0"/>
              </StackPanel>
            </Grid>
          </Border>

          <Border Grid.Column="6" CornerRadius="11" BorderBrush="{StaticResource Line}" BorderThickness="1" Height="88">
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
                <TextBlock Text="2" FontSize="19" FontWeight="SemiBold" Foreground="{StaticResource T1}" Margin="0,2,0,0"/>
              </StackPanel>
            </Grid>
          </Border>
        </Grid>

        <!-- 主体两栏 -->
        <Grid Grid.Row="2">
          <Grid.ColumnDefinitions>
            <ColumnDefinition Width="*"/>
            <ColumnDefinition Width="12"/>
            <ColumnDefinition Width="236"/>
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
                <Grid Margin="12,10,12,6">
                  <TextBlock Text="实例监控" FontSize="12.5" FontWeight="SemiBold" Foreground="{StaticResource T1}"/>
                  <TextBlock Text="⋯" FontSize="14" Foreground="{StaticResource T3}" HorizontalAlignment="Right"/>
                </Grid>

                <!-- 行 1 -->
                <Grid Margin="12,0,10,0" Height="54">
                  <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="Auto"/><ColumnDefinition Width="*"/>
                    <ColumnDefinition Width="Auto"/><ColumnDefinition Width="92"/>
                    <ColumnDefinition Width="68"/><ColumnDefinition Width="16"/>
                  </Grid.ColumnDefinitions>
                  <Border Grid.Column="0" Width="26" Height="26" CornerRadius="8" Background="#22FFFFFF" VerticalAlignment="Center">
                    <Image x:Name="Ava1" Width="22" Height="22" Stretch="Uniform" HorizontalAlignment="Center" VerticalAlignment="Center"/>
                  </Border>
                  <StackPanel Grid.Column="1" Margin="10,0,0,0" VerticalAlignment="Center">
                    <TextBlock Text="国服 微信" FontSize="12.5" Foreground="{StaticResource T1}"/>
                    <TextBlock Text="紫孔雀运行中 · 游戏运行中" FontSize="10.5" Foreground="{StaticResource T3}" Margin="0,1,0,0"/>
                  </StackPanel>
                  <Border Grid.Column="2" Background="#2934C759" CornerRadius="20" Padding="8,3" VerticalAlignment="Center">
                    <TextBlock Text="运行中" FontSize="10" Foreground="{StaticResource Green}"/>
                  </Border>
                  <StackPanel Grid.Column="3" Margin="10,0,0,0" VerticalAlignment="Center">
                    <TextBlock Text="1.8 GB" FontSize="10.5" Foreground="{StaticResource T2}"/>
                    <Border Height="3" CornerRadius="2" Background="#22FFFFFF" Margin="0,4,0,0">
                      <Border Width="56" Height="3" CornerRadius="2" Background="{StaticResource Blue}" HorizontalAlignment="Left"/>
                    </Border>
                  </StackPanel>
                  <StackPanel Grid.Column="4" VerticalAlignment="Center" HorizontalAlignment="Right">
                    <TextBlock Text="2:38" FontSize="12" Foreground="{StaticResource T1}" HorizontalAlignment="Right"/>
                    <TextBlock Text="22:23 完成" FontSize="9.5" Foreground="{StaticResource T3}" Margin="0,1,0,0"/>
                  </StackPanel>
                  <TextBlock Grid.Column="5" Text="›" FontSize="12" Foreground="#40FFFFFF" VerticalAlignment="Center" HorizontalAlignment="Right"/>
                </Grid>
                <Border Height="1" Background="#0DFFFFFF" Margin="12,0,12,0"/>

                <!-- 行 2 -->
                <Grid Margin="12,0,10,0" Height="54">
                  <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="Auto"/><ColumnDefinition Width="*"/>
                    <ColumnDefinition Width="Auto"/><ColumnDefinition Width="92"/>
                    <ColumnDefinition Width="68"/><ColumnDefinition Width="16"/>
                  </Grid.ColumnDefinitions>
                  <Border Grid.Column="0" Width="26" Height="26" CornerRadius="8" Background="#22FFFFFF" VerticalAlignment="Center">
                    <Image x:Name="Ava2" Width="22" Height="22" Stretch="Uniform" HorizontalAlignment="Center" VerticalAlignment="Center"/>
                  </Border>
                  <StackPanel Grid.Column="1" Margin="10,0,0,0" VerticalAlignment="Center">
                    <TextBlock Text="国际服" FontSize="12.5" Foreground="{StaticResource T1}"/>
                    <TextBlock Text="内存已释放" FontSize="10.5" Foreground="{StaticResource T3}" Margin="0,1,0,0"/>
                  </StackPanel>
                  <Border Grid.Column="2" Background="#29FF9F0A" CornerRadius="20" Padding="8,3" VerticalAlignment="Center">
                    <TextBlock Text="休眠" FontSize="10" Foreground="{StaticResource Amber}"/>
                  </Border>
                  <StackPanel Grid.Column="3" Margin="10,0,0,0" VerticalAlignment="Center">
                    <TextBlock Text="0.6 GB" FontSize="10.5" Foreground="{StaticResource T2}"/>
                    <Border Height="3" CornerRadius="2" Background="#22FFFFFF" Margin="0,4,0,0"/>
                  </StackPanel>
                  <StackPanel Grid.Column="4" VerticalAlignment="Center" HorizontalAlignment="Right">
                    <TextBlock Text="05:45" FontSize="12" Foreground="{StaticResource T1}" HorizontalAlignment="Right"/>
                    <TextBlock Text="自动唤醒" FontSize="9.5" Foreground="{StaticResource T3}" Margin="0,1,0,0"/>
                  </StackPanel>
                  <TextBlock Grid.Column="5" Text="›" FontSize="12" Foreground="#40FFFFFF" VerticalAlignment="Center" HorizontalAlignment="Right"/>
                </Grid>
                <Border Height="1" Background="#0DFFFFFF" Margin="12,0,12,0"/>

                <!-- 行 3 -->
                <Grid Margin="12,0,10,0" Height="54">
                  <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="Auto"/><ColumnDefinition Width="*"/>
                    <ColumnDefinition Width="Auto"/><ColumnDefinition Width="92"/>
                    <ColumnDefinition Width="68"/><ColumnDefinition Width="16"/>
                  </Grid.ColumnDefinitions>
                  <Border Grid.Column="0" Width="26" Height="26" CornerRadius="8" Background="#22FFFFFF" VerticalAlignment="Center">
                    <Image x:Name="Ava3" Width="22" Height="22" Stretch="Uniform" HorizontalAlignment="Center" VerticalAlignment="Center"/>
                  </Border>
                  <StackPanel Grid.Column="1" Margin="10,0,0,0" VerticalAlignment="Center">
                    <TextBlock Text="国服QQ" FontSize="12.5" Foreground="{StaticResource T1}"/>
                    <TextBlock Text="内存已释放" FontSize="10.5" Foreground="{StaticResource T3}" Margin="0,1,0,0"/>
                  </StackPanel>
                  <Border Grid.Column="2" Background="#29FF9F0A" CornerRadius="20" Padding="8,3" VerticalAlignment="Center">
                    <TextBlock Text="休眠" FontSize="10" Foreground="{StaticResource Amber}"/>
                  </Border>
                  <StackPanel Grid.Column="3" Margin="10,0,0,0" VerticalAlignment="Center">
                    <TextBlock Text="0.7 GB" FontSize="10.5" Foreground="{StaticResource T2}"/>
                    <Border Height="3" CornerRadius="2" Background="#22FFFFFF" Margin="0,4,0,0"/>
                  </StackPanel>
                  <StackPanel Grid.Column="4" VerticalAlignment="Center" HorizontalAlignment="Right">
                    <TextBlock Text="11:17" FontSize="12" Foreground="{StaticResource T1}" HorizontalAlignment="Right"/>
                    <TextBlock Text="自动唤醒" FontSize="9.5" Foreground="{StaticResource T3}" Margin="0,1,0,0"/>
                  </StackPanel>
                  <TextBlock Grid.Column="5" Text="›" FontSize="12" Foreground="#40FFFFFF" VerticalAlignment="Center" HorizontalAlignment="Right"/>
                </Grid>
                <Border Height="1" Background="#0DFFFFFF" Margin="12,0,12,0"/>

                <!-- 行 4 -->
                <Grid Margin="12,0,10,0" Height="54">
                  <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="Auto"/><ColumnDefinition Width="*"/>
                    <ColumnDefinition Width="Auto"/><ColumnDefinition Width="92"/>
                    <ColumnDefinition Width="68"/><ColumnDefinition Width="16"/>
                  </Grid.ColumnDefinitions>
                  <Border Grid.Column="0" Width="26" Height="26" CornerRadius="8" Background="#22FFFFFF" VerticalAlignment="Center">
                    <Image x:Name="Ava4" Width="22" Height="22" Stretch="Uniform" HorizontalAlignment="Center" VerticalAlignment="Center"/>
                  </Border>
                  <StackPanel Grid.Column="1" Margin="10,0,0,0" VerticalAlignment="Center">
                    <TextBlock Text="MuMu安卓设备-2" FontSize="12.5" Foreground="{StaticResource T1}"/>
                    <TextBlock Text="已关机" FontSize="10.5" Foreground="{StaticResource T3}" Margin="0,1,0,0"/>
                  </StackPanel>
                  <Border Grid.Column="2" Background="#14FFFFFF" CornerRadius="20" Padding="8,3" VerticalAlignment="Center">
                    <TextBlock Text="关闭" FontSize="10" Foreground="{StaticResource T2}"/>
                  </Border>
                  <StackPanel Grid.Column="3" Margin="10,0,0,0" VerticalAlignment="Center">
                    <TextBlock Text="—" FontSize="10.5" Foreground="{StaticResource T2}"/>
                    <Border Height="3" CornerRadius="2" Background="#22FFFFFF" Margin="0,4,0,0"/>
                  </StackPanel>
                  <StackPanel Grid.Column="4" VerticalAlignment="Center" HorizontalAlignment="Right">
                    <TextBlock Text="—" FontSize="12" Foreground="{StaticResource T1}" HorizontalAlignment="Right"/>
                    <TextBlock Text="无任务" FontSize="9.5" Foreground="{StaticResource T3}" Margin="0,1,0,0"/>
                  </StackPanel>
                  <TextBlock Grid.Column="5" Text="›" FontSize="12" Foreground="#40FFFFFF" VerticalAlignment="Center" HorizontalAlignment="Right"/>
                </Grid>
                <Border Height="1" Background="#0DFFFFFF" Margin="12,0,12,0"/>

                <!-- 行 5 -->
                <Grid Margin="12,0,10,8" Height="54">
                  <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="Auto"/><ColumnDefinition Width="*"/>
                    <ColumnDefinition Width="Auto"/><ColumnDefinition Width="92"/>
                    <ColumnDefinition Width="68"/><ColumnDefinition Width="16"/>
                  </Grid.ColumnDefinitions>
                  <Border Grid.Column="0" Width="26" Height="26" CornerRadius="8" Background="#22FFFFFF" VerticalAlignment="Center">
                    <Image x:Name="Ava5" Width="22" Height="22" Stretch="Uniform" HorizontalAlignment="Center" VerticalAlignment="Center"/>
                  </Border>
                  <StackPanel Grid.Column="1" Margin="10,0,0,0" VerticalAlignment="Center">
                    <TextBlock Text="MuMu安卓设备-4" FontSize="12.5" Foreground="{StaticResource T1}"/>
                    <TextBlock Text="已关机" FontSize="10.5" Foreground="{StaticResource T3}" Margin="0,1,0,0"/>
                  </StackPanel>
                  <Border Grid.Column="2" Background="#14FFFFFF" CornerRadius="20" Padding="8,3" VerticalAlignment="Center">
                    <TextBlock Text="关闭" FontSize="10" Foreground="{StaticResource T2}"/>
                  </Border>
                  <StackPanel Grid.Column="3" Margin="10,0,0,0" VerticalAlignment="Center">
                    <TextBlock Text="—" FontSize="10.5" Foreground="{StaticResource T2}"/>
                    <Border Height="3" CornerRadius="2" Background="#22FFFFFF" Margin="0,4,0,0"/>
                  </StackPanel>
                  <StackPanel Grid.Column="4" VerticalAlignment="Center" HorizontalAlignment="Right">
                    <TextBlock Text="—" FontSize="12" Foreground="{StaticResource T1}" HorizontalAlignment="Right"/>
                    <TextBlock Text="无任务" FontSize="9.5" Foreground="{StaticResource T3}" Margin="0,1,0,0"/>
                  </StackPanel>
                  <TextBlock Grid.Column="5" Text="›" FontSize="12" Foreground="#40FFFFFF" VerticalAlignment="Center" HorizontalAlignment="Right"/>
                </Grid>
              </StackPanel>
            </Border>

            <!-- 事件记录 -->
            <Border Grid.Row="2" Background="{StaticResource Card}" CornerRadius="11" BorderBrush="{StaticResource Line}" BorderThickness="1">
              <StackPanel>
                <Grid Margin="12,10,12,6">
                  <TextBlock Text="事件记录" FontSize="12.5" FontWeight="SemiBold" Foreground="{StaticResource T1}"/>
                  <TextBlock Text="查看全部 ›" FontSize="10.5" Foreground="{StaticResource T3}" HorizontalAlignment="Right"/>
                </Grid>
                <Grid Margin="12,0,12,0" Height="34">
                  <Grid.ColumnDefinitions><ColumnDefinition Width="46"/><ColumnDefinition Width="16"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
                  <TextBlock Grid.Column="0" Text="22:52" FontSize="10.5" Foreground="{StaticResource T3}" VerticalAlignment="Center"/>
                  <Ellipse Grid.Column="1" Width="5" Height="5" Fill="{StaticResource Green}" VerticalAlignment="Center" HorizontalAlignment="Left"/>
                  <TextBlock Grid.Column="2" Text="内存检查通过，可用 2.9 GB" FontSize="11" Foreground="{StaticResource T2}" VerticalAlignment="Center"/>
                </Grid>
                <Grid Margin="12,0,12,0" Height="34">
                  <Grid.ColumnDefinitions><ColumnDefinition Width="46"/><ColumnDefinition Width="16"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
                  <TextBlock Grid.Column="0" Text="22:50" FontSize="10.5" Foreground="{StaticResource T3}" VerticalAlignment="Center"/>
                  <Ellipse Grid.Column="1" Width="5" Height="5" Fill="#5A5A64" VerticalAlignment="Center" HorizontalAlignment="Left"/>
                  <TextBlock Grid.Column="2" Text="清理 CEF 回收 0 个（今日 24 次）" FontSize="11" Foreground="{StaticResource T2}" VerticalAlignment="Center"/>
                </Grid>
                <Grid Margin="12,0,12,0" Height="34">
                  <Grid.ColumnDefinitions><ColumnDefinition Width="46"/><ColumnDefinition Width="16"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
                  <TextBlock Grid.Column="0" Text="22:21" FontSize="10.5" Foreground="{StaticResource T3}" VerticalAlignment="Center"/>
                  <Ellipse Grid.Column="1" Width="5" Height="5" Fill="{StaticResource Amber}" VerticalAlignment="Center" HorizontalAlignment="Left"/>
                  <TextBlock Grid.Column="2" Text="实例 3 关机休眠，11:17 唤醒" FontSize="11" Foreground="{StaticResource T2}" VerticalAlignment="Center"/>
                </Grid>
                <Grid Margin="12,0,12,0" Height="34">
                  <Grid.ColumnDefinitions><ColumnDefinition Width="46"/><ColumnDefinition Width="16"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
                  <TextBlock Grid.Column="0" Text="22:10" FontSize="10.5" Foreground="{StaticResource T3}" VerticalAlignment="Center"/>
                  <Ellipse Grid.Column="1" Width="5" Height="5" Fill="#FF453A" VerticalAlignment="Center" HorizontalAlignment="Left"/>
                  <TextBlock Grid.Column="2" Text="实例 3 未运行，连续 1/2" FontSize="11" Foreground="#FF8078" VerticalAlignment="Center"/>
                </Grid>
                
              </StackPanel>
            </Border>
          </Grid>

          <!-- 右栏 -->
          <StackPanel Grid.Column="2" VerticalAlignment="Top">
            <Border Background="{StaticResource Card}" CornerRadius="11" BorderBrush="{StaticResource Line}" BorderThickness="1">
              <StackPanel Margin="12,11,12,12">
                <TextBlock Text="主机内存" FontSize="11" Foreground="{StaticResource T3}"/>
                <StackPanel Orientation="Horizontal" Margin="0,3,0,0">
                  <TextBlock Text="5.2" FontSize="24" FontWeight="SemiBold" Foreground="{StaticResource T1}"/>
                  <TextBlock Text="/ 15.7 GB" FontSize="11" Foreground="{StaticResource T3}" VerticalAlignment="Bottom" Margin="4,0,0,4"/>
                </StackPanel>

                <!-- 趋势曲线 -->
                <Viewbox Height="46" Stretch="Fill" Margin="0,6,0,0">
                  <Canvas Width="240" Height="46" ClipToBounds="True">
                    <Path Stroke="{StaticResource Blue}" StrokeThickness="1.6"
                          Data="M0,34 C18,30 30,20 48,22 C66,24 76,34 96,30 C116,26 126,12 148,14 C170,16 196,10 240,6"/>
                    <Path Opacity="0.28" Data="M0,34 C18,30 30,20 48,22 C66,24 76,34 96,30 C116,26 126,12 148,14 C170,16 196,10 240,6 L240,46 L0,46 Z">
                      <Path.Fill>
                        <LinearGradientBrush StartPoint="0,0" EndPoint="0,1">
                          <GradientStop Color="#0A84FF" Offset="0"/>
                          <GradientStop Color="#000A84FF" Offset="1"/>
                        </LinearGradientBrush>
                      </Path.Fill>
                    </Path>
                  </Canvas>
                </Viewbox>

                <Border Height="5" CornerRadius="3" Background="#24FFFFFF" Margin="0,6,0,0">
                  <Border Width="96" Height="5" CornerRadius="3" Background="{StaticResource Blue}" HorizontalAlignment="Left"/>
                </Border>
                <StackPanel Orientation="Horizontal" Margin="0,8,0,0">
                  <Ellipse Width="5" Height="5" Fill="{StaticResource Blue}" VerticalAlignment="Center"/>
                  <TextBlock Text="已用 5.2 GB" FontSize="9.5" Foreground="{StaticResource T3}" Margin="4,0,12,0"/>
                  <Ellipse Width="5" Height="5" Fill="{StaticResource T3}" VerticalAlignment="Center"/>
                  <TextBlock Text="可用 10.5 GB" FontSize="9.5" Foreground="{StaticResource T3}" Margin="4,0,0,0"/>
                </StackPanel>
              </StackPanel>
            </Border>

            <Border Background="{StaticResource Card}" CornerRadius="11" BorderBrush="{StaticResource Line}" BorderThickness="1" Margin="0,12,0,0">
              <StackPanel>
                <TextBlock Text="系统健康" FontSize="12.5" FontWeight="SemiBold" Foreground="{StaticResource T1}" Margin="12,12,12,0"/>
                <Grid Margin="12,10,12,14">
                  <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="Auto"/><ColumnDefinition Width="*"/><ColumnDefinition Width="16"/>
                  </Grid.ColumnDefinitions>
                  <Border Grid.Column="0" Width="26" Height="26" CornerRadius="13" Background="#2934C759" VerticalAlignment="Center">
                    <TextBlock Text="✓" FontSize="13" Foreground="{StaticResource Green}" HorizontalAlignment="Center" VerticalAlignment="Center"/>
                  </Border>
                  <StackPanel Grid.Column="1" Margin="10,0,0,0" VerticalAlignment="Center">
                    <TextBlock Text="检查通过" FontSize="12.5" Foreground="{StaticResource T1}"/>
                    <TextBlock Text="系统服务与资源状态正常" FontSize="10" Foreground="{StaticResource T3}" Margin="0,1,0,0"/>
                  </StackPanel>
                  <TextBlock Grid.Column="2" Text="›" FontSize="12" Foreground="#40FFFFFF" VerticalAlignment="Center" HorizontalAlignment="Right"/>
                </Grid>
              </StackPanel>
            </Border>

            <Border Background="{StaticResource Card}" CornerRadius="11" BorderBrush="{StaticResource Line}" BorderThickness="1" Margin="0,12,0,0">
              <StackPanel>
                <Grid Margin="12,9,12,9">
                  <TextBlock Text="下一次唤醒" FontSize="11" Foreground="{StaticResource T2}"/>
                  <TextBlock Text="05:45" FontSize="11" Foreground="{StaticResource T1}" HorizontalAlignment="Right"/>
                </Grid>
                <Border Height="1" Background="#0DFFFFFF" Margin="12,0,12,0"/>
                <Grid Margin="12,9,12,9">
                  <TextBlock Text="今日休眠" FontSize="11" Foreground="{StaticResource T2}"/>
                  <TextBlock Text="2 次" FontSize="11" Foreground="{StaticResource T1}" HorizontalAlignment="Right"/>
                </Grid>
              </StackPanel>
            </Border>

            <Border Background="{StaticResource Card}" CornerRadius="11" BorderBrush="{StaticResource Line}" BorderThickness="1" Margin="0,12,0,0">
              <StackPanel>
                <TextBlock Text="今日统计" FontSize="12.5" FontWeight="SemiBold" Foreground="{StaticResource T1}" Margin="12,10,12,4"/>
                <Grid Margin="12,6,12,0">
                  <TextBlock Text="自动唤醒" FontSize="11" Foreground="{StaticResource T2}"/>
                  <TextBlock Text="3 次" FontSize="11" Foreground="{StaticResource T1}" HorizontalAlignment="Right"/>
                </Grid>
                <Grid Margin="12,8,12,0">
                  <TextBlock Text="内存清理" FontSize="11" Foreground="{StaticResource T2}"/>
                  <TextBlock Text="24 次" FontSize="11" Foreground="{StaticResource T1}" HorizontalAlignment="Right"/>
                </Grid>
                <Grid Margin="12,8,12,10">
                  <TextBlock Text="异常恢复" FontSize="11" Foreground="{StaticResource T2}"/>
                  <TextBlock Text="1 次" FontSize="11" Foreground="{StaticResource T1}" HorizontalAlignment="Right"/>
                </Grid>
              </StackPanel>
            </Border>
          </StackPanel>
        </Grid>
      </Grid>
    </Grid>
  </Border>
</Window>
'@

$win = [Windows.Markup.XamlReader]::Parse($xaml)

# 拖动 / 窗口按钮
$win.FindName('Root').Add_MouseLeftButtonDown({ $win.DragMove() })


Add-Type -AssemblyName System.Drawing
function Load-Ico([string]$path){
  $ico = New-Object System.Drawing.Icon($path)
  return [System.Windows.Interop.Imaging]::CreateBitmapSourceFromHIcon(
    $ico.Handle, [System.Windows.Int32Rect]::Empty,
    [System.Windows.Media.Imaging.BitmapSizeOptions]::FromEmptyOptions())
}
$logo = Load-Ico 'C:\Users\MOOM\Documents\MuMuGuard\MuMuGuard.ico'
$mumu = Load-Ico 'D:\Program Files\Netease\MuMu\nx_device\15.0\shell\MuMuPlayer.ico'
$win.FindName('LogoImg').Source = $logo
foreach($n in @('Ava1','Ava2','Ava3','Ava4','Ava5')){
  $c = $win.FindName($n); if($c){ $c.Source = $mumu }
}
$win.ShowDialog() | Out-Null