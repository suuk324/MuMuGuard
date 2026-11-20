#Requires -Version 5.1
<#
    国际服实例（默认实例1）内的 xxYun 安卓版自动连接脚本

    背景：xxYun 安卓客户端没有「开机自启 / 自动连接」开关；
          Android 的「始终开启 VPN」实测也无法在模拟器冷启动时拉起它（App 没有 BOOT_COMPLETED receiver）。
          因此用 MuMuManager + adb 在实例启动后自动：启动 xxYun -> 关掉服务公告 -> 点连接 -> 校验 tun0。

    用法：
      单次检查（调试用）：
        powershell -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File .\xxyun-android-autoconnect.ps1 -Once
      常驻看门狗（推荐配合 Windows 计划任务“登录时启动”）：
        powershell -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File .\xxyun-android-autoconnect.ps1
      暂停：在脚本目录放一个 xxYunAutoConnect.disabled 文件（或结束该 powershell 进程）
#>
param(
    [int]$Instance = 1,
    [string]$MuMuRoot = 'D:\Program Files\Netease\MuMu',
    [string]$AdbExe = '',
    [switch]$Once,
    [int]$IntervalSec = 20
)
$ErrorActionPreference = 'Continue'

$script:LogFile = Join-Path $PSScriptRoot 'xxyun-autoconnect.log'
$script:DisabledFlag = Join-Path $PSScriptRoot 'xxYunAutoConnect.disabled'
$script:UiFileHost = Join-Path $env:TEMP 'mmg-xxyun-ui.xml'
$script:Serial = ''

function Write-AutoLog([string]$msg) {
    try {
        $line = '[{0:yyyy-MM-dd HH:mm:ss}] {1}' -f (Get-Date), $msg
        Add-Content -Path $script:LogFile -Value $line -Encoding UTF8
    } catch { }
}

function Get-VmInfo {
    $mgr = Join-Path $MuMuRoot 'nx_main\MuMuManager.exe'
    if (-not (Test-Path $mgr)) { return $null }
    try {
        $raw = & $mgr info -v $Instance 2>&1 | Out-String
        if ($raw -match '"index"') { return ($raw | ConvertFrom-Json) }
    } catch { }
    return $null
}

function Get-Adb {
    if ($AdbExe -and (Test-Path $AdbExe)) { return $AdbExe }
    $p = Join-Path $MuMuRoot 'nx_device\12.0\shell\adb.exe'
    if (Test-Path $p) { return $p }
    return 'adb.exe'
}

function Invoke-Adb([string[]]$argv) {
    if (-not $script:Serial) { return '' }
    try { return (& (Get-Adb) -s $script:Serial @argv 2>&1 | Out-String) } catch { return '' }
}

function Invoke-Sh([string]$cmd) {
    return (Invoke-Adb @('shell', $cmd))
}

function Ensure-Connected {
    $j = Get-VmInfo
    if (-not $j) { return $false }
    if (-not $j.is_process_started) { return $false }
    if (-not $j.adb_port) { return $false }
    $serial = "127.0.0.1:$($j.adb_port)"
    if ($script:Serial -ne $serial) {
        $script:Serial = $serial
        $null = & (Get-Adb) connect $serial 2>&1
    }
    return $true
}

function Test-Booted {
    $v = (Invoke-Sh 'getprop sys.boot_completed').Trim()
    return ($v -match '1')
}

function Test-VpnUp {
    # 注意：tun0 不存在时 adb 会返回 Device "tun0" does not exist，字符串里也带 tun0，
    # 不能只匹配 tun0，必须匹配 tun0 后面确实有 inet 地址
    $r = Invoke-Sh 'ip -o addr show tun0 2>/dev/null'
    return ($r -match 'tun0\s+inet ')
}

function Get-UiXml {
    Invoke-Adb @('shell', 'uiautomator dump /sdcard/mmg-ui.xml') | Out-Null
    Invoke-Adb @('pull', '/sdcard/mmg-ui.xml', $script:UiFileHost) | Out-Null
    if (Test-Path $script:UiFileHost) {
        try { return [System.IO.File]::ReadAllText($script:UiFileHost, [System.Text.Encoding]::UTF8) } catch { }
    }
    return ''
}

