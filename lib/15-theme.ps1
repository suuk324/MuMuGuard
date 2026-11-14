#Requires -Version 5.1
#
# 主题：深色 / 浅色 / 跟随系统
# 做法：把界面里所有硬编码色值映射成固定 token，再按当前主题给出实际色值。
#   - XAML 里的色值在解析前替换成 {DynamicResource T_xxxxxx}，切换主题时资源一改，界面立即更新
#   - 代码里新建的控件走 Brush()，由本模块按当前主题翻译

# 深色（现有配色，作为基准）
$script:PaletteDark = [ordered]@{
    'T_0A0D14' = '#0A0D14'   # 窗口底色
    'T_0F141C' = '#0F141C'   # 卡片 / 面板底
    'T_161C26' = '#161C26'   # 卡片描边 / 深色按钮
    'T_141A24' = '#141A24'   # 次级按钮底
    'T_1A2130' = '#1A2130'   # 环底座
    'T_1E293B' = '#1E293B'   # 输入框底
    'T_2A3650' = '#2A3650'   # 内存格（已用）
    'T_232B3A' = '#232B3A'   # 休眠环底座
    'T_E6EAF2' = '#E6EAF2'   # 主文字
    'T_C9D2E0' = '#C9D2E0'   # 次级亮文字
    'T_8A94A6' = '#8A94A6'   # 次文字
    'T_7C8BA8' = '#7C8BA8'   # 休眠文字
    'T_4B566B' = '#4B566B'   # 弱文字
    'T_414B5E' = '#414B5E'   # 极弱文字 / 标签
    'T_3DDC84' = '#3DDC84'   # 正常绿
    'T_F5A524' = '#F5A524'   # 警告黄
    'T_F26D6D' = '#F26D6D'   # 错误红
    'T_FB923C' = '#FB923C'   # 橙色强调
    'T_E8EDF5' = '#E8EDF5'   # 主按钮底
    'T_1B2A22' = '#1B2A22'   # 绿色按钮底
    'T_2A2110' = '#2A2110'   # 黄色按钮底
    'T_2A1214' = '#2A1214'   # 红色按钮底
    'T_16241C' = '#16241C'   # 深绿按钮底
    'T_0F2A1C' = '#0F2A1C'   # 深绿面板底
}

# 浅色：保持同样的层级关系，只是明暗翻转
$script:PaletteLight = [ordered]@{
    'T_0A0D14' = '#F3F5F8'   # 窗口底色
    'T_0F141C' = '#FFFFFF'   # 卡片
    'T_161C26' = '#E3E8F0'   # 描边
    'T_141A24' = '#EEF1F6'   # 次级按钮
    'T_1A2130' = '#E2E7F0'   # 环底座
    'T_1E293B' = '#F7F8FA'   # 输入框
    'T_2A3650' = '#C3CDDD'   # 内存格
    'T_232B3A' = '#E7EBF2'   # 休眠环底座
    'T_E6EAF2' = '#111827'   # 主文字
    'T_C9D2E0' = '#1F2937'   # 次级亮文字
    'T_8A94A6' = '#5B6678'   # 次文字
    'T_7C8BA8' = '#7C8798'   # 休眠文字
    'T_4B566B' = '#8A93A3'   # 弱文字
    'T_414B5E' = '#98A2B3'   # 极弱文字
    'T_3DDC84' = '#16A34A'   # 绿
    'T_F5A524' = '#C2760A'   # 黄
    'T_F26D6D' = '#DC2626'   # 红
    'T_FB923C' = '#EA580C'   # 橙
    'T_E8EDF5' = '#1F2937'   # 主按钮底（浅色下反转为深色）
    'T_1B2A22' = '#E6F6EC'   # 绿色按钮底
    'T_2A2110' = '#FDF1E0'   # 黄色按钮底
    'T_2A1214' = '#FBE9E9'   # 红色按钮底
    'T_16241C' = '#E9F6EF'   # 深绿按钮底
    'T_0F2A1C' = '#E4F5EB'   # 深绿面板底
}

# 色值 -> token 反查表
$script:HexToToken = @{}
foreach ($k in $script:PaletteDark.Keys) {
    $script:HexToToken[$script:PaletteDark[$k].ToUpper()] = $k
}

# 系统是否处于浅色模式
function Get-SystemIsLight {
    try {
        $v = Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize' -Name 'AppsUseLightTheme' -ErrorAction Stop
        return ([int]$v.AppsUseLightTheme -eq 1)
    } catch {
        return $false
    }
}

# 当前应使用的主题：dark / light
function Get-ActiveTheme {
    $mode = "$($script:cfg.Theme)"
    if ($mode -eq 'light') { return 'light' }
    if ($mode -eq 'dark')  { return 'dark' }
    if (Get-SystemIsLight) { return 'light' }
    return 'dark'
}

# 取当前色板
function Get-Palette {
    if ((Get-ActiveTheme) -eq 'light') { return $script:PaletteLight }
    return $script:PaletteDark
}

# 把深色基准色值翻译成当前主题下的色值（代码里 Brush '#xxxxxx' 走这里）
function Convert-ThemeHex([string]$hex) {
    if (-not $hex) { return $hex }
    $u = $hex.ToUpper()
    if (-not $script:HexToToken.ContainsKey($u)) { return $hex }
    $token = $script:HexToToken[$u]
    $p = Get-Palette
    if ($p.Contains($token)) { return $p[$token] }
    return $hex
}

