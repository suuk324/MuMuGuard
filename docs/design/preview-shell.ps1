# 预览：全套五页（WPF 真实渲染，假数据）
# 运行：powershell -STA -File preview-shell.ps1

Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Drawing

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
    <Style x:Key="Pill" TargetType="Border">
      <Setter Property="CornerRadius" Value="7"/>
      <Setter Property="Padding" Value="10,4"/>
      <Setter Property="Background" Value="#1AFFFFFF"/>
    </Style>
  </Window.Resources>

  <Border x:Name="Root" CornerRadius="14" Background="{StaticResource WinBg}" BorderBrush="#1AFFFFFF" BorderThickness="1">
    <Grid>
      <Grid.ColumnDefinitions>
        <ColumnDefinition Width="168"/>
        <ColumnDefinition Width="*"/>
      </Grid.ColumnDefinitions>

      <Border Grid.Column="0" Background="{StaticResource SideBg}" CornerRadius="14,0,0,14">
        <StackPanel Margin="14,26,14,14">
          <StackPanel Margin="0,0,0,24">
            <Border Width="56" Height="56" CornerRadius="15" HorizontalAlignment="Center">
              <Border.Background>
                <LinearGradientBrush StartPoint="0,0" EndPoint="0,1">
                  <GradientStop Color="#3C3C43" Offset="0"/><GradientStop Color="#2A2A30" Offset="1"/>
                </LinearGradientBrush>
              </Border.Background>
              <Border.BorderBrush>
                <LinearGradientBrush StartPoint="0,0" EndPoint="1,1">
                  <GradientStop Color="#40FFFFFF" Offset="0"/><GradientStop Color="#10FFFFFF" Offset="1"/>
                </LinearGradientBrush>
              </Border.BorderBrush>
              <Border BorderThickness="1" Padding="0">
                <Image x:Name="LogoImg" Stretch="UniformToFill"/>
              </Border>
            </Border>
            <TextBlock Text="MuMuGuard" Foreground="{StaticResource T1}" FontSize="15" FontWeight="SemiBold"
                       HorizontalAlignment="Center" Margin="0,9,0,0"/>
            <TextBlock Text="v1.6.3" Foreground="{StaticResource T3}" FontSize="10.5"
                       HorizontalAlignment="Center" Margin="0,2,0,0"/>
          </StackPanel>

          <Border x:Name="Nav1" Style="{StaticResource NavItem}" Background="#24FFFFFF" Padding="12,0">
            <StackPanel Orientation="Horizontal" VerticalAlignment="Center">
              <TextBlock x:Name="Nav1Ico" Text="▤" FontSize="13" Foreground="{StaticResource T1}" Width="20"/>
              <TextBlock x:Name="Nav1Txt" Text="概览" FontSize="12.5" Foreground="{StaticResource T1}" FontWeight="SemiBold"/>
            </StackPanel>
          </Border>
          <Border x:Name="Nav2" Style="{StaticResource NavItem}" Padding="12,0">
            <StackPanel Orientation="Horizontal" VerticalAlignment="Center">
              <TextBlock x:Name="Nav2Ico" Text="☰" FontSize="13" Foreground="{StaticResource T2}" Width="20"/>
              <TextBlock x:Name="Nav2Txt" Text="实例管理" FontSize="12.5" Foreground="{StaticResource T2}"/>
            </StackPanel>
          </Border>
          <Border x:Name="Nav3" Style="{StaticResource NavItem}" Padding="12,0">
            <StackPanel Orientation="Horizontal" VerticalAlignment="Center">
              <TextBlock x:Name="Nav3Ico" Text="♡" FontSize="13" Foreground="{StaticResource T2}" Width="20"/>
              <TextBlock x:Name="Nav3Txt" Text="健康检查" FontSize="12.5" Foreground="{StaticResource T2}"/>
            </StackPanel>
          </Border>
          <Border x:Name="Nav4" Style="{StaticResource NavItem}" Padding="12,0">
            <StackPanel Orientation="Horizontal" VerticalAlignment="Center">
              <TextBlock x:Name="Nav4Ico" Text="≡" FontSize="13" Foreground="{StaticResource T2}" Width="20"/>
              <TextBlock x:Name="Nav4Txt" Text="事件记录" FontSize="12.5" Foreground="{StaticResource T2}"/>
            </StackPanel>
          </Border>
          <Border x:Name="Nav5" Style="{StaticResource NavItem}" Padding="12,0">
            <StackPanel Orientation="Horizontal" VerticalAlignment="Center">
              <TextBlock x:Name="Nav5Ico" Text="⚙" FontSize="13" Foreground="{StaticResource T2}" Width="20"/>
              <TextBlock x:Name="Nav5Txt" Text="设置" FontSize="12.5" Foreground="{StaticResource T2}"/>
            </StackPanel>
          </Border>
        </StackPanel>
      </Border>

      <Grid Grid.Column="1" Margin="18,14,16,12">
        <Grid.RowDefinitions>
          <RowDefinition Height="Auto"/>
          <RowDefinition Height="*"/>
        </Grid.RowDefinitions>

        <Grid Grid.Row="0" Margin="0,0,0,14">
          <StackPanel>
            <TextBlock x:Name="TxtTitle" Text="概览" FontSize="22" FontWeight="SemiBold" Foreground="{StaticResource T1}"/>
            <TextBlock x:Name="TxtSub" Text="5 个实例 · 1 个运行 · 2 个休眠" FontSize="11.5" Foreground="{StaticResource T3}" Margin="0,4,0,0"/>
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

        <!-- ============ 页1 概览 ============ -->
        <Grid x:Name="Page1" Grid.Row="1">
          <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="*"/>
          </Grid.RowDefinitions>

          <Grid Grid.Row="0" Margin="0,0,0,12">
            <Grid.ColumnDefinitions>
              <ColumnDefinition Width="*"/><ColumnDefinition Width="10"/>
              <ColumnDefinition Width="*"/><ColumnDefinition Width="10"/>
              <ColumnDefinition Width="*"/><ColumnDefinition Width="10"/>
              <ColumnDefinition Width="*"/>
            </Grid.ColumnDefinitions>

            <Border Grid.Column="0" CornerRadius="11" BorderBrush="{StaticResource Line}" BorderThickness="1" Height="86">
              <Border.Background><LinearGradientBrush StartPoint="0,0" EndPoint="1,1"><GradientStop Color="#33333A" Offset="0"/><GradientStop Color="#2A2A2F" Offset="1"/></LinearGradientBrush></Border.Background>
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
            <Border Grid.Column="2" CornerRadius="11" BorderBrush="{StaticResource Line}" BorderThickness="1" Height="86">
              <Border.Background><LinearGradientBrush StartPoint="0,0" EndPoint="1,1"><GradientStop Color="#2E3A34" Offset="0"/><GradientStop Color="#2A2A2F" Offset="1"/></LinearGradientBrush></Border.Background>
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
            <Border Grid.Column="4" CornerRadius="11" BorderBrush="{StaticResource Line}" BorderThickness="1" Height="86">
              <Border.Background><LinearGradientBrush StartPoint="0,0" EndPoint="1,1"><GradientStop Color="#33333A" Offset="0"/><GradientStop Color="#2A2A2F" Offset="1"/></LinearGradientBrush></Border.Background>
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
            <Border Grid.Column="6" CornerRadius="11" BorderBrush="{StaticResource Line}" BorderThickness="1" Height="86">
              <Border.Background><LinearGradientBrush StartPoint="0,0" EndPoint="1,1"><GradientStop Color="#33333A" Offset="0"/><GradientStop Color="#2A2A2F" Offset="1"/></LinearGradientBrush></Border.Background>
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

          <Grid Grid.Row="1">
            <Grid.ColumnDefinitions>
              <ColumnDefinition Width="*"/><ColumnDefinition Width="12"/><ColumnDefinition Width="236"/>
            </Grid.ColumnDefinitions>

            <Grid Grid.Column="0">
              <Grid.RowDefinitions>
                <RowDefinition Height="Auto"/><RowDefinition Height="12"/><RowDefinition Height="*"/>
              </Grid.RowDefinitions>
              <Border Grid.Row="0" Background="{StaticResource Card}" CornerRadius="11" BorderBrush="{StaticResource Line}" BorderThickness="1">
                <StackPanel x:Name="PnlInstances">
                  <Grid Margin="12,10,12,4">
                    <TextBlock Text="实例监控" FontSize="12.5" FontWeight="SemiBold" Foreground="{StaticResource T1}"/>
                    <TextBlock Text="管理 ›" FontSize="10.5" Foreground="{StaticResource T3}" HorizontalAlignment="Right"/>
                  </Grid>
                </StackPanel>
              </Border>
              <Border Grid.Row="2" Background="{StaticResource Card}" CornerRadius="11" BorderBrush="{StaticResource Line}" BorderThickness="1">
                <StackPanel x:Name="PnlEvents">
                  <Grid Margin="12,10,12,4">
                    <TextBlock Text="事件记录" FontSize="12.5" FontWeight="SemiBold" Foreground="{StaticResource T1}"/>
                    <TextBlock Text="查看全部 ›" FontSize="10.5" Foreground="{StaticResource T3}" HorizontalAlignment="Right"/>
                  </Grid>
                </StackPanel>
              </Border>
            </Grid>

            <StackPanel Grid.Column="2">
              <Border Background="{StaticResource Card}" CornerRadius="11" BorderBrush="{StaticResource Line}" BorderThickness="1">
                <StackPanel Margin="12,11,12,12">
                  <TextBlock Text="主机内存" FontSize="11" Foreground="{StaticResource T3}"/>
                  <StackPanel Orientation="Horizontal" Margin="0,3,0,0">
                    <TextBlock Text="5.2" FontSize="24" FontWeight="SemiBold" Foreground="{StaticResource T1}"/>
                    <TextBlock Text="/ 15.7 GB" FontSize="11" Foreground="{StaticResource T3}" VerticalAlignment="Bottom" Margin="4,0,0,4"/>
                  </StackPanel>
                  <Viewbox Height="46" Stretch="Fill" Margin="0,6,0,0">
                    <Canvas Width="240" Height="46" ClipToBounds="True">
                      <Path Stroke="{StaticResource Blue}" StrokeThickness="1.6"
                            Data="M0,34 C18,30 30,20 48,22 C66,24 76,34 96,30 C116,26 126,12 148,14 C170,16 196,10 240,6"/>
                      <Path Opacity="0.28" Data="M0,34 C18,30 30,20 48,22 C66,24 76,34 96,30 C116,26 126,12 148,14 C170,16 196,10 240,6 L240,46 L0,46 Z">
                        <Path.Fill><LinearGradientBrush StartPoint="0,0" EndPoint="0,1"><GradientStop Color="#0A84FF" Offset="0"/><GradientStop Color="#000A84FF" Offset="1"/></LinearGradientBrush></Path.Fill>
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
                  <TextBlock Text="系统健康" FontSize="12.5" FontWeight="SemiBold" Foreground="{StaticResource T1}" Margin="12,14,12,0"/>
                  <Grid Margin="12,10,12,14">
                    <Grid.ColumnDefinitions><ColumnDefinition Width="Auto"/><ColumnDefinition Width="*"/><ColumnDefinition Width="16"/></Grid.ColumnDefinitions>
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
                  <Grid Margin="12,9,12,9"><TextBlock Text="下一次唤醒" FontSize="11" Foreground="{StaticResource T2}"/><TextBlock Text="05:45" FontSize="11" Foreground="{StaticResource T1}" HorizontalAlignment="Right"/></Grid>
                  <Border Height="1" Background="#0DFFFFFF" Margin="12,0,12,0"/>
                  <Grid Margin="12,9,12,9"><TextBlock Text="今日休眠" FontSize="11" Foreground="{StaticResource T2}"/><TextBlock Text="2 次" FontSize="11" Foreground="{StaticResource T1}" HorizontalAlignment="Right"/></Grid>
                </StackPanel>
              </Border>
              <Border Background="{StaticResource Card}" CornerRadius="11" BorderBrush="{StaticResource Line}" BorderThickness="1" Margin="0,12,0,0">
                <StackPanel>
                  <TextBlock Text="今日统计" FontSize="12.5" FontWeight="SemiBold" Foreground="{StaticResource T1}" Margin="12,10,12,4"/>
                  <Grid Margin="12,6,12,0"><TextBlock Text="自动唤醒" FontSize="11" Foreground="{StaticResource T2}"/><TextBlock Text="3 次" FontSize="11" Foreground="{StaticResource T1}" HorizontalAlignment="Right"/></Grid>
                  <Grid Margin="12,8,12,0"><TextBlock Text="内存清理" FontSize="11" Foreground="{StaticResource T2}"/><TextBlock Text="24 次" FontSize="11" Foreground="{StaticResource T1}" HorizontalAlignment="Right"/></Grid>
                  <Grid Margin="12,8,12,10"><TextBlock Text="异常恢复" FontSize="11" Foreground="{StaticResource T2}"/><TextBlock Text="1 次" FontSize="11" Foreground="{StaticResource T1}" HorizontalAlignment="Right"/></Grid>
                </StackPanel>
              </Border>
            </StackPanel>
          </Grid>
        </Grid>

        <!-- ============ 页2 实例管理 ============ -->
        <Grid x:Name="Page2" Grid.Row="1" Visibility="Collapsed">
          <Border Background="{StaticResource Card}" CornerRadius="11" BorderBrush="{StaticResource Line}" BorderThickness="1" VerticalAlignment="Top">
            <StackPanel>
              <Grid Margin="14,10,14,8">
                <StackPanel>
                  <TextBlock Text="全部实例" FontSize="10.5" Foreground="{StaticResource T3}" VerticalAlignment="Center"/>
                </StackPanel>
                
              </Grid>

              <Border Height="1" Background="#0DFFFFFF"/>

              <Grid Margin="14,8,14,6">
                <Grid.ColumnDefinitions>
                  <ColumnDefinition Width="*"/><ColumnDefinition Width="118"/><ColumnDefinition Width="120"/>
                </Grid.ColumnDefinitions>
                <TextBlock Text="实例" FontSize="10" Foreground="{StaticResource T3}"/>
                <TextBlock Grid.Column="1" Text="升级" FontSize="10" Foreground="{StaticResource T3}" HorizontalAlignment="Center"/>
                <TextBlock Grid.Column="2" Text="操作" FontSize="10" Foreground="{StaticResource T3}" HorizontalAlignment="Right"/>
              </Grid>

              <Grid Margin="14,0,14,0" Height="64">
                <Grid.ColumnDefinitions>
                  <ColumnDefinition Width="*"/><ColumnDefinition Width="118"/><ColumnDefinition Width="120"/>
                </Grid.ColumnDefinitions>
                <StackPanel Orientation="Horizontal" VerticalAlignment="Center">
                  <Border Width="26" Height="26" CornerRadius="8" Background="Transparent">
                    <Image x:Name="Mg1" Stretch="UniformToFill"/>
                  </Border>
                  <StackPanel Margin="10,0,0,0" VerticalAlignment="Center">
                    <TextBlock Text="国服 微信" FontSize="12.5" Foreground="{StaticResource T1}"/>
                    <TextBlock Text="运行中 · 紫孔雀 · 剩余 2:38" FontSize="10.5" Foreground="{StaticResource T3}" Margin="0,1,0,0"/>
                  </StackPanel>
                </StackPanel>
                <TextBlock Grid.Column="1" Text="建筑大师训练营 Lv.11" FontSize="10.5" Foreground="{StaticResource T2}" VerticalAlignment="Center" HorizontalAlignment="Center"/>
                <StackPanel Grid.Column="2" Orientation="Horizontal" HorizontalAlignment="Right" VerticalAlignment="Center">
                  <Border Background="#1AFFFFFF" CornerRadius="7" Padding="10,4" Margin="0,0,6,0"><TextBlock Text="检测中" FontSize="10.5" Foreground="{StaticResource T2}"/></Border>
                  <Border Background="#F2F2F5" CornerRadius="7" Padding="10,4"><TextBlock Text="重启" FontSize="10.5" Foreground="#1F1F23" FontWeight="SemiBold"/></Border>
                </StackPanel>
              </Grid>
              <Border Height="1" Background="#0DFFFFFF" Margin="14,0,14,0"/>

              <Grid Margin="14,0,14,0" Height="64">
                <Grid.ColumnDefinitions>
                  <ColumnDefinition Width="*"/><ColumnDefinition Width="118"/><ColumnDefinition Width="120"/>
                </Grid.ColumnDefinitions>
                <StackPanel Orientation="Horizontal" VerticalAlignment="Center">
                  <Border Width="26" Height="26" CornerRadius="8" Background="Transparent"><Image x:Name="Mg2" Stretch="UniformToFill"/></Border>
                  <StackPanel Margin="10,0,0,0" VerticalAlignment="Center">
                    <TextBlock Text="国际服" FontSize="12.5" Foreground="{StaticResource T1}"/>
                    <TextBlock Text="休眠中 · 05:45 自动唤醒" FontSize="10.5" Foreground="{StaticResource T3}" Margin="0,1,0,0"/>
                  </StackPanel>
                </StackPanel>
                <TextBlock Grid.Column="1" Text="部落城堡 Lv.2" FontSize="10.5" Foreground="{StaticResource T2}" VerticalAlignment="Center" HorizontalAlignment="Center"/>
                <StackPanel Grid.Column="2" Orientation="Horizontal" HorizontalAlignment="Right" VerticalAlignment="Center">
                  <Border Background="#1AFFFFFF" CornerRadius="7" Padding="10,4" Margin="0,0,6,0"><TextBlock Text="检测中" FontSize="10.5" Foreground="{StaticResource T2}"/></Border>
                  <Border Background="#F2F2F5" CornerRadius="7" Padding="10,4"><TextBlock Text="唤醒" FontSize="10.5" Foreground="#1F1F23" FontWeight="SemiBold"/></Border>
                </StackPanel>
              </Grid>
              <Border Height="1" Background="#0DFFFFFF" Margin="14,0,14,0"/>

              <Grid Margin="14,0,14,0" Height="64">
                <Grid.ColumnDefinitions>
                  <ColumnDefinition Width="*"/><ColumnDefinition Width="118"/><ColumnDefinition Width="120"/>
                </Grid.ColumnDefinitions>
                <StackPanel Orientation="Horizontal" VerticalAlignment="Center">
                  <Border Width="26" Height="26" CornerRadius="8" Background="Transparent"><Image x:Name="Mg3" Stretch="UniformToFill"/></Border>
                  <StackPanel Margin="10,0,0,0" VerticalAlignment="Center">
                    <TextBlock Text="国服QQ" FontSize="12.5" Foreground="{StaticResource T1}"/>
                    <TextBlock Text="休眠中 · 11:17 自动唤醒" FontSize="10.5" Foreground="{StaticResource T3}" Margin="0,1,0,0"/>
                  </StackPanel>
                </StackPanel>
                <TextBlock Grid.Column="1" Text="箭塔 Lv.13" FontSize="10.5" Foreground="{StaticResource T2}" VerticalAlignment="Center" HorizontalAlignment="Center"/>
                <StackPanel Grid.Column="2" Orientation="Horizontal" HorizontalAlignment="Right" VerticalAlignment="Center">
                  <Border Background="#1AFFFFFF" CornerRadius="7" Padding="10,4" Margin="0,0,6,0"><TextBlock Text="检测中" FontSize="10.5" Foreground="{StaticResource T2}"/></Border>
                  <Border Background="#F2F2F5" CornerRadius="7" Padding="10,4"><TextBlock Text="唤醒" FontSize="10.5" Foreground="#1F1F23" FontWeight="SemiBold"/></Border>
                </StackPanel>
              </Grid>
              <Border Height="1" Background="#0DFFFFFF" Margin="14,0,14,0"/>

              <Grid Margin="14,0,14,0" Height="64">
                <Grid.ColumnDefinitions>
                  <ColumnDefinition Width="*"/><ColumnDefinition Width="118"/><ColumnDefinition Width="120"/>
                </Grid.ColumnDefinitions>
                <StackPanel Orientation="Horizontal" VerticalAlignment="Center">
                  <Border Width="26" Height="26" CornerRadius="8" Background="Transparent"><Image x:Name="Mg4" Stretch="UniformToFill" Opacity="0.45"/></Border>
                  <StackPanel Margin="10,0,0,0" VerticalAlignment="Center">
                    <TextBlock Text="MuMu安卓设备-2" FontSize="12.5" Foreground="{StaticResource T1}"/>
                    <TextBlock Text="已关机" FontSize="10.5" Foreground="{StaticResource T3}" Margin="0,1,0,0"/>
                  </StackPanel>
                </StackPanel>
                <TextBlock Grid.Column="1" Text="—" FontSize="10.5" Foreground="{StaticResource T3}" VerticalAlignment="Center" HorizontalAlignment="Center"/>
                <StackPanel Grid.Column="2" Orientation="Horizontal" HorizontalAlignment="Right" VerticalAlignment="Center">
                  <Border Background="#1AFFFFFF" CornerRadius="7" Padding="10,4" Margin="0,0,6,0"><TextBlock Text="已暂停" FontSize="10.5" Foreground="{StaticResource T3}"/></Border>
                  <Border Background="#1AFFFFFF" CornerRadius="7" Padding="10,4"><TextBlock Text="启动" FontSize="10.5" Foreground="{StaticResource T1}"/></Border>
                </StackPanel>
              </Grid>
              <Border Height="1" Background="#0DFFFFFF" Margin="14,0,14,0"/>

              <Grid Margin="14,0,14,12" Height="64">
                <Grid.ColumnDefinitions>
                  <ColumnDefinition Width="*"/><ColumnDefinition Width="118"/><ColumnDefinition Width="120"/>
                </Grid.ColumnDefinitions>
                <StackPanel Orientation="Horizontal" VerticalAlignment="Center">
                  <Border Width="26" Height="26" CornerRadius="8" Background="Transparent"><Image x:Name="Mg5" Stretch="UniformToFill" Opacity="0.45"/></Border>
                  <StackPanel Margin="10,0,0,0" VerticalAlignment="Center">
                    <TextBlock Text="MuMu安卓设备-4" FontSize="12.5" Foreground="{StaticResource T1}"/>
                    <TextBlock Text="已关机" FontSize="10.5" Foreground="{StaticResource T3}" Margin="0,1,0,0"/>
                  </StackPanel>
                </StackPanel>
                <TextBlock Grid.Column="1" Text="—" FontSize="10.5" Foreground="{StaticResource T3}" VerticalAlignment="Center" HorizontalAlignment="Center"/>
                <StackPanel Grid.Column="2" Orientation="Horizontal" HorizontalAlignment="Right" VerticalAlignment="Center">
                  <Border Background="#1AFFFFFF" CornerRadius="7" Padding="10,4" Margin="0,0,6,0"><TextBlock Text="已暂停" FontSize="10.5" Foreground="{StaticResource T3}"/></Border>
                  <Border Background="#1AFFFFFF" CornerRadius="7" Padding="10,4"><TextBlock Text="启动" FontSize="10.5" Foreground="{StaticResource T1}"/></Border>
                </StackPanel>
              </Grid>
            </StackPanel>
          </Border>
        </Grid>

        <!-- ============ 页3 健康检查 ============ -->
        <Grid x:Name="Page3" Grid.Row="1" Visibility="Collapsed">
          <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/><RowDefinition Height="12"/><RowDefinition Height="*"/>
          </Grid.RowDefinitions>

          <Border Grid.Row="0" Background="{StaticResource Card}" CornerRadius="11" BorderBrush="{StaticResource Line}" BorderThickness="1">
            <Grid Margin="14,12,14,12">
              <StackPanel>
                <TextBlock Text="内存" FontSize="11" Foreground="{StaticResource T3}"/>
                <StackPanel Orientation="Horizontal" Margin="0,4,0,0">
                  <TextBlock Text="5.2" FontSize="26" FontWeight="SemiBold" Foreground="{StaticResource T1}"/>
                  <TextBlock Text="/ 15.7 GB" FontSize="11" Foreground="{StaticResource T3}" VerticalAlignment="Bottom" Margin="5,0,0,5"/>
                </StackPanel>
                <Border Height="6" CornerRadius="3" Background="#24FFFFFF" Margin="0,10,0,0" Width="320" HorizontalAlignment="Left">
                  <Border Width="106" Height="6" CornerRadius="3" Background="{StaticResource Blue}" HorizontalAlignment="Left"/>
                </Border>
              </StackPanel>
              <StackPanel HorizontalAlignment="Right" VerticalAlignment="Center">
                <Grid Margin="0,0,0,8"><TextBlock Text="提交内存" FontSize="11" Foreground="{StaticResource T2}"/><TextBlock Text="21.5 GB" FontSize="11" Foreground="{StaticResource T1}" HorizontalAlignment="Right" Margin="60,0,0,0"/></Grid>
                <Grid Margin="0,0,0,8"><TextBlock Text="物理可用" FontSize="11" Foreground="{StaticResource T2}"/><TextBlock Text="10.5 GB" FontSize="11" Foreground="{StaticResource T1}" HorizontalAlignment="Right" Margin="60,0,0,0"/></Grid>
                <Grid><TextBlock Text="页面文件" FontSize="11" Foreground="{StaticResource T2}"/><TextBlock Text="正常" FontSize="11" Foreground="{StaticResource Green}" HorizontalAlignment="Right" Margin="60,0,0,0"/></Grid>
              </StackPanel>
            </Grid>
          </Border>

          <Grid Grid.Row="2">
            <Grid.ColumnDefinitions>
              <ColumnDefinition Width="*"/><ColumnDefinition Width="12"/><ColumnDefinition Width="*"/>
            </Grid.ColumnDefinitions>
            <Grid.RowDefinitions>
              <RowDefinition Height="*"/><RowDefinition Height="12"/><RowDefinition Height="*"/><RowDefinition Height="12"/><RowDefinition Height="*"/>
            </Grid.RowDefinitions>

            <Border Grid.Row="0" Grid.Column="0" Background="{StaticResource Card}" CornerRadius="11" BorderBrush="{StaticResource Line}" BorderThickness="1">
              <Grid Margin="14,12,14,12">
                <StackPanel VerticalAlignment="Center">
                  <TextBlock Text="内存压缩" FontSize="12.5" Foreground="{StaticResource T1}"/>
                  <TextBlock Text="系统内存压缩服务已启用" FontSize="10.5" Foreground="{StaticResource T3}" Margin="0,3,0,0"/>
                </StackPanel>
                <Border HorizontalAlignment="Right" VerticalAlignment="Center" Background="#2934C759" CornerRadius="20" Padding="9,3">
                  <TextBlock Text="正常" FontSize="10" Foreground="{StaticResource Green}"/>
                </Border>
              </Grid>
            </Border>
            <Border Grid.Row="0" Grid.Column="2" Background="{StaticResource Card}" CornerRadius="11" BorderBrush="{StaticResource Line}" BorderThickness="1">
              <Grid Margin="14,12,14,12">
                <StackPanel VerticalAlignment="Center">
                  <TextBlock Text="SysMain" FontSize="12.5" Foreground="{StaticResource T1}"/>
                  <TextBlock Text="超级预读取服务运行中" FontSize="10.5" Foreground="{StaticResource T3}" Margin="0,3,0,0"/>
                </StackPanel>
                <Border HorizontalAlignment="Right" VerticalAlignment="Center" Background="#2934C759" CornerRadius="20" Padding="9,3">
                  <TextBlock Text="正常" FontSize="10" Foreground="{StaticResource Green}"/>
                </Border>
              </Grid>
            </Border>
            <Border Grid.Row="2" Grid.Column="0" Background="{StaticResource Card}" CornerRadius="11" BorderBrush="{StaticResource Line}" BorderThickness="1">
              <Grid Margin="14,12,14,12">
                <StackPanel VerticalAlignment="Center">
                  <TextBlock Text="Mem Reduct" FontSize="12.5" Foreground="{StaticResource T1}"/>
                  <TextBlock Text="第三方清理工具已安装" FontSize="10.5" Foreground="{StaticResource T3}" Margin="0,3,0,0"/>
                </StackPanel>
                <Border HorizontalAlignment="Right" VerticalAlignment="Center" Background="#2934C759" CornerRadius="20" Padding="9,3">
                  <TextBlock Text="正常" FontSize="10" Foreground="{StaticResource Green}"/>
                </Border>
              </Grid>
            </Border>
            <Border Grid.Row="2" Grid.Column="2" Background="{StaticResource Card}" CornerRadius="11" BorderBrush="{StaticResource Line}" BorderThickness="1">
              <Grid Margin="14,12,14,12">
                <StackPanel VerticalAlignment="Center">
                  <TextBlock Text="CEF 泄漏" FontSize="12.5" Foreground="{StaticResource T1}"/>
                  <TextBlock Text="24 小时内回收 24 次，累计 0 个孤儿进程" FontSize="10.5" Foreground="{StaticResource T3}" Margin="0,3,0,0"/>
                </StackPanel>
                <Border HorizontalAlignment="Right" VerticalAlignment="Center" Background="#29FF9F0A" CornerRadius="20" Padding="9,3">
                  <TextBlock Text="关注" FontSize="10" Foreground="{StaticResource Amber}"/>
                </Border>
              </Grid>
            </Border>
            <Border Grid.Row="4" Grid.Column="0" Grid.ColumnSpan="3" Background="{StaticResource Card}" CornerRadius="11" BorderBrush="{StaticResource Line}" BorderThickness="1">
              <Grid Margin="14,12,14,12">
                <StackPanel VerticalAlignment="Center">
                  <TextBlock Text="权限" FontSize="12.5" Foreground="{StaticResource T1}"/>
                  <TextBlock Text="MuMu 以管理员运行，面板不是，重启与休眠会失败" FontSize="10.5" Foreground="{StaticResource T3}" Margin="0,3,0,0"/>
                </StackPanel>
                <Border HorizontalAlignment="Right" VerticalAlignment="Center" Background="#29FF453A" CornerRadius="20" Padding="9,3">
                  <TextBlock Text="需管理员" FontSize="10" Foreground="{StaticResource Red}"/>
                </Border>
              </Grid>
            </Border>
          </Grid>
        </Grid>

        <!-- ============ 页4 事件记录 ============ -->
        <Grid x:Name="Page4" Grid.Row="1" Visibility="Collapsed">
          <Border Background="{StaticResource Card}" CornerRadius="11" BorderBrush="{StaticResource Line}" BorderThickness="1">
            <Grid>
              <Grid.RowDefinitions>
                <RowDefinition Height="Auto"/><RowDefinition Height="*"/>
              </Grid.RowDefinitions>
              <Grid Margin="14,12,14,10">
                <StackPanel VerticalAlignment="Center">
                  <TextBlock Text="共 128 条 · 今日 42 条" FontSize="10.5" Foreground="{StaticResource T3}"/>
                </StackPanel>
                <StackPanel Orientation="Horizontal" HorizontalAlignment="Right" VerticalAlignment="Center">
                  <Border Background="#24FFFFFF" CornerRadius="7" Padding="10,4" Margin="0,0,6,0"><TextBlock Text="全部" FontSize="10.5" Foreground="{StaticResource T1}"/></Border>
                  <Border Background="#1AFFFFFF" CornerRadius="7" Padding="10,4" Margin="0,0,6,0"><TextBlock Text="告警" FontSize="10.5" Foreground="{StaticResource T2}"/></Border>
                  <Border Background="#1AFFFFFF" CornerRadius="7" Padding="10,4"><TextBlock Text="休眠" FontSize="10.5" Foreground="{StaticResource T2}"/></Border>
                </StackPanel>
              </Grid>
              <ScrollViewer Grid.Row="1" VerticalScrollBarVisibility="Auto" Margin="14,0,10,10">
                <StackPanel>
                  <Grid Height="30"><Grid.ColumnDefinitions><ColumnDefinition Width="52"/><ColumnDefinition Width="18"/><ColumnDefinition Width="*"/><ColumnDefinition Width="110"/></Grid.ColumnDefinitions>
                    <TextBlock Text="22:52" FontSize="10.5" Foreground="{StaticResource T3}" VerticalAlignment="Center"/>
                    <Ellipse Grid.Column="1" Width="5" Height="5" Fill="{StaticResource Green}" VerticalAlignment="Center" HorizontalAlignment="Left"/>
                    <TextBlock Grid.Column="2" Text="内存检查通过，可用 2.9 GB" FontSize="11" Foreground="{StaticResource T2}" VerticalAlignment="Center"/>
                    <TextBlock Grid.Column="3" Text="全局" FontSize="10" Foreground="{StaticResource T3}" VerticalAlignment="Center" HorizontalAlignment="Right"/>
                  </Grid>
                  <Border Height="1" Background="#0DFFFFFF"/>
                  <Grid Height="30"><Grid.ColumnDefinitions><ColumnDefinition Width="52"/><ColumnDefinition Width="18"/><ColumnDefinition Width="*"/><ColumnDefinition Width="110"/></Grid.ColumnDefinitions>
                    <TextBlock Text="22:50" FontSize="10.5" Foreground="{StaticResource T3}" VerticalAlignment="Center"/>
                    <Ellipse Grid.Column="1" Width="5" Height="5" Fill="#5A5A64" VerticalAlignment="Center" HorizontalAlignment="Left"/>
                    <TextBlock Grid.Column="2" Text="清理 CEF 回收 0 个（今日 24 次）" FontSize="11" Foreground="{StaticResource T2}" VerticalAlignment="Center"/>
                    <TextBlock Grid.Column="3" Text="全局" FontSize="10" Foreground="{StaticResource T3}" VerticalAlignment="Center" HorizontalAlignment="Right"/>
                  </Grid>
                  <Border Height="1" Background="#0DFFFFFF"/>
                  <Grid Height="30"><Grid.ColumnDefinitions><ColumnDefinition Width="52"/><ColumnDefinition Width="18"/><ColumnDefinition Width="*"/><ColumnDefinition Width="110"/></Grid.ColumnDefinitions>
                    <TextBlock Text="22:41" FontSize="10.5" Foreground="{StaticResource T3}" VerticalAlignment="Center"/>
                    <Ellipse Grid.Column="1" Width="5" Height="5" Fill="#5A5A64" VerticalAlignment="Center" HorizontalAlignment="Left"/>
                    <TextBlock Grid.Column="2" Text="实例 5 采集正常，adb 通道 mumu" FontSize="11" Foreground="{StaticResource T2}" VerticalAlignment="Center"/>
                    <TextBlock Grid.Column="3" Text="国服 微信" FontSize="10" Foreground="{StaticResource T3}" VerticalAlignment="Center" HorizontalAlignment="Right"/>
                  </Grid>
                  <Border Height="1" Background="#0DFFFFFF"/>
                  <Grid Height="30"><Grid.ColumnDefinitions><ColumnDefinition Width="52"/><ColumnDefinition Width="18"/><ColumnDefinition Width="*"/><ColumnDefinition Width="110"/></Grid.ColumnDefinitions>
                    <TextBlock Text="22:21" FontSize="10.5" Foreground="{StaticResource T3}" VerticalAlignment="Center"/>
                    <Ellipse Grid.Column="1" Width="5" Height="5" Fill="{StaticResource Amber}" VerticalAlignment="Center" HorizontalAlignment="Left"/>
                    <TextBlock Grid.Column="2" Text="实例 3 关机休眠，11:17 唤醒（箭塔 Lv.13）" FontSize="11" Foreground="{StaticResource T2}" VerticalAlignment="Center"/>
                    <TextBlock Grid.Column="3" Text="国服QQ" FontSize="10" Foreground="{StaticResource T3}" VerticalAlignment="Center" HorizontalAlignment="Right"/>
                  </Grid>
                  <Border Height="1" Background="#0DFFFFFF"/>
                  <Grid Height="30"><Grid.ColumnDefinitions><ColumnDefinition Width="52"/><ColumnDefinition Width="18"/><ColumnDefinition Width="*"/><ColumnDefinition Width="110"/></Grid.ColumnDefinitions>
                    <TextBlock Text="22:20" FontSize="10.5" Foreground="{StaticResource T3}" VerticalAlignment="Center"/>
                    <Ellipse Grid.Column="1" Width="5" Height="5" Fill="#5A5A64" VerticalAlignment="Center" HorizontalAlignment="Left"/>
                    <TextBlock Grid.Column="2" Text="实例 5 升级 建筑大师训练营 Lv.11，剩 2h38m" FontSize="11" Foreground="{StaticResource T2}" VerticalAlignment="Center"/>
                    <TextBlock Grid.Column="3" Text="国服 微信" FontSize="10" Foreground="{StaticResource T3}" VerticalAlignment="Center" HorizontalAlignment="Right"/>
                  </Grid>
                  <Border Height="1" Background="#0DFFFFFF"/>
                  <Grid Height="30"><Grid.ColumnDefinitions><ColumnDefinition Width="52"/><ColumnDefinition Width="18"/><ColumnDefinition Width="*"/><ColumnDefinition Width="110"/></Grid.ColumnDefinitions>
                    <TextBlock Text="22:10" FontSize="10.5" Foreground="{StaticResource T3}" VerticalAlignment="Center"/>
                    <Ellipse Grid.Column="1" Width="5" Height="5" Fill="{StaticResource Red}" VerticalAlignment="Center" HorizontalAlignment="Left"/>
                    <TextBlock Grid.Column="2" Text="实例 3 未运行，连续 1/2" FontSize="11" Foreground="#FF8078" VerticalAlignment="Center"/>
                    <TextBlock Grid.Column="3" Text="国服QQ" FontSize="10" Foreground="{StaticResource T3}" VerticalAlignment="Center" HorizontalAlignment="Right"/>
                  </Grid>
                  <Border Height="1" Background="#0DFFFFFF"/>
                  <Grid Height="30"><Grid.ColumnDefinitions><ColumnDefinition Width="52"/><ColumnDefinition Width="18"/><ColumnDefinition Width="*"/><ColumnDefinition Width="110"/></Grid.ColumnDefinitions>
                    <TextBlock Text="22:09" FontSize="10.5" Foreground="{StaticResource T3}" VerticalAlignment="Center"/>
                    <Ellipse Grid.Column="1" Width="5" Height="5" Fill="#5A5A64" VerticalAlignment="Center" HorizontalAlignment="Left"/>
                    <TextBlock Grid.Column="2" Text="实例 3 自动重启实例" FontSize="11" Foreground="{StaticResource T2}" VerticalAlignment="Center"/>
                    <TextBlock Grid.Column="3" Text="国服QQ" FontSize="10" Foreground="{StaticResource T3}" VerticalAlignment="Center" HorizontalAlignment="Right"/>
                  </Grid>
                  <Border Height="1" Background="#0DFFFFFF"/>
                  <Grid Height="30"><Grid.ColumnDefinitions><ColumnDefinition Width="52"/><ColumnDefinition Width="18"/><ColumnDefinition Width="*"/><ColumnDefinition Width="110"/></Grid.ColumnDefinitions>
                    <TextBlock Text="21:55" FontSize="10.5" Foreground="{StaticResource T3}" VerticalAlignment="Center"/>
                    <Ellipse Grid.Column="1" Width="5" Height="5" Fill="#5A5A64" VerticalAlignment="Center" HorizontalAlignment="Left"/>
                    <TextBlock Grid.Column="2" Text="看护启动" FontSize="11" Foreground="{StaticResource T2}" VerticalAlignment="Center"/>
                    <TextBlock Grid.Column="3" Text="全局" FontSize="10" Foreground="{StaticResource T3}" VerticalAlignment="Center" HorizontalAlignment="Right"/>
                  </Grid>
                </StackPanel>
              </ScrollViewer>
            </Grid>
          </Border>
        </Grid>

        <!-- ============ 页5 设置 ============ -->
        <Grid x:Name="Page5" Grid.Row="1" Visibility="Collapsed">
          <ScrollViewer VerticalScrollBarVisibility="Auto">
            <StackPanel>
              <TextBlock Text="休眠" FontSize="10.5" Foreground="{StaticResource T3}" Margin="4,0,0,6"/>
              <Border Background="{StaticResource Card}" CornerRadius="11" BorderBrush="{StaticResource Line}" BorderThickness="1">
                <StackPanel>
                  <Grid Margin="14,0,14,0" Height="44"><TextBlock Text="自动休眠" FontSize="12" Foreground="{StaticResource T1}" VerticalAlignment="Center"/>
                    <Border HorizontalAlignment="Right" VerticalAlignment="Center" Width="38" Height="22" CornerRadius="11" Background="{StaticResource Green}">
                      <Ellipse Width="18" Height="18" Fill="#FFFFFF" HorizontalAlignment="Right" Margin="0,0,2,0"/>
                    </Border></Grid>
                  <Border Height="1" Background="#0DFFFFFF" Margin="14,0,14,0"/>
                  <Grid Margin="14,0,14,0" Height="44"><TextBlock Text="游戏切到后台时也休眠" FontSize="12" Foreground="{StaticResource T1}" VerticalAlignment="Center"/>
                    <Border HorizontalAlignment="Right" VerticalAlignment="Center" Width="38" Height="22" CornerRadius="11" Background="{StaticResource Green}">
                      <Ellipse Width="18" Height="18" Fill="#FFFFFF" HorizontalAlignment="Right" Margin="0,0,2,0"/>
                    </Border></Grid>
                  <Border Height="1" Background="#0DFFFFFF" Margin="14,0,14,0"/>
                  <Grid Margin="14,0,14,0" Height="44"><TextBlock Text="后台空闲判定" FontSize="12" Foreground="{StaticResource T1}" VerticalAlignment="Center"/>
                    <TextBlock Text="10 分钟" FontSize="12" Foreground="{StaticResource T3}" HorizontalAlignment="Right" VerticalAlignment="Center"/></Grid>
                  <Border Height="1" Background="#0DFFFFFF" Margin="14,0,14,0"/>
                  <Grid Margin="14,0,14,0" Height="44"><TextBlock Text="提前唤醒" FontSize="12" Foreground="{StaticResource T1}" VerticalAlignment="Center"/>
                    <TextBlock Text="10 分钟" FontSize="12" Foreground="{StaticResource T3}" HorizontalAlignment="Right" VerticalAlignment="Center"/></Grid>
                  <Border Height="1" Background="#0DFFFFFF" Margin="14,0,14,0"/>
                  <Grid Margin="14,0,14,0" Height="44"><TextBlock Text="最长休眠" FontSize="12" Foreground="{StaticResource T1}" VerticalAlignment="Center"/>
                    <TextBlock Text="168 小时" FontSize="12" Foreground="{StaticResource T3}" HorizontalAlignment="Right" VerticalAlignment="Center"/></Grid>
                  <Border Height="1" Background="#0DFFFFFF" Margin="14,0,14,0"/>
                  <Grid Margin="14,0,14,0" Height="44"><TextBlock Text="最短休眠" FontSize="12" Foreground="{StaticResource T1}" VerticalAlignment="Center"/>
                    <TextBlock Text="1 小时" FontSize="12" Foreground="{StaticResource T3}" HorizontalAlignment="Right" VerticalAlignment="Center"/></Grid>
                </StackPanel>
              </Border>

              <TextBlock Text="守护" FontSize="10.5" Foreground="{StaticResource T3}" Margin="4,16,0,6"/>
              <Border Background="{StaticResource Card}" CornerRadius="11" BorderBrush="{StaticResource Line}" BorderThickness="1">
                <StackPanel>
                  <Grid Margin="14,0,14,0" Height="44"><TextBlock Text="掉线自动恢复" FontSize="12" Foreground="{StaticResource T1}" VerticalAlignment="Center"/>
                    <Border HorizontalAlignment="Right" VerticalAlignment="Center" Width="38" Height="22" CornerRadius="11" Background="{StaticResource Green}">
                      <Ellipse Width="18" Height="18" Fill="#FFFFFF" HorizontalAlignment="Right" Margin="0,0,2,0"/>
                    </Border></Grid>
                  <Border Height="1" Background="#0DFFFFFF" Margin="14,0,14,0"/>
                  <Grid Margin="14,0,14,0" Height="44"><TextBlock Text="检测间隔" FontSize="12" Foreground="{StaticResource T1}" VerticalAlignment="Center"/>
                    <TextBlock Text="30 秒" FontSize="12" Foreground="{StaticResource T3}" HorizontalAlignment="Right" VerticalAlignment="Center"/></Grid>
                  <Border Height="1" Background="#0DFFFFFF" Margin="14,0,14,0"/>
                  <Grid Margin="14,0,14,0" Height="44"><TextBlock Text="连续几次判定掉线" FontSize="12" Foreground="{StaticResource T1}" VerticalAlignment="Center"/>
                    <TextBlock Text="2 次" FontSize="12" Foreground="{StaticResource T3}" HorizontalAlignment="Right" VerticalAlignment="Center"/></Grid>
                </StackPanel>
              </Border>

              <TextBlock Text="告警与日志" FontSize="10.5" Foreground="{StaticResource T3}" Margin="4,16,0,6"/>
              <Border Background="{StaticResource Card}" CornerRadius="11" BorderBrush="{StaticResource Line}" BorderThickness="1">
                <StackPanel>
                  <Grid Margin="14,0,14,0" Height="44"><TextBlock Text="CEF 告警阈值" FontSize="12" Foreground="{StaticResource T1}" VerticalAlignment="Center"/>
                    <TextBlock Text="600 MB" FontSize="12" Foreground="{StaticResource T3}" HorizontalAlignment="Right" VerticalAlignment="Center"/></Grid>
                  <Border Height="1" Background="#0DFFFFFF" Margin="14,0,14,0"/>
                  <Grid Margin="14,0,14,0" Height="44"><TextBlock Text="日志保留" FontSize="12" Foreground="{StaticResource T1}" VerticalAlignment="Center"/>
                    <TextBlock Text="14 天" FontSize="12" Foreground="{StaticResource T3}" HorizontalAlignment="Right" VerticalAlignment="Center"/></Grid>
                  <Border Height="1" Background="#0DFFFFFF" Margin="14,0,14,0"/>
                  <Grid Margin="14,0,14,0" Height="44"><TextBlock Text="不检测的实例" FontSize="12" Foreground="{StaticResource T1}" VerticalAlignment="Center"/>
                    <TextBlock Text="无" FontSize="12" Foreground="{StaticResource T3}" HorizontalAlignment="Right" VerticalAlignment="Center"/></Grid>
                </StackPanel>
              </Border>

              <TextBlock Text="路径与版本" FontSize="10.5" Foreground="{StaticResource T3}" Margin="4,16,0,6"/>
              <Border Background="{StaticResource Card}" CornerRadius="11" BorderBrush="{StaticResource Line}" BorderThickness="1" Margin="0,0,0,10">
                <StackPanel>
                  <Grid Margin="14,0,14,0" Height="44"><TextBlock Text="MuMu 安装目录" FontSize="12" Foreground="{StaticResource T1}" VerticalAlignment="Center"/>
                    <TextBlock Text="D:\Program Files\Netease\MuMu" FontSize="11" Foreground="{StaticResource T3}" HorizontalAlignment="Right" VerticalAlignment="Center"/></Grid>
                  <Border Height="1" Background="#0DFFFFFF" Margin="14,0,14,0"/>
                  <Grid Margin="14,0,14,0" Height="44"><TextBlock Text="当前版本" FontSize="12" Foreground="{StaticResource T1}" VerticalAlignment="Center"/>
                    <TextBlock Text="1.6.3" FontSize="12" Foreground="{StaticResource T3}" HorizontalAlignment="Right" VerticalAlignment="Center"/></Grid>
                </StackPanel>
              </Border>
            </StackPanel>
          </ScrollViewer>
        </Grid>
      </Grid>
    </Grid>
  </Border>
