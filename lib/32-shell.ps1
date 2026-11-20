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
        ResizeMode="CanMinimize" FontFamily="Microsoft YaHei UI" UseLayoutRounding="True" SnapsToDevicePixels="True" TextOptions.TextFormattingMode="Display">
  <Window.Resources>











    <Style x:Key="NavItem" TargetType="Border">
      <Setter Property="Height" Value="36"/>
      <Setter Property="CornerRadius" Value="8"/>
      <Setter Property="Margin" Value="0,1,0,1"/>
      <Setter Property="Background" Value="Transparent"/>
    </Style>
  </Window.Resources>

  <Border x:Name="Root" CornerRadius="14" Background="{DynamicResource T_UI_BG}" BorderBrush="#1AFFFFFF" BorderThickness="1">
    <Grid>
      <Grid.ColumnDefinitions>
        <ColumnDefinition Width="168"/>
        <ColumnDefinition Width="*"/>
      </Grid.ColumnDefinitions>

      <!-- 侧栏 -->
      <Border Grid.Column="0" Background="{DynamicResource T_UI_SIDE}" CornerRadius="14,0,0,14">
        <StackPanel Margin="14,26,14,14">
          <StackPanel Margin="0,0,0,24">
            <Border Width="56" Height="56" CornerRadius="15" HorizontalAlignment="Center">
              
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
            <TextBlock Text="MuMuGuard" Foreground="{DynamicResource T_UI_T1}" FontSize="15" FontWeight="SemiBold"
                       HorizontalAlignment="Center" Margin="0,9,0,0"/>
            <TextBlock x:Name="TxtVersion" Text="v2.3.0" Foreground="{DynamicResource T_UI_T3}" FontSize="10.5"
                       HorizontalAlignment="Center" Margin="0,2,0,0"/>
          </StackPanel>

          <Border x:Name="Nav1" Style="{StaticResource NavItem}" Background="#24FFFFFF" Padding="12,0">
            <StackPanel Orientation="Horizontal" VerticalAlignment="Center">
              <TextBlock x:Name="Nav1Ico" Text="▤" FontSize="13" Foreground="{DynamicResource T_UI_T1}" Width="20"/>
              <TextBlock x:Name="Nav1Txt" Text="概览" FontSize="12.5" Foreground="{DynamicResource T_UI_T1}" FontWeight="SemiBold"/>
            </StackPanel>
          </Border>
          <Border x:Name="Nav2" Style="{StaticResource NavItem}" Padding="12,0" Background="Transparent">
            <StackPanel Orientation="Horizontal" VerticalAlignment="Center">
              <TextBlock x:Name="Nav2Ico" Text="☰" FontSize="13" Foreground="{DynamicResource T_UI_T2}" Width="20"/>
              <TextBlock x:Name="Nav2Txt" Text="实例管理" FontSize="12.5" Foreground="{DynamicResource T_UI_T2}"/>
            </StackPanel>
          </Border>
          <Border x:Name="Nav3" Style="{StaticResource NavItem}" Padding="12,0" Background="Transparent">
            <StackPanel Orientation="Horizontal" VerticalAlignment="Center">
              <TextBlock x:Name="Nav3Ico" Text="♡" FontSize="13" Foreground="{DynamicResource T_UI_T2}" Width="20"/>
              <TextBlock x:Name="Nav3Txt" Text="健康检查" FontSize="12.5" Foreground="{DynamicResource T_UI_T2}"/>
            </StackPanel>
          </Border>
          <Border x:Name="Nav4" Style="{StaticResource NavItem}" Padding="12,0" Background="Transparent">
            <StackPanel Orientation="Horizontal" VerticalAlignment="Center">
              <TextBlock x:Name="Nav4Ico" Text="≡" FontSize="13" Foreground="{DynamicResource T_UI_T2}" Width="20"/>
              <TextBlock x:Name="Nav4Txt" Text="事件记录" FontSize="12.5" Foreground="{DynamicResource T_UI_T2}"/>
            </StackPanel>
          </Border>
          <Border x:Name="Nav5" Style="{StaticResource NavItem}" Padding="12,0" Background="Transparent">
            <StackPanel Orientation="Horizontal" VerticalAlignment="Center">
              <TextBlock x:Name="Nav5Ico" Text="⚙" FontSize="13" Foreground="{DynamicResource T_UI_T2}" Width="20"/>
              <TextBlock x:Name="Nav5Txt" Text="设置" FontSize="12.5" Foreground="{DynamicResource T_UI_T2}"/>
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
            <TextBlock x:Name="TxtTitle" Text="概览" FontSize="22" FontWeight="SemiBold" Foreground="{DynamicResource T_UI_T1}"/>
            <TextBlock x:Name="TxtSub" Text="" FontSize="11.5" Foreground="{DynamicResource T_UI_T3}" Margin="0,4,0,0"/>
          </StackPanel>
          <StackPanel Orientation="Horizontal" HorizontalAlignment="Right" VerticalAlignment="Top">
            <Border x:Name="BtnRefresh" Width="30" Height="30" CornerRadius="9" Background="#14FFFFFF" Margin="0,0,8,0">
              <TextBlock Text="↻" FontSize="14" Foreground="{DynamicResource T_UI_T2}" HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
            <Border x:Name="BtnCompact" Width="30" Height="30" CornerRadius="9" Background="#14FFFFFF" Margin="0,0,8,0">
              <TextBlock Text="▣" FontSize="12" Foreground="{DynamicResource T_UI_T2}" HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
            <Border x:Name="BtnMin" Width="30" Height="30" CornerRadius="9" Background="#14FFFFFF" Margin="0,0,8,0">
              <TextBlock Text="—" FontSize="12" Foreground="{DynamicResource T_UI_T2}" HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
            <Border x:Name="BtnHide" Width="30" Height="30" CornerRadius="9" Background="#14FFFFFF">
              <TextBlock Text="✕" FontSize="12" Foreground="{DynamicResource T_UI_T2}" HorizontalAlignment="Center" VerticalAlignment="Center"/>
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

            <Border Grid.Column="0" CornerRadius="11" BorderBrush="{DynamicResource T_UI_LINE}" BorderThickness="1" Height="94" Background="{DynamicResource T_UI_CARD}">
              
              <Grid Margin="12,11,12,12">
                <Border Width="22" Height="22" CornerRadius="7" Background="{DynamicResource T_UI_CHIP}" VerticalAlignment="Top" HorizontalAlignment="Left">
                  <TextBlock Text="▤" FontSize="11" Foreground="{DynamicResource T_UI_ICON}" HorizontalAlignment="Center" VerticalAlignment="Center"/>
                </Border>
                <StackPanel VerticalAlignment="Bottom">
                  <TextBlock Text="实例总数" FontSize="10.5" Foreground="{DynamicResource T_UI_T3}"/>
                  <TextBlock x:Name="StatTotal" Text="0" FontSize="19" FontWeight="SemiBold" Foreground="{DynamicResource T_UI_T1}" Margin="0,2,0,0"/>
                </StackPanel>
              </Grid>
            </Border>

            <Border Grid.Column="2" CornerRadius="11" BorderBrush="{DynamicResource T_UI_LINE}" BorderThickness="1" Height="94" Background="{DynamicResource T_UI_CARD}">
              
              <Grid Margin="12,11,12,12">
                <Border Width="22" Height="22" CornerRadius="7" Background="{DynamicResource T_UI_CHIP}" VerticalAlignment="Top" HorizontalAlignment="Left">
                  <TextBlock Text="▷" FontSize="11" Foreground="{DynamicResource T_UI_ICON}" HorizontalAlignment="Center" VerticalAlignment="Center"/>
                </Border>
                <StackPanel VerticalAlignment="Bottom">
                  <TextBlock Text="运行中" FontSize="10.5" Foreground="{DynamicResource T_UI_T3}"/>
                  <TextBlock x:Name="StatRun" Text="0" FontSize="19" FontWeight="SemiBold" Foreground="{DynamicResource T_UI_T1}" Margin="0,2,0,0"/>
                </StackPanel>
              </Grid>
            </Border>

            <Border Grid.Column="4" CornerRadius="11" BorderBrush="{DynamicResource T_UI_LINE}" BorderThickness="1" Height="94" Background="{DynamicResource T_UI_CARD}">
              
              <Grid Margin="12,11,12,12">
                <Border Width="22" Height="22" CornerRadius="7" Background="{DynamicResource T_UI_CHIP}" VerticalAlignment="Top" HorizontalAlignment="Left">
                  <TextBlock Text="☾" FontSize="11" Foreground="{DynamicResource T_UI_ICON}" HorizontalAlignment="Center" VerticalAlignment="Center"/>
                </Border>
                <StackPanel VerticalAlignment="Bottom">
                  <TextBlock Text="休眠中" FontSize="10.5" Foreground="{DynamicResource T_UI_T3}"/>
                  <TextBlock x:Name="StatSleep" Text="0" FontSize="19" FontWeight="SemiBold" Foreground="{DynamicResource T_UI_T1}" Margin="0,2,0,0"/>
                </StackPanel>
              </Grid>
            </Border>

            <Border Grid.Column="6" CornerRadius="11" BorderBrush="{DynamicResource T_UI_LINE}" BorderThickness="1" Height="94" Background="{DynamicResource T_UI_CARD}">
              
              <Grid Margin="12,11,12,12">
                <Border Width="22" Height="22" CornerRadius="7" Background="{DynamicResource T_UI_CHIP}" VerticalAlignment="Top" HorizontalAlignment="Left">
                  <TextBlock Text="⏻" FontSize="11" Foreground="{DynamicResource T_UI_ICON}" HorizontalAlignment="Center" VerticalAlignment="Center"/>
                </Border>
                <StackPanel VerticalAlignment="Bottom">
                  <TextBlock Text="已关闭" FontSize="10.5" Foreground="{DynamicResource T_UI_T3}"/>
                  <TextBlock x:Name="StatOff" Text="0" FontSize="19" FontWeight="SemiBold" Foreground="{DynamicResource T_UI_T1}" Margin="0,2,0,0"/>
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
              <Border Grid.Row="0" Background="{DynamicResource T_UI_CARD}" CornerRadius="11" BorderBrush="{DynamicResource T_UI_LINE}" BorderThickness="1">
                <StackPanel>
                  <Grid Margin="12,10,12,4">
                    <TextBlock Text="实例监控" FontSize="12.5" FontWeight="SemiBold" Foreground="{DynamicResource T_UI_T1}"/>
                    <TextBlock x:Name="TxtInstanceMore" Text="管理 ›" FontSize="10.5" Foreground="{DynamicResource T_UI_T3}" HorizontalAlignment="Right" Cursor="Hand"/>
                  </Grid>
                  <StackPanel x:Name="PnlInstances"/>
                </StackPanel>
              </Border>

              <!-- 事件记录 -->
              <Border Grid.Row="2" Background="{DynamicResource T_UI_CARD}" CornerRadius="11" BorderBrush="{DynamicResource T_UI_LINE}" BorderThickness="1">
                <StackPanel>
                  <Grid Margin="12,10,12,4">
                    <TextBlock Text="事件记录" FontSize="12.5" FontWeight="SemiBold" Foreground="{DynamicResource T_UI_T1}"/>
                    <TextBlock x:Name="TxtEventMore" Text="查看全部 ›" FontSize="10.5" Foreground="{DynamicResource T_UI_T3}" HorizontalAlignment="Right" Cursor="Hand"/>
                  </Grid>
                  <StackPanel x:Name="PnlEvents"/>
                </StackPanel>
              </Border>
            </Grid>

          <!-- 右栏 -->
          <Grid Grid.Column="2">
            <Grid.RowDefinitions>
              <RowDefinition Height="Auto"/>
              <RowDefinition Height="Auto"/>
              <RowDefinition Height="Auto"/>
              <RowDefinition Height="*"/>
            </Grid.RowDefinitions>
            <Grid Grid.Row="0" Margin="0,0,0,12">
              <Rectangle RadiusX="11" RadiusY="11" Fill="{DynamicResource T_UI_CARD}" Stroke="{DynamicResource T_UI_LINE}" StrokeThickness="1"/>
              <Border Padding="12,11,12,12">
                <StackPanel>
                  <TextBlock Text="主机内存" FontSize="11" Foreground="{DynamicResource T_UI_T3}"/>
                  <StackPanel Orientation="Horizontal" Margin="0,3,0,0">
                    <TextBlock x:Name="TxtMemUsed" Text="0.0" FontSize="24" FontWeight="SemiBold" Foreground="{DynamicResource T_UI_T1}"/>
                    <TextBlock x:Name="TxtMemTotal" Text="/ 0 GB" FontSize="11" Foreground="{DynamicResource T_UI_T3}" VerticalAlignment="Bottom" Margin="4,0,0,4"/>
                  </StackPanel>
                  <Border Height="5" CornerRadius="3" Background="#24FFFFFF" Margin="0,8,0,0">
                    <Border x:Name="MemBar" Width="0" Height="5" CornerRadius="3" Background="{DynamicResource T_UI_INFO}" HorizontalAlignment="Left"/>
                  </Border>
                  <StackPanel Orientation="Horizontal" Margin="0,8,0,0">
                    <Ellipse Width="5" Height="5" Fill="{DynamicResource T_UI_INFO}" VerticalAlignment="Center"/>
                    <TextBlock x:Name="TxtMemUsedLg" Text="已用 0 GB" FontSize="9.5" Foreground="{DynamicResource T_UI_T3}" Margin="4,0,12,0"/>
                    <Ellipse Width="5" Height="5" Fill="{DynamicResource T_UI_T3}" VerticalAlignment="Center"/>
                    <TextBlock x:Name="TxtMemFreeLg" Text="可用 0 GB" FontSize="9.5" Foreground="{DynamicResource T_UI_T3}" Margin="4,0,0,0"/>
                  </StackPanel>
                </StackPanel>
              </Border>
            </Grid>

            <Grid Grid.Row="1" Margin="0,0,0,12">
              <Rectangle RadiusX="11" RadiusY="11" Fill="{DynamicResource T_UI_CARD}" Stroke="{DynamicResource T_UI_LINE}" StrokeThickness="1"/>
              <Border Padding="0,12,0,12">
                <StackPanel>
                  <TextBlock Text="快捷操作" FontSize="12.5" FontWeight="SemiBold" Foreground="{DynamicResource T_UI_T1}" Margin="12,0,12,8"/>
                  <Grid Margin="12,0,12,0">
                    <Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="8"/><RowDefinition Height="Auto"/></Grid.RowDefinitions>
                    <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="8"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
                    <Border x:Name="BtnGuardRun" Grid.Row="0" Grid.Column="0" CornerRadius="9" Background="#F2F2F5" Padding="0,9" Cursor="Hand">
                      <TextBlock x:Name="TxtGuardRun" Text="开始看护" FontSize="11.5" FontWeight="SemiBold" Foreground="{DynamicResource T_UI_ON_ACC}" HorizontalAlignment="Center"/>
                    </Border>
                    <Border x:Name="BtnSleepRun" Grid.Row="0" Grid.Column="2" CornerRadius="9" Background="#1AFFFFFF" Padding="0,9" Cursor="Hand">
                      <TextBlock x:Name="TxtSleepRun" Text="自动休眠 关" FontSize="11.5" Foreground="#9E9EA6" HorizontalAlignment="Center"/>
                    </Border>
                    <Border x:Name="BtnCleanNow" Grid.Row="2" Grid.Column="0" CornerRadius="9" Background="#1AFFFFFF" Padding="0,9" Cursor="Hand">
                      <TextBlock Text="清理内存" FontSize="11.5" Foreground="#F2F2F5" HorizontalAlignment="Center"/>
                    </Border>
                    <Border x:Name="BtnRemoteOpen" Grid.Row="2" Grid.Column="2" CornerRadius="9" Background="#1AFFFFFF" Padding="0,9" Cursor="Hand">
                      <TextBlock Text="手机访问" FontSize="11.5" Foreground="#F2F2F5" HorizontalAlignment="Center"/>
                    </Border>
                  </Grid>
                </StackPanel>
              </Border>
            </Grid>

            <Grid x:Name="HealthCard" Grid.Row="2" Margin="0,0,0,12" Cursor="Hand">
              <Rectangle RadiusX="11" RadiusY="11" Fill="{DynamicResource T_UI_CARD}" Stroke="{DynamicResource T_UI_LINE}" StrokeThickness="1"/>
              <StackPanel Margin="0,12,0,12">
                <TextBlock Text="系统健康" FontSize="12.5" FontWeight="SemiBold" Foreground="{DynamicResource T_UI_T1}" Margin="12,0,12,8"/>
                <Grid Margin="12,0,12,0">
                  <Grid.ColumnDefinitions><ColumnDefinition Width="Auto"/><ColumnDefinition Width="*"/><ColumnDefinition Width="16"/></Grid.ColumnDefinitions>
                  <Border x:Name="HealthDot" Grid.Column="0" Width="26" Height="26" CornerRadius="13" Background="{DynamicResource T_UI_OKBG2}" VerticalAlignment="Center">
                    <TextBlock x:Name="HealthGlyph" Text="✓" FontSize="13" Foreground="{DynamicResource T_UI_OK}" HorizontalAlignment="Center" VerticalAlignment="Center"/>
                  </Border>
                  <StackPanel Grid.Column="1" Margin="10,0,0,0" VerticalAlignment="Center">
                    <TextBlock x:Name="TxtHealthTitle" Text="检查通过" FontSize="12" Foreground="{DynamicResource T_UI_T1}"/>
                    <TextBlock x:Name="TxtHealthSub" Text="系统服务与资源状态正常" FontSize="9.5" Foreground="{DynamicResource T_UI_T3}" Margin="0,1,0,0" TextTrimming="CharacterEllipsis"/>
                  </StackPanel>
                  <TextBlock Grid.Column="2" Text="›" FontSize="12" Foreground="{DynamicResource T_UI_ARROW}" VerticalAlignment="Center" HorizontalAlignment="Right"/>
                </Grid>
              </StackPanel>
            </Grid>
            <Grid Grid.Row="3">
              <Rectangle RadiusX="11" RadiusY="11" Fill="{DynamicResource T_UI_CARD}" Stroke="{DynamicResource T_UI_LINE}" StrokeThickness="1"/>
              <Border Padding="0,6,0,6">
              <StackPanel>
                <Grid Margin="12,7,12,2"><TextBlock Text="下次唤醒" FontSize="11" Foreground="{DynamicResource T_UI_T2}"/><TextBlock x:Name="TxtNextWake" Text="—" FontSize="11" Foreground="{DynamicResource T_UI_T1}" HorizontalAlignment="Right"/></Grid>
                <TextBlock x:Name="TxtNextWakeSub" Text="" FontSize="9.5" Foreground="{DynamicResource T_UI_T3}" HorizontalAlignment="Right" Margin="12,0,12,6"/>
                <Border Height="1" Background="{DynamicResource T_UI_DIV}" Margin="12,0,12,0"/>
                <Grid Margin="12,7,12,7"><TextBlock Text="今日休眠" FontSize="11" Foreground="{DynamicResource T_UI_T2}"/><TextBlock x:Name="TxtSleepToday" Text="0 次" FontSize="11" Foreground="{DynamicResource T_UI_T1}" HorizontalAlignment="Right"/></Grid>
              </StackPanel>
              </Border>
            </Grid>
          </Grid>
          </Grid>
        </Grid>

        <!-- 其余页面占位（后续填充） -->
        <Grid x:Name="Page2" Grid.Row="1" Grid.RowSpan="2" Visibility="Collapsed">
          <Grid Margin="0,14,0,0">
            <Rectangle RadiusX="11" RadiusY="11" Fill="{DynamicResource T_UI_CARD}" Stroke="{DynamicResource T_UI_LINE}" StrokeThickness="1"/>
              <StackPanel>
                
                <StackPanel x:Name="PnlManage" Margin="8,0,8,10"/>
              </StackPanel>
          </Grid>
        </Grid>

        <Grid x:Name="Page3" Grid.Row="1" Grid.RowSpan="2" Visibility="Collapsed">
          <Grid Margin="0,14,0,0">
            <Rectangle RadiusX="11" RadiusY="11" Fill="{DynamicResource T_UI_CARD}" Stroke="{DynamicResource T_UI_LINE}" StrokeThickness="1"/>
              <StackPanel>
                
                <StackPanel x:Name="PnlHealthDetail" Margin="16,0,16,14"/>
              </StackPanel>
          </Grid>
        </Grid>

        <Grid x:Name="Page4" Grid.Row="1" Grid.RowSpan="2" Visibility="Collapsed">
          <Grid>
            <Rectangle RadiusX="11" RadiusY="11" Fill="{DynamicResource T_UI_CARD}" Stroke="{DynamicResource T_UI_LINE}" StrokeThickness="1"/>
              <StackPanel>
                <Grid Margin="16,14,16,8">
                  <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="*"/><ColumnDefinition Width="*"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
                  <StackPanel Grid.Column="0"><TextBlock Text="今日休眠" FontSize="10" Foreground="{DynamicResource T_UI_T3}"/><TextBlock x:Name="TxtSleepToday2" Text="0" FontSize="17" FontWeight="SemiBold" Foreground="{DynamicResource T_UI_T1}" Margin="0,1,0,0"/></StackPanel>
                  <StackPanel Grid.Column="1"><TextBlock Text="自动唤醒" FontSize="10" Foreground="{DynamicResource T_UI_T3}"/><TextBlock x:Name="TxtWakeToday" Text="0" FontSize="17" FontWeight="SemiBold" Foreground="{DynamicResource T_UI_T1}" Margin="0,1,0,0"/></StackPanel>
                  <StackPanel Grid.Column="2"><TextBlock Text="内存清理" FontSize="10" Foreground="{DynamicResource T_UI_T3}"/><TextBlock x:Name="TxtCleanToday" Text="0" FontSize="17" FontWeight="SemiBold" Foreground="{DynamicResource T_UI_T1}" Margin="0,1,0,0"/></StackPanel>
                  <StackPanel Grid.Column="3"><TextBlock Text="异常恢复" FontSize="10" Foreground="{DynamicResource T_UI_T3}"/><TextBlock x:Name="TxtRecoverToday" Text="0" FontSize="17" FontWeight="SemiBold" Foreground="{DynamicResource T_UI_T1}" Margin="0,1,0,0"/></StackPanel>
                </Grid>
                <StackPanel Orientation="Horizontal" Margin="16,14,16,10">
                  <TextBox x:Name="TxtEventSearch" Width="150" Height="26" Margin="0,0,8,0" FontSize="11" Foreground="{DynamicResource T_UI_T1}" Background="{DynamicResource T_UI_INPUT}" BorderThickness="0" Padding="8,4,8,4" VerticalContentAlignment="Center" ToolTip="按实例名 / 内容搜索"/>
                <Border x:Name="BtnFAll" Background="#24FFFFFF" CornerRadius="7" Padding="10,4" Margin="0,0,6,0"><TextBlock Text="全部" FontSize="10.5" Foreground="#F2F2F5"/></Border>
                  <Border x:Name="BtnFWarn" Background="#1AFFFFFF" CornerRadius="7" Padding="10,4" Margin="0,0,6,0"><TextBlock Text="告警" FontSize="10.5" Foreground="#9E9EA6"/></Border>
                  <Border x:Name="BtnFSleep" Background="#1AFFFFFF" CornerRadius="7" Padding="10,4"><TextBlock Text="休眠" FontSize="10.5" Foreground="#9E9EA6"/></Border>
                </StackPanel>
                <ScrollViewer Height="470" VerticalScrollBarVisibility="Auto">
                  <StackPanel x:Name="PnlEventDetail" Margin="16,0,16,14"/>
                </ScrollViewer>
              </StackPanel>
          </Grid>
        </Grid>

        <Grid x:Name="Page5" Grid.Row="1" Grid.RowSpan="2" Visibility="Collapsed">
          <Grid Margin="0,14,0,0">
            <Rectangle RadiusX="11" RadiusY="11" Fill="{DynamicResource T_UI_CARD}" Stroke="{DynamicResource T_UI_LINE}" StrokeThickness="1"/>
              <ScrollViewer VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Disabled" TextOptions.TextFormattingMode="Display">
                <StackPanel Margin="16,14,16,20">
                  <StackPanel x:Name="PnlSettings"/>
                  <TextBlock Text="工具" FontSize="10.5" Foreground="{DynamicResource T_UI_T3}" Margin="2,18,0,6"/>
                  <Grid>
                    <Rectangle RadiusX="11" RadiusY="11" Fill="{DynamicResource T_UI_CARD}" Stroke="{DynamicResource T_UI_LINE}" StrokeThickness="1"/>
                      <StackPanel>
                        <Border x:Name="BtnOpenLog" Padding="14,0" Height="44" Background="Transparent" Cursor="Hand"><TextBlock Text="打开日志目录" FontSize="12" Foreground="{DynamicResource T_UI_T1}" VerticalAlignment="Center"/></Border>
                        <Border Height="1" Background="{DynamicResource T_UI_DIV}" Margin="14,0,14,0"/>
                        <Border x:Name="BtnExportRep" Padding="14,0" Height="44" Background="Transparent" Cursor="Hand"><TextBlock Text="导出诊断报告" FontSize="12" Foreground="{DynamicResource T_UI_T1}" VerticalAlignment="Center"/></Border>
                        <Border Height="1" Background="{DynamicResource T_UI_DIV}" Margin="14,0,14,0"/>
                        <Border x:Name="BtnCheckUpd" Padding="14,0" Height="44" Background="Transparent" Cursor="Hand"><TextBlock Text="检查更新" FontSize="12" Foreground="{DynamicResource T_UI_T1}" VerticalAlignment="Center"/></Border>
                        <Border Height="1" Background="{DynamicResource T_UI_DIV}" Margin="14,0,14,0"/>
                        <Border x:Name="BtnExportCfg" Padding="14,0" Height="44" Background="Transparent" Cursor="Hand"><TextBlock Text="导出设置" FontSize="12" Foreground="{DynamicResource T_UI_T1}" VerticalAlignment="Center"/></Border>
                        <Border Height="1" Background="{DynamicResource T_UI_DIV}" Margin="14,0,14,0"/>
                        <Border x:Name="BtnResetCfg" Padding="14,0" Height="44" Background="Transparent" Cursor="Hand"><TextBlock Text="恢复默认设置" FontSize="12" Foreground="{DynamicResource T_UI_ERR}" VerticalAlignment="Center"/></Border>
                </StackPanel>
              </Grid>
              </StackPanel>
            </ScrollViewer>
          </Grid>
        </Grid>
      </Grid>
    </Grid>
  </Border>