# 预测：如果换成某个主题，这个色值会变成什么（用于提前生成 XAML）
function Get-ThemedHex([string]$hex, [string]$theme) {
    $u = $hex.ToUpper()
    if (-not $script:HexToToken.ContainsKey($u)) { return $hex }
    $token = $script:HexToToken[$u]
    if ($theme -eq 'light') { return $script:PaletteLight[$token] }
    return $script:PaletteDark[$token]
}

# 把 XAML 里的硬编码色值换成 DynamicResource 引用
function Convert-XamlTheme([string]$xaml) {
    foreach ($hex in $script:PaletteDark.Keys) {
        $token = $hex
        $val = $script:PaletteDark[$hex]
        # 只替换带引号的色值，避免误伤其它文本
        $xaml = $xaml.Replace('"' + $val + '"', '"{DynamicResource ' + $token + '}"')
        $xaml = $xaml.Replace('"' + $val.ToUpper() + '"', '"{DynamicResource ' + $token + '}"')
        $xaml = $xaml.Replace('"' + $val.ToLower() + '"', '"{DynamicResource ' + $token + '}"')
    }
    return $xaml
}

# 生成要注入 XAML 的资源定义（当前主题的实际色值）
function New-ThemeResourcesXaml {
    $p = Get-Palette
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.AppendLine('  <Window.Resources>')
    foreach ($k in $p.Keys) {
        [void]$sb.AppendLine(('    <SolidColorBrush x:Key="{0}" Color="{1}"/>' -f $k, $p[$k]))
    }
    [void]$sb.AppendLine('  </Window.Resources>')
    return $sb.ToString()
}

# 用 C# 写资源字典：PowerShell 直接赋值会包一层 PSObject，WPF 拿去做 Brush 时会转换失败
if (-not ('ThemeRes' -as [type])) {
    Add-Type -TypeDefinition @"
using System;
using System.Windows;
using System.Windows.Media;

public static class ThemeRes
{
    public static void Set(ResourceDictionary dict, string key, string hex)
    {
        var color = (Color)ColorConverter.ConvertFromString(hex);
        dict[key] = new SolidColorBrush(color);
    }
}
"@ -ReferencedAssemblies PresentationFramework, PresentationCore, WindowsBase, System.Xaml
}

# 把一个窗口的资源整体换成指定主题的色值（DynamicResource 会自动刷新界面）
function Set-ThemeResources($win, [string]$theme) {
    if (-not $win) { return }
    $p = if ($theme -eq 'light') { $script:PaletteLight } else { $script:PaletteDark }
    foreach ($k in $p.Keys) {
        try {
            [ThemeRes]::Set($win.Resources, $k, $p[$k])
        } catch {
            Write-Diag "设置主题资源失败 $k : $($_.Exception.Message)"
        }
    }
}

# 切换主题：换资源 + 清掉按主题缓存过的控件 + 重绘
function Set-Theme([string]$mode) {
    $script:cfg.Theme = $mode
    Save-Config
    $theme = Get-ActiveTheme
    Set-ThemeResources $win $theme
    # 设置对话框开着的时候也要同步换色，否则会出现「浅色面板 + 黑色对话框」
    if ($script:settingsWin) {
        try { Set-ThemeResources $script:settingsWin $theme } catch { }
    }

    # 之前创建的控件用的是旧画刷，清掉重建（注意变量名必须和主程序一致）
    try { $script:cmpMap = @{}; if ($cmpRings) { [void]$cmpRings.Children.Clear() } } catch { }
    try { $script:cardMap = @{}; if ($pnlCards) { [void]$pnlCards.Children.Clear() } } catch { }
    try { $script:cellMap = @(); if ($cmpCells) { [void]$cmpCells.Children.Clear() } } catch { }
    try { $script:listRows = @{}; if ($cmpList) { [void]$cmpList.Children.Clear() } } catch { }
    try { $script:healthRows = @(); if ($pnlHealth) { [void]$pnlHealth.Children.Clear() } } catch { }
    try { if ($script:cmpEmpty -and $cmpRingsHost) { [void]$cmpRingsHost.Children.Remove($script:cmpEmpty) }; $script:cmpEmpty = $null } catch { }
    try { $script:lastGuardState = $null } catch { }
    try { $script:lastFilled = -1 } catch { }
    try { $script:lastFilled = -1 } catch { }
    try { Update-Ui } catch { }
}

# 主题显示名
function Get-ThemeLabel([string]$mode) {
    switch ($mode) {
        'dark'  { return '深色' }
        'light' { return '浅色' }
        default { return '跟随系统' }
    }
}

# 把控件颜色绑定到主题资源（切换主题时自动更新）
function Bind-ThemeBrush {
    param($Control, [string]$Hex, [string]$Which = 'Foreground')
    if (-not $Control) { return }
    $token = 'T_' + ($Hex -replace '#', '').ToUpper()
    $dp = $null
    switch ($Which) {
        'Foreground' {
            if ($Control -is [System.Windows.Controls.TextBlock]) { $dp = [System.Windows.Controls.TextBlock]::ForegroundProperty }
            else { $dp = [System.Windows.Controls.Control]::ForegroundProperty }
        }
        'Background'  { $dp = [System.Windows.Controls.Control]::BackgroundProperty }
        'BorderBrush' { $dp = [System.Windows.Controls.Control]::BorderBrushProperty }
    }
    if ($null -eq $dp) { return }
    try { $Control.SetResourceReference($dp, $token) } catch { }
}
