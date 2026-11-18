# 紧凑视图 · B（环）定稿
# 运行：powershell -STA -File preview-compact.ps1

Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Drawing

$xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="紧凑视图" Width="344" Height="182"
        WindowStartupLocation="CenterScreen"
        WindowStyle="None" AllowsTransparency="True" Background="Transparent"
        FontFamily="Microsoft YaHei UI">
  <Window.Resources>
    <SolidColorBrush x:Key="Card" Color="#2B2B30"/>
    <SolidColorBrush x:Key="Line" Color="#33FFFFFF"/>
    <SolidColorBrush x:Key="T1" Color="#F2F2F5"/>
    <SolidColorBrush x:Key="T2" Color="#9E9EA6"/>
    <SolidColorBrush x:Key="T3" Color="#6E6E78"/>
    <SolidColorBrush x:Key="Green" Color="#34C759"/>
    <SolidColorBrush x:Key="Amber" Color="#FF9F0A"/>
    <SolidColorBrush x:Key="Blue" Color="#0A84FF"/>
  </Window.Resources>

  <Border x:Name="Root" CornerRadius="12" Background="{StaticResource Card}" BorderBrush="{StaticResource Line}" BorderThickness="1">
    <StackPanel>
      <!-- 顶栏 -->
      <Grid Margin="12,9,9,7">
        <StackPanel Orientation="Horizontal">
          <Border Width="16" Height="16" CornerRadius="5" Background="Transparent" VerticalAlignment="Center">
            <Image x:Name="Logo" Stretch="UniformToFill"/>
          </Border>
          <TextBlock Text="MuMuGuard" FontSize="11" Foreground="{StaticResource T1}" Margin="6,0,0,0" VerticalAlignment="Center" FontWeight="SemiBold"/>
          <Ellipse Width="5" Height="5" Fill="{StaticResource Green}" Margin="8,0,0,0" VerticalAlignment="Center"/>
          <TextBlock Text="1 跑 · 2 睡" FontSize="9.5" Foreground="{StaticResource T3}" Margin="4,0,0,0" VerticalAlignment="Center"/>
        </StackPanel>
        <StackPanel Orientation="Horizontal" HorizontalAlignment="Right">
          <Border x:Name="BtnExpand" Width="19" Height="19" CornerRadius="6" Background="#14FFFFFF">
            <TextBlock Text="⤢" FontSize="10" Foreground="{StaticResource T2}" HorizontalAlignment="Center" VerticalAlignment="Center"/>
          </Border>
          <Border x:Name="BtnClose" Width="19" Height="19" CornerRadius="6" Background="#14FFFFFF" Margin="5,0,0,0">
            <TextBlock Text="✕" FontSize="9" Foreground="{StaticResource T2}" HorizontalAlignment="Center" VerticalAlignment="Center"/>
          </Border>
        </StackPanel>
      </Grid>
      <Border Height="1" Background="#0DFFFFFF"/>

      <!-- 五个环 -->
      <Grid Margin="10,12,10,6">
        <Grid.ColumnDefinitions>
          <ColumnDefinition Width="*"/><ColumnDefinition Width="*"/><ColumnDefinition Width="*"/><ColumnDefinition Width="*"/><ColumnDefinition Width="*"/>
        </Grid.ColumnDefinitions>

        <StackPanel Grid.Column="0" HorizontalAlignment="Center">
          <Grid Width="46" Height="46">
            <Ellipse Width="46" Height="46" Stroke="#22FFFFFF" StrokeThickness="3"/>
            <Ellipse Width="46" Height="46" Stroke="{StaticResource Blue}" StrokeThickness="3"
                     StrokeDashArray="30 18.5" StrokeDashCap="Round" RenderTransformOrigin="0.5,0.5">
              <Ellipse.RenderTransform><RotateTransform Angle="-90"/></Ellipse.RenderTransform>
            </Ellipse>
            <TextBlock Text="62%" FontSize="9.5" Foreground="{StaticResource T1}" HorizontalAlignment="Center" VerticalAlignment="Center"/>
          </Grid>
          <TextBlock Text="微信" FontSize="9.5" Foreground="{StaticResource T1}" HorizontalAlignment="Center" Margin="0,5,0,0"/>
        </StackPanel>

        <StackPanel Grid.Column="1" HorizontalAlignment="Center">
          <Grid Width="46" Height="46">
            <Ellipse Width="46" Height="46" Stroke="#22FFFFFF" StrokeThickness="3"/>
            <Ellipse Width="46" Height="46" Stroke="{StaticResource Amber}" StrokeThickness="3" Opacity="0.5"
                     RenderTransformOrigin="0.5,0.5">
              <Ellipse.RenderTransform><RotateTransform Angle="-90"/></Ellipse.RenderTransform>
            </Ellipse>
            <TextBlock Text="睡" FontSize="11" Foreground="{StaticResource T3}" HorizontalAlignment="Center" VerticalAlignment="Center"/>
          </Grid>
          <TextBlock Text="国际服" FontSize="9.5" Foreground="{StaticResource T3}" HorizontalAlignment="Center" Margin="0,5,0,0"/>
        </StackPanel>

        <StackPanel Grid.Column="2" HorizontalAlignment="Center">
          <Grid Width="46" Height="46">
            <Ellipse Width="46" Height="46" Stroke="#22FFFFFF" StrokeThickness="3"/>
            <Ellipse Width="46" Height="46" Stroke="{StaticResource Amber}" StrokeThickness="3" Opacity="0.5"
                     RenderTransformOrigin="0.5,0.5">
              <Ellipse.RenderTransform><RotateTransform Angle="-90"/></Ellipse.RenderTransform>
            </Ellipse>
            <TextBlock Text="睡" FontSize="11" Foreground="{StaticResource T3}" HorizontalAlignment="Center" VerticalAlignment="Center"/>
          </Grid>
          <TextBlock Text="国服QQ" FontSize="9.5" Foreground="{StaticResource T3}" HorizontalAlignment="Center" Margin="0,5,0,0"/>
        </StackPanel>

        <StackPanel Grid.Column="3" HorizontalAlignment="Center">
          <Grid Width="46" Height="46">
            <Ellipse Width="46" Height="46" Stroke="#1AFFFFFF" StrokeThickness="3"/>
            <TextBlock Text="关" FontSize="11" Foreground="#4A4A52" HorizontalAlignment="Center" VerticalAlignment="Center"/>
          </Grid>
          <TextBlock Text="设备-2" FontSize="9.5" Foreground="#4A4A52" HorizontalAlignment="Center" Margin="0,5,0,0"/>
        </StackPanel>

        <StackPanel Grid.Column="4" HorizontalAlignment="Center">
          <Grid Width="46" Height="46">
            <Ellipse Width="46" Height="46" Stroke="#1AFFFFFF" StrokeThickness="3"/>
            <TextBlock Text="关" FontSize="11" Foreground="#4A4A52" HorizontalAlignment="Center" VerticalAlignment="Center"/>
          </Grid>
          <TextBlock Text="设备-4" FontSize="9.5" Foreground="#4A4A52" HorizontalAlignment="Center" Margin="0,5,0,0"/>
        </StackPanel>
      </Grid>

      <!-- 底部 -->
      <Border Height="1" Background="#0DFFFFFF" Margin="10,4,10,0"/>
      <Grid Margin="12,7,12,8">
        <TextBlock Text="05:45 唤醒国际服" FontSize="9" Foreground="{StaticResource T3}"/>
        <TextBlock Text="内存 5.2 / 15.7 GB" FontSize="9" Foreground="{StaticResource T3}" HorizontalAlignment="Right"/>
      </Grid>
    </StackPanel>
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
$win.FindName('Logo').Source = Load-Ico 'C:\Users\MOOM\Documents\MuMuGuard\MuMuGuard.ico'

$win.FindName('Root').Add_MouseLeftButtonDown({ $win.DragMove() })
$win.FindName('BtnClose').Add_MouseLeftButtonUp({ $win.Close() })
$win.FindName('BtnExpand').Add_MouseLeftButtonUp({ $win.Close() })
$win.ShowDialog() | Out-Null