</Window>
'@

$win = [Windows.Markup.XamlReader]::Parse($xaml)

function Load-Ico([string]$path){
  $ico = New-Object System.Drawing.Icon($path)
  return [System.Windows.Interop.Imaging]::CreateBitmapSourceFromHIcon(
    $ico.Handle, [System.Windows.Int32Rect]::Empty,
    [System.Windows.Media.Imaging.BitmapSizeOptions]::FromEmptyOptions())
}

$logo = Load-Ico 'C:\Users\MOOM\Documents\MuMuGuard\MuMuGuard.ico'
$mumu = Load-Ico 'D:\Program Files\Netease\MuMu\nx_device\15.0\shell\MuMuPlayer.ico'
$win.FindName('LogoImg').Source = $logo
foreach($n in @('Mg1','Mg2','Mg3','Mg4','Mg5')){
  $c = $win.FindName($n); if($c){ $c.Source = $mumu }
}

# 拖动
$win.FindName('Root').Add_MouseLeftButtonDown({ $win.DragMove() })
$win.FindName('BtnMin').Add_MouseLeftButtonUp({ $win.WindowState = 'Minimized' })
$win.FindName('BtnHide').Add_MouseLeftButtonUp({ $win.Close() })

# 分页
$script:pages = @('Page1','Page2','Page3','Page4','Page5')
$script:navs  = @('Nav1','Nav2','Nav3','Nav4','Nav5')
$script:titles= @(@('概览','5 个实例 · 1 个运行 · 2 个休眠'),
                  @('实例管理','对每个实例单独启动、唤醒、重启或暂停检测'),
                  @('健康检查','系统层面的内存、服务与权限状态'),
                  @('事件记录','最近的守护动作与异常'),
                  @('设置','阈值、路径与休眠规则'))