function Find-Node([string]$xml, [string]$pattern) {
    if (-not $xml) { return $null }
    foreach ($m in [regex]::Matches($xml, '<node[^>]+>')) {
        $n = $m.Value
        $desc = if ($n -match 'content-desc="([^"]*)"') { $Matches[1] } else { '' }
        $text = if ($n -match 'text="([^"]*)"') { $Matches[1] } else { '' }
        if ($desc -match $pattern -or $text -match $pattern) {
            if ($n -match 'bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"') {
                $x = [int](([int]$Matches[1] + [int]$Matches[3]) / 2)
                $y = [int](([int]$Matches[2] + [int]$Matches[4]) / 2)
                return [pscustomobject]@{ X = $x; Y = $y; Desc = $desc; Text = $text }
            }
        }
    }
    return $null
}

function Tap-Node([string]$pattern) {
    $xml = Get-UiXml
    $node = Find-Node $xml $pattern
    if ($node) {
        Invoke-Adb @('shell', "input tap $($node.X) $($node.Y)") | Out-Null
        return $true
    }
    return $false
}

function Handle-SystemVpnDialog {
    $xml = Get-UiXml
    if ($xml -match '网络连接请求|想要设置一个 VPN') {
        if (Tap-Node '确定|允许|同意') {
            Write-AutoLog '已授权系统 VPN 请求'
            Start-Sleep -Seconds 2
        }
    }
}

function Handle-Announcement {
    $xml = Get-UiXml
    if ($xml -match '服务公告') {
        if (Tap-Node '今日不再提示') {
            Write-AutoLog '已关闭服务公告（今日不再提示）'
        } elseif (Tap-Node '关闭') {
            Write-AutoLog '已关闭服务公告'
        }
        Start-Sleep -Seconds 2
    }
}

function Test-AppConnectedUi {
    $xml = Get-UiXml
    return ($xml -match '已连接, 断开连接' -or $xml -match '已连接')
}

function Start-Xxyun {
    $out = Invoke-Sh 'am start -n de.vpjs.xxyun/com.follow.clash.MainActivity'
    return ($out -match 'Starting|Warning' -or $out -match 'Error' -eq $false)
}

function Connect-Xxyun {
    if (-not (Ensure-Connected)) { return $false }
    if (-not (Test-Booted)) { return $false }

    if (Test-VpnUp) {
        if (Test-AppConnectedUi) { return $true }
        # tun0 存在但 UI 未确认时也视为已连接
        return $true
    }

    for ($try = 1; $try -le 3; $try++) {
        Write-AutoLog ("尝试连接 xxYun（第 $try 次）")
        $null = Start-Xxyun
        Start-Sleep -Seconds 5
        Handle-Announcement
        Handle-SystemVpnDialog

        $xml = Get-UiXml
        if ($xml -match '已连接, 断开连接') {
            Write-AutoLog 'xxYun 已连接'
            return $true
        }
        if (Tap-Node '未连接') {
            Start-Sleep -Seconds 8
            Handle-SystemVpnDialog
            if (Test-VpnUp) {
                Write-AutoLog 'xxYun 已连接（tun0 已建立）'
                return $true
            }
            if (Test-AppConnectedUi) {
                Write-AutoLog 'xxYun 已连接（界面已确认）'
                return $true
            }
        } else {
            Write-AutoLog '没找到连接按钮，稍后重试'
        }
        Start-Sleep -Seconds 5
    }
    Write-AutoLog '连接失败（重试 3 次后仍无 tun0）'
    return $false
}

Write-AutoLog "自动连接脚本启动（实例 $Instance，Once=$Once，间隔 ${IntervalSec}s）"
while ($true) {
    try {
        if (Test-Path $script:DisabledFlag) {
            Write-AutoLog '检测到停用标记，退出'
            break
        }
        $j = Get-VmInfo
        $cond = ($null -ne $j) -and ([bool]$j.is_process_started) -and ([bool]$j.is_android_started)
        if ($cond) {
            $adbOk = Ensure-Connected
            if (-not $adbOk) { Write-AutoLog 'adb 连接失败（实例可能未就绪）' }
            elseif (-not (Test-Booted)) { Write-AutoLog '等待 Android 启动完成' }
            elseif (-not (Test-VpnUp)) {
                $null = Connect-Xxyun
            }
        }
    } catch {
        Write-AutoLog ("异常: " + $_.Exception.Message)
    }
    if ($Once) { break }
    Start-Sleep -Seconds $IntervalSec
}
Write-AutoLog '脚本退出'