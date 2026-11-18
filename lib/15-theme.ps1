#Requires -Version 5.1
#
# 主题：深色 / 浅色 / 跟随系统
# 做法：把界面里所有硬编码色值映射成固定 token，再按当前主题给出实际色值。
#   - XAML 里的色值在解析前替换成 {DynamicResource T_xxxxxx}，切换主题时资源一改，界面立即更新
#   - 代码里新建的控件走 Brush()，由本模块按当前主题翻译

# 深色（现有配色，作为基准）
$script:PaletteDark = [ordered]@{
    'T_0A0D14' = '#0B0E13'   # 窗口底色
    'T_0F141C' = '#12161D'   # 卡片 / 面板底
    'T_161C26' = '#232A36'   # 卡片描边 / 深色按钮
    'T_141A24' = '#1A1F29'   # 次级按钮底
    'T_1A2130' = '#1E242E'   # 环底座
    'T_1E293B' = '#171C25'   # 输入框底
    'T_2A3650' = '#2E3A55'   # 内存格（已用）
    'T_232B3A' = '#1E242E'   # 休眠环底座
    'T_E6EAF2' = '#E8ECF2'   # 主文字
    'T_C9D2E0' = '#C7D0DC'   # 次级亮文字
    'T_8A94A6' = '#9BA5B4'   # 次文字
    'T_7C8BA8' = '#8E9AAA'   # 休眠文字
    'T_4B566B' = '#6B7485'   # 弱文字
    'T_414B5E' = '#565F6E'   # 极弱文字 / 标签
    'T_3DDC84' = '#3FB950'   # 正常绿
    'T_F5A524' = '#D29922'   # 警告黄
    'T_F26D6D' = '#F85149'   # 错误红
    'T_FB923C' = '#E08A3C'   # 橙色强调
    'T_E8EDF5' = '#E8ECF2'   # 主按钮底
    'T_1B2A22' = '#16281D'   # 绿色按钮底
    'T_2A2110' = '#2A2010'   # 黄色按钮底
    'T_2A1214' = '#2A1315'   # 红色按钮底
    'T_16241C' = '#14251A'   # 深绿按钮底
    'T_0F2A1C' = '#10271A'   # 深绿面板底
    # —— 新界面（v1.6.4 重构）用到的色值 ——
    'T_UI_BG'      = '#1F1F23'   # 窗口底
    'T_UI_SIDE'    = '#262629'   # 侧栏
    'T_UI_CARD'    = '#2B2B30'   # 卡片
    'T_UI_DIALOG'  = '#232327'   # 对话框
    'T_UI_INPUT'   = '#1A1A1E'   # 输入框 / 内嵌块
    'T_UI_DEEP'    = '#17171A'   # 最深底（手机页 / 页面底）
    'T_UI_RAISE'   = '#33333A'   # 抬升一档的卡片
    'T_UI_RAISE2'  = '#2A2A2F'   # 渐变尾色
    'T_UI_TILE'    = '#3A3A42'   # 图标底座
    'T_UI_T1'      = '#F2F2F5'   # 主文字 / 主按钮底
    'T_UI_T2'      = '#9E9EA6'   # 次文字
    'T_UI_T3'      = '#6E6E78'   # 弱文字
    'T_UI_OK'      = '#34C759'   # 正常绿
    'T_UI_WARN'    = '#FF9F0A'   # 警告橙
    'T_UI_INFO'    = '#0A84FF'   # 信息蓝
    'T_UI_ERR'     = '#FF453A'   # 错误红
    'T_UI_LINE'    = '#33FFFFFF' # 描边
    'T_UI_FILL1'   = '#1AFFFFFF' # 次级块
    'T_UI_FILL2'   = '#24FFFFFF' # 选中块
    'T_UI_FILL3'   = '#14FFFFFF' # 按钮底
    'T_UI_DIV'     = '#0DFFFFFF' # 分隔线
}

# 浅色：保持同样的层级关系，只是明暗翻转
$script:PaletteLight = [ordered]@{
    'T_0A0D14' = '#F5F7FA'   # 窗口底色
    'T_0F141C' = '#FFFFFF'   # 卡片
    'T_161C26' = '#E2E6EC'   # 描边
    'T_141A24' = '#EFF2F6'   # 次级按钮
    'T_1A2130' = '#E4E8EE'   # 环底座
    'T_1E293B' = '#F8F9FB'   # 输入框
    'T_2A3650' = '#C6D0DE'   # 内存格
    'T_232B3A' = '#E9ECF1'   # 休眠环底座
    'T_E6EAF2' = '#111826'   # 主文字
    'T_C9D2E0' = '#202A38'   # 次级亮文字
    'T_8A94A6' = '#5A6474'   # 次文字
    'T_7C8BA8' = '#7B8595'   # 休眠文字
    'T_4B566B' = '#8B94A3'   # 弱文字
    'T_414B5E' = '#9AA3B2'   # 极弱文字
    'T_3DDC84' = '#1A7F37'   # 绿
    'T_F5A524' = '#9A6700'   # 黄
    'T_F26D6D' = '#CF222E'   # 红
    'T_FB923C' = '#BC4C00'   # 橙
    'T_E8EDF5' = '#202A38'   # 主按钮底（浅色下反转为深色）
    'T_1B2A22' = '#E8F5EC'   # 绿色按钮底
    'T_2A2110' = '#FBF3E2'   # 黄色按钮底
    'T_2A1214' = '#FCEBEC'   # 红色按钮底
    'T_16241C' = '#EBF7EF'   # 深绿按钮底
    'T_0F2A1C' = '#E6F4EB'   # 深绿面板底
    'T_UI_BG'      = '#F4F5F7'
    'T_UI_SIDE'    = '#ECEDF0'
    'T_UI_CARD'    = '#FFFFFF'
    'T_UI_DIALOG'  = '#FFFFFF'
    'T_UI_INPUT'   = '#F2F3F5'
    'T_UI_DEEP'    = '#F7F8FA'
    'T_UI_RAISE'   = '#E8E9EC'
    'T_UI_RAISE2'  = '#F0F1F3'
    'T_UI_TILE'    = '#DCDDE2'
    'T_UI_T1'      = '#17171A'
    'T_UI_T2'      = '#5A5A62'
    'T_UI_T3'      = '#8A8A92'
    'T_UI_OK'      = '#1A7F37'
    'T_UI_WARN'    = '#9A6700'
    'T_UI_INFO'    = '#0B62D6'
    'T_UI_ERR'     = '#CF222E'
    'T_UI_LINE'    = '#1A000000'
    'T_UI_FILL1'   = '#0F000000'
    'T_UI_FILL2'   = '#14000000'
    'T_UI_FILL3'   = '#0D000000'
    'T_UI_DIV'     = '#0D000000'
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
    # 通过「色值反查表」找资源键：调色板的值改过之后，不能再靠色值拼键名
    $key = $Hex.ToUpper()
    $token = if ($script:HexToToken.ContainsKey($key)) { $script:HexToToken[$key] } else { 'T_' + ($Hex -replace '#', '').ToUpper() }
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