</Window>
'@
}

# 生成一行实例（概览）
function Get-CompactXaml {
    return @'
<Border xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        x:Name="CmpRoot" CornerRadius="12" Background="#2B2B30" BorderBrush="#33FFFFFF" BorderThickness="1">
  <StackPanel>
    <Grid Margin="12,9,9,7">
      <StackPanel Orientation="Horizontal">
        <Border Width="16" Height="16" CornerRadius="5" Background="Transparent" VerticalAlignment="Center">
          <Image x:Name="CmpLogo" Stretch="UniformToFill"/>
        </Border>
        <TextBlock Text="MuMuGuard" FontSize="11" Foreground="#F2F2F5" Margin="6,0,0,0" VerticalAlignment="Center" FontWeight="SemiBold"/>
        <Ellipse x:Name="CmpDot" Width="5" Height="5" Fill="#34C759" Margin="8,0,0,0" VerticalAlignment="Center"/>
        <TextBlock x:Name="CmpState" Text="看护中" FontSize="9.5" Foreground="#6E6E78" Margin="4,0,0,0" VerticalAlignment="Center"/>
      </StackPanel>
      <StackPanel Orientation="Horizontal" HorizontalAlignment="Right">
        <Border x:Name="BtnCmpExpand" Width="19" Height="19" CornerRadius="6" Background="#14FFFFFF">
          <TextBlock Text="⤢" FontSize="10" Foreground="#9E9EA6" HorizontalAlignment="Center" VerticalAlignment="Center"/>
        </Border>
        <Border x:Name="BtnCmpClose" Width="19" Height="19" CornerRadius="6" Background="#14FFFFFF" Margin="5,0,0,0">
          <TextBlock Text="✕" FontSize="9" Foreground="#9E9EA6" HorizontalAlignment="Center" VerticalAlignment="Center"/>
        </Border>
      </StackPanel>
    </Grid>
    <Border Height="1" Background="#0DFFFFFF"/>
    <UniformGrid x:Name="PnlRings" Columns="5" Margin="10,12,10,6"/>
    <Border Height="1" Background="#0DFFFFFF" Margin="10,2,10,0"/>
    <Grid Margin="12,7,12,8">
      <TextBlock x:Name="TxtCmpWake" Text="—" FontSize="9" Foreground="#6E6E78"/>
      <TextBlock x:Name="TxtCmpMem" Text="内存 —" FontSize="9" Foreground="#6E6E78" HorizontalAlignment="Right"/>
    </Grid>
  </StackPanel>
</Border>
'@
}