function Switch-Page([int]$n){
  for($i=0; $i -lt 5; $i++){
    $pg = $win.FindName($script:pages[$i])
    $nv = $win.FindName($script:navs[$i])
    $ico = $win.FindName("Nav$($i+1)Ico")
    $txt = $win.FindName("Nav$($i+1)Txt")
    if($i -eq ($n-1)){
      if($pg){ $pg.Visibility = 'Visible' }
      if($nv){ $nv.Background = New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.ColorConverter]::ConvertFromString('#24FFFFFF')) }
      if($ico){ $ico.Foreground = New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.ColorConverter]::ConvertFromString('#F2F2F5')) }
      if($txt){ $txt.Foreground = New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.ColorConverter]::ConvertFromString('#F2F2F5')); $txt.FontWeight = 'SemiBold' }
    } else {
      if($pg){ $pg.Visibility = 'Collapsed' }
      if($nv){ $nv.Background = [System.Windows.Media.Brushes]::Transparent }
      if($ico){ $ico.Foreground = New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.ColorConverter]::ConvertFromString('#9E9EA6')) }
      if($txt){ $txt.Foreground = New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.ColorConverter]::ConvertFromString('#9E9EA6')); $txt.FontWeight = 'Normal' }
    }
  }
  $win.FindName('TxtTitle').Text = $script:titles[$n-1][0]
  $win.FindName('TxtSub').Text   = $script:titles[$n-1][1]
}

# 点击导航
1..5 | ForEach-Object {
  $idx = $_
  $nav = $win.FindName("Nav$idx")
  if($nav){ $nav.Add_MouseLeftButtonUp({ Switch-Page $idx }.GetNewClosure()) }
}

$startPage = 1; if($args.Count -ge 1){ try { $startPage = [int]$args[0] } catch { } }; Switch-Page $startPage
$win.ShowDialog() | Out-Null