function New-RingCell {
    param($Row, [string]$Label, [int]$Pct, [string]$State)

    $sp = New-Object System.Windows.Controls.StackPanel
    $sp.HorizontalAlignment = 'Center'

    $grid = New-Object System.Windows.Controls.Grid
    $grid.Width = 46; $grid.Height = 46

    $track = New-Object System.Windows.Shapes.Ellipse
    $track.Width = 46; $track.Height = 46
    $track.Stroke = Brush '#22FFFFFF'
    $track.StrokeThickness = 3
    [void]$grid.Children.Add($track)

    if ($State -eq 'run') {
        $arc = New-Object System.Windows.Shapes.Ellipse
        $arc.Width = 46; $arc.Height = 46
        $arc.Stroke = Brush '#0A84FF'
        $arc.StrokeThickness = 3
        $arc.StrokeDashCap = 'Round'
        $circ = [math]::PI * 46
        $dash = [math]::Max(1, ($circ * $Pct / 100.0) / 3)
        $gap = [math]::Max(0.5, ($circ - ($circ * $Pct / 100.0)) / 3)
        $arc.StrokeDashArray = New-Object System.Windows.Media.DoubleCollection
        $arc.StrokeDashArray.Add($dash)
        $arc.StrokeDashArray.Add($gap)
        $arc.RenderTransformOrigin = '0.5,0.5'
        $rot = New-Object System.Windows.Media.RotateTransform
        $rot.Angle = -90
        $arc.RenderTransform = $rot
        [void]$grid.Children.Add($arc)
    } elseif ($State -eq 'sleep') {
        $ring = New-Object System.Windows.Shapes.Ellipse
        $ring.Width = 46; $ring.Height = 46
        $ring.Stroke = Brush '#FF9F0A'
        $ring.StrokeThickness = 3
        $ring.Opacity = 0.5
        [void]$grid.Children.Add($ring)
    }

    $txt = New-Object System.Windows.Controls.TextBlock
    $txt.FontSize = 9.5
    $txt.HorizontalAlignment = 'Center'
    $txt.VerticalAlignment = 'Center'
    switch ($State) {
        'run'   { $txt.Text = "$Pct%"; $txt.Foreground = Brush '#F2F2F5' }
        'sleep' { $txt.Text = '睡';  $txt.Foreground = Brush '#6E6E78'; $txt.FontSize = 11 }
        default { $txt.Text = '关';  $txt.Foreground = Brush '#4A4A52'; $txt.FontSize = 11 }
    }
    [void]$grid.Children.Add($txt)
    [void]$sp.Children.Add($grid)

    $nm = New-Object System.Windows.Controls.TextBlock
    $nm.Text = $Label
    $nm.FontSize = 9.5
    $nm.HorizontalAlignment = 'Center'
    $nm.Margin = New-Object System.Windows.Thickness(0, 5, 0, 0)
    $nm.TextTrimming = 'CharacterEllipsis'
    if ($State -eq 'run') { $nm.Foreground = Brush '#F2F2F5' }
    elseif ($State -eq 'sleep') { $nm.Foreground = Brush '#6E6E78' }
    else { $nm.Foreground = Brush '#4A4A52' }
    [void]$sp.Children.Add($nm)

    return $sp
}
function New-InstanceRowShell {
    param($Row, $Icon, $IsSleep, $IsOff)

    $grid = New-Object System.Windows.Controls.Grid
    $grid.Height = 54
    $grid.Margin = New-Object System.Windows.Thickness(12, 0, 10, 0)

    foreach ($w in @('Auto', '*', 'Auto', '92', '96', '16')) {
        $cd = New-Object System.Windows.Controls.ColumnDefinition
        if ($w -eq '*') { $cd.Width = [System.Windows.GridLength]::new(1, [System.Windows.GridUnitType]::Star) }
        elseif ($w -eq 'Auto') { $cd.Width = [System.Windows.GridLength]::Auto }
        else { $cd.Width = [System.Windows.GridLength]::new([double]$w) }
        [void]$grid.ColumnDefinitions.Add($cd)
    }

    # 图标
    $tile = New-Object System.Windows.Controls.Border
    $tile.Width = 26; $tile.Height = 26; $tile.CornerRadius = [System.Windows.CornerRadius]::new(8)
    $tile.Background = Brush '#00000000'
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
    $nm.Foreground = Brush '#F2F2F5'
    $sub = New-Object System.Windows.Controls.TextBlock
    $sub.Text = "$($Row.Judge)"; $sub.FontSize = 10.5
    $sub.Foreground = Brush '#6E6E78'
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
        $pill.Background = Brush '#29FF9F0A'
        $pt.Foreground = Brush '#FF9F0A'
        $pt.Text = '休眠'
    } elseif ($IsOff) {
        $pill.Background = Brush '#14FFFFFF'
        $pt.Foreground = Brush '#9E9EA6'
        $pt.Text = '关闭'
    } else {
        $pill.Background = Brush '#2934C759'
        $pt.Foreground = Brush '#34C759'
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
    $mt.Foreground = Brush '#9E9EA6'
    $track = New-Object System.Windows.Controls.Border
    $track.Height = 3; $track.CornerRadius = [System.Windows.CornerRadius]::new(2)
    $track.Background = Brush '#22FFFFFF'
    $track.Margin = New-Object System.Windows.Thickness(0, 4, 0, 0)
    if (-not $IsOff -and $Row.Private -gt 0) {
        $fill = New-Object System.Windows.Controls.Border
        $fill.Height = 3; $fill.CornerRadius = [System.Windows.CornerRadius]::new(2)
        $fill.Background = Brush '#0A84FF'
        $fill.HorizontalAlignment = 'Left'
        $barBase = 6144.0
        if ($Row.PSObject.Properties.Name -contains 'MemBase' -and [double]$Row.MemBase -gt 0) { $barBase = [double]$Row.MemBase }
        $pct = [math]::Min(100, [math]::Max(4, ($Row.Private / $barBase) * 100))
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
    $tt.Foreground = Brush '#F2F2F5'
    $ts = New-Object System.Windows.Controls.TextBlock
    $ts.FontSize = 9.5
    $ts.HorizontalAlignment = 'Right'
    $ts.Margin = New-Object System.Windows.Thickness(0, 1, 0, 0)
    $ts.Foreground = Brush '#6E6E78'
    if ($IsSleep -and $Row.WakeAt) {
        $wi = Get-WakeInfo $Row.WakeAt
        $tt.Text = $wi.Main
        $ts.Text = $wi.Sub
    } elseif ($IsOff) {
        $tt.Text = '—'
        $ts.Text = '无任务'
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
    $ch.Foreground = Brush '#40FFFFFF'
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
    $t.Foreground = Brush '#6E6E78'
    [System.Windows.Controls.Grid]::SetColumn($t, 0); [void]$g.Children.Add($t)

    $dotColor = switch ($Level) { 'ok' { '#34C759' } 'warn' { '#FF9F0A' } 'err' { '#FF453A' } default { '#5A5A64' } }
    $e = New-Object System.Windows.Shapes.Ellipse
    $e.Width = 5; $e.Height = 5; $e.VerticalAlignment = 'Center'; $e.HorizontalAlignment = 'Left'
    $e.Fill = Brush $dotColor
    [System.Windows.Controls.Grid]::SetColumn($e, 1); [void]$g.Children.Add($e)

    $x = New-Object System.Windows.Controls.TextBlock
    $x.Text = $Text; $x.FontSize = 11; $x.VerticalAlignment = 'Center'
    $x.TextTrimming = 'CharacterEllipsis'
    $x.Foreground = Brush $(if ($Level -eq 'err') { '#FF8078' } else { '#9E9EA6' })
    [System.Windows.Controls.Grid]::SetColumn($x, 2); [void]$g.Children.Add($x)
    return $g
}
