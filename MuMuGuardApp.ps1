#requires -Version 5.1
<#
  MuMuGuardApp.ps1  -  MuMuGuard 看护面板 v3

  功能：
    实例监控 / 掉线检测 / 空转识别 / 健康自检 / 内存趋势
    CEF 泄漏清理 / 一键重启 / 事件筛选 / 阈值设置 / 报告导出

  工作方式：
    打开面板 -> 点「启动看护」-> 每 N 分钟自动清理一次
    点「停止看护」或关闭窗口 -> 立即停止，无后台残留
#>

Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase

# DPI 感知，避免高分屏发虚
Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public class DpiHelper {
  [DllImport("shcore.dll")] public static extern int SetProcessDpiAwareness(int value);
  [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
  public static void Enable() {
    try { SetProcessDpiAwareness(2); } catch { try { SetProcessDPIAware(); } catch { } }
  }
}
"@
try { [DpiHelper]::Enable() } catch { }

# 进程父子关系快照（Toolhelp32），比 WMI 快两个数量级
Add-Type -TypeDefinition @"
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
public class ProcSnap {
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    public struct PROCESSENTRY32W {
        public uint dwSize;
        public uint cntUsage;
        public uint th32ProcessID;
        public IntPtr th32DefaultHeapID;
        public uint th32ModuleID;
        public uint cntThreads;
        public uint th32ParentProcessID;
        public int pcPriClassBase;
        public uint dwFlags;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 260)] public string szExeFile;
    }
    [DllImport("kernel32.dll", SetLastError = true)]
    public static extern IntPtr CreateToolhelp32Snapshot(uint dwFlags, uint th32ProcessID);
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    public static extern bool Process32FirstW(IntPtr hSnapshot, ref PROCESSENTRY32W lppe);
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    public static extern bool Process32NextW(IntPtr hSnapshot, ref PROCESSENTRY32W lppe);
    [DllImport("kernel32.dll", SetLastError = true)]
    public static extern bool CloseHandle(IntPtr hObject);

    public static Dictionary<uint, uint> ParentMap() {
        var map = new Dictionary<uint, uint>();
        IntPtr snap = CreateToolhelp32Snapshot(0x2, 0);
        if (snap == (IntPtr)(-1)) { return map; }
        var pe = new PROCESSENTRY32W();
        pe.dwSize = (uint)Marshal.SizeOf(typeof(PROCESSENTRY32W));
        if (Process32FirstW(snap, ref pe)) {
            do { map[pe.th32ProcessID] = pe.th32ParentProcessID; } while (Process32NextW(snap, ref pe));
        }
        CloseHandle(snap);
        return map;
    }

    public class Entry {
        public uint Pid;
        public uint Parent;
        public string Name;
    }

    public static List<Entry> Snap() {
        var list = new List<Entry>();
        IntPtr snap = CreateToolhelp32Snapshot(0x2, 0);
        if (snap == (IntPtr)(-1)) { return list; }
        var pe = new PROCESSENTRY32W();
        pe.dwSize = (uint)Marshal.SizeOf(typeof(PROCESSENTRY32W));
        if (Process32FirstW(snap, ref pe)) {
            do {
                list.Add(new Entry { Pid = pe.th32ProcessID, Parent = pe.th32ParentProcessID, Name = pe.szExeFile });
            } while (Process32NextW(snap, ref pe));
        }
        CloseHandle(snap);
        return list;
    }
}
"@

# 轻量取内存信息，避免频繁 WMI 查询
Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public class MemInfo {
    [StructLayout(LayoutKind.Sequential)]
    public class MEMORYSTATUSEX {
        public uint dwLength;
        public uint dwMemoryLoad;
        public ulong ullTotalPhys;
        public ulong ullAvailPhys;
        public ulong ullTotalPageFile;
        public ulong ullAvailPageFile;
        public ulong ullTotalVirtual;
        public ulong ullAvailVirtual;
        public ulong ullAvailExtendedVirtual;
        public MEMORYSTATUSEX() { dwLength = (uint)Marshal.SizeOf(typeof(MEMORYSTATUSEX)); }
    }
    [DllImport("kernel32.dll", SetLastError = true)]
    public static extern bool GlobalMemoryStatusEx([In, Out] MEMORYSTATUSEX lpBuffer);
    public static ulong[] Get() {
        var m = new MEMORYSTATUSEX();
        if (!GlobalMemoryStatusEx(m)) { return new ulong[] { 0, 0, 0, 0 }; }
        return new ulong[] { m.ullTotalPhys, m.ullAvailPhys, m.ullTotalPageFile, m.ullAvailPageFile };
    }
}
"@

$ErrorActionPreference = 'Continue'

$Root     = $PSScriptRoot

# ---------------- 加载模块 ----------------
$libPath = Join-Path $Root 'lib'
foreach ($f in @('90-pure', '00-common', '15-theme', '05-instances', '10-data', '20-actions', '30-ui', '40-tray', '50-update')) {
    $p = Join-Path $libPath ($f + '.ps1')
    if (Test-Path $p) { . $p }
    else { throw "缺少模块: $p" }
}

# 数据目录：程序目录可写就放旁边，否则（如放在 Program Files）退回 LOCALAPPDATA
$DataDir = $Root
try {
    $probe = Join-Path $Root '.write_test'
    [System.IO.File]::WriteAllText($probe, 'x')
    Remove-Item $probe -Force -ErrorAction SilentlyContinue
} catch {
    $DataDir = Join-Path $env:LOCALAPPDATA 'MuMuGuard'
    if (-not (Test-Path $DataDir)) { New-Item -ItemType Directory -Path $DataDir -Force | Out-Null }
}

$LogDir   = Join-Path $DataDir 'logs'
$CfgPath  = Join-Path $DataDir 'config.json'
$TrendFile = Join-Path $DataDir 'trend.json'
$SleepFile = Join-Path $DataDir 'sleep.json'
$MuMuRoot = 'D:\Program Files\Netease\MuMu'
$AdbExe   = Join-Path $MuMuRoot 'nx_device\15.0\shell\adb.exe'
$MuMuMgr  = Join-Path $MuMuRoot 'nx_main\MuMuManager.exe'
$PkgScript = 'com.coc.zkqcode'
$PkgGame   = 'com.tencent.tmgp.supercell.clashofclans com.supercell.clashofclans'

if (-not (Test-Path $LogDir)) { New-Item -ItemType Directory -Path $LogDir -Force | Out-Null }


# 诊断日志（必须早于任何 Write-Diag 调用）
$script:diagFile = Join-Path $LogDir 'diag.log'
# ---------------- 配置 ----------------

$defaultCfg = [ordered]@{
    CefKeep      = 3
    CefStaleMin  = 10
    CefAlert     = 20
    CpuAlert     = 4.0
    LowMemMB     = 800
    GuardMinute  = 5
    GuardRunning = $false
    NemuSpinPct  = 50
    MemAlertMB   = 9216
    LogKeepDays  = 7
    # 自动恢复
    AutoRecover      = $true
    RecoverCheckSec  = 60
    RecoverFailCount = 2
    RecoverCooldown  = 10
    DetectOff        = @()
    # 升级休眠
    AutoSleep        = $false
    SleepLeadMin     = 10
    SleepMaxHours    = 20
    # 路径与包名（可在设置里改）
    MuMuRoot     = 'D:\Program Files\Netease\MuMu'
    PkgScript    = 'com.coc.zkqcode'
    PkgGame      = 'com.tencent.tmgp.supercell.clashofclans com.supercell.clashofclans'
    # 开机自启（可选，默认关闭）
    StartWithWindows = $false
    # 主题：auto / dark / light
    Theme        = 'auto'
    # 实例别名（编号 -> 自定义名称）
    Aliases      = @{}
    # 更新
    UpdateRepo       = 'suuk324/MuMuGuard'
    UpdateMirror     = ''
    AutoUpdateCheck  = $true
    LastUpdateCheck  = ''
    SkippedVersion   = ''
    WindowLeft   = $null
    WindowTop    = $null
}

$script:cfg = @{}
foreach ($k in $defaultCfg.Keys) { $script:cfg[$k] = $defaultCfg[$k] }

if (Test-Path $CfgPath) {
    try {
        $saved = Get-Content $CfgPath -Raw -Encoding UTF8 | ConvertFrom-Json
        foreach ($p in $saved.PSObject.Properties) {
            if ($script:cfg.ContainsKey($p.Name)) { $script:cfg[$p.Name] = $p.Value }
        }
    } catch { }
}

# 用配置覆盖路径与包名
if ($script:cfg.MuMuRoot) {
    $MuMuRoot = [string]$script:cfg.MuMuRoot
    if ($script:cfg.PkgScript) { $PkgScript = [string]$script:cfg.PkgScript }
    if ($script:cfg.PkgGame)   { $PkgGame   = [string]$script:cfg.PkgGame }
}

# ---------------- 实例发现 ----------------
# 从 install_config.json 定位 adb / manager（自动适配 MuMu 12 / 15）
# 版本号
$script:appVersion = '1.1.1'
$verFile = Join-Path $Root 'VERSION'
if (Test-Path $verFile) { $script:appVersion = (Get-Content $verFile -Raw).Trim() }

$script:muInfo = Get-MuMuInstallInfo -Root $MuMuRoot
if ($script:muInfo.Found) {
    $AdbExe  = $script:muInfo.AdbExe
    $MuMuMgr = $script:muInfo.ManagerExe
} else {
    $AdbExe  = Join-Path $MuMuRoot 'nx_device\15.0\shell\adb.exe'
    $MuMuMgr = Join-Path $MuMuRoot 'nx_main\MuMuManager.exe'
    Write-Diag "未能自动定位 MuMu 组件，回退到默认路径：$AdbExe"
}

# 扫描真实存在的实例（名称/内存/CPU/端口）
$script:instances = @(Get-InstanceConfigs -VmsDir $script:muInfo.VmsDir)
$script:instanceMap = @{}
foreach ($ic in $script:instances) { $script:instanceMap["$($ic.Index)"] = $ic }
Write-Diag ("发现 {0} 个实例：{1}" -f $script:instances.Count, (($script:instances | ForEach-Object { "$($_.Index)[$($_.Name)]" }) -join ', '))

# ---------------- 诊断日志 ----------------


# ---------------- 单实例 ----------------
Add-Type -AssemblyName Microsoft.VisualBasic -ErrorAction SilentlyContinue
$script:mutex = New-Object System.Threading.Mutex($false, 'Local\MuMuGuardPanel')
if (-not $script:mutex.WaitOne(0)) {
    try {
        $existing = Get-Process | Where-Object { $_.MainWindowTitle -eq 'MuMuGuard' } | Select-Object -First 1
        if ($existing) { [Microsoft.VisualBasic.Interaction]::AppActivate($existing.Id) | Out-Null }
    } catch { }
    exit
}


# ---------------- 状态 ----------------

$script:prevCpu      = @{}
$script:guardRunning = $false
$script:lastClean    = $null
$script:logClean     = 0
$script:logKilled    = 0
$script:logAlert     = 0
$script:totalMB      = 16384
$script:cardMap      = @{}
$script:placeholder  = $null
$script:lastEventSig = ''
$script:eventFilter  = 'all'
$script:trend        = New-Object System.Collections.ArrayList
$script:tickCount    = 0
$script:lowestAvail  = [int]::MaxValue
$script:overMem      = @{}
$script:memAlertAt   = @{}
$script:healthRows   = @()
$script:logCache     = $null
$script:rootWarned   = $false
$script:listRows     = @{}
$script:shortLabels  = @{}
$script:compactMode  = 'rings'
$script:alertCache   = $null
$script:lastWakeFail = ''
$script:pfCache      = $null
$script:compCache    = $null
$script:instCache    = $null
$script:indexCache   = @{}
$script:lastFilled   = -1
$script:lastGuardState = $null
# 自动恢复：每实例连续失败计数 / 上次恢复时间 / 正在恢复中
$script:failCount   = @{}
$script:lastRecover = @{}
$script:recovering  = @{}

$script:adbData = [hashtable]::Synchronized(@{})
$script:adbSync = [hashtable]::Synchronized(@{ Stop = $false; Data = @{}; Idle = $false; RootOk = $true })

try {
    $osInfo = Get-CimInstance Win32_OperatingSystem -ErrorAction Stop
    $script:totalMB = [int]($osInfo.TotalVisibleMemorySize / 1KB)
} catch { }


# ---------------- 日志 ----------------





# ---------------- 数据 ----------------




$script:lastInstances = @()

# ---------------- 清理 ----------------


# ---------------- 后台 adb 采集 ----------------

$workerScript = {
    param($sync, $mumuRoot, $adbExe, $pkgScript, $pkgGame, $purePath, $deviceList, $batchSize)

    # 载入纯函数，保证与主程序逻辑一致
    if ($purePath -and (Test-Path $purePath)) { . $purePath }

    function Convert-TimePlus([string]$s) {
        if ($s -match '(\d+):(\d+):(\d+)') { return ([int]$Matches[1] * 3600 + [int]$Matches[2] * 60 + [int]$Matches[3]) }
        if ($s -match '(\d+):(\d+)')        { return ([int]$Matches[1] * 60 + [int]$Matches[2]) }
        return $null
    }

    # 从 memory.json 里取「下一次升级」信息（base64 传入，避开编码问题）
    function Get-UpgradeInfo([string]$b64) {
        if (-not $b64) { return $null }
        try {
            $bytes = [Convert]::FromBase64String(($b64 -replace '\s', ''))
            $memText = [System.Text.Encoding]::UTF8.GetString($bytes)
        } catch { return $null }
        return Get-UpgradeFromMemoryJson -Text $memText
    }

    # 判断脚本是否只是在等升级完成（日志里只剩升级倒计时）
    function Test-Waiting([string]$b64) {
        if (-not $b64) { return $null }
        try {
            $bytes = [Convert]::FromBase64String(($b64 -replace '\s', ''))
            $text = [System.Text.Encoding]::UTF8.GetString($bytes)
        } catch { return $null }
        if (-not $text) { return $null }
        $lines = @($text -split "`n")
        $r = Test-IsWaitingLog -Lines $lines
        # 保留原语义：不足 5 条业务日志视为"未知"
        $biz = @($lines | Where-Object { $_ -match '账号\d+[，,]' })
        if ($biz.Count -lt 5) { return $null }
        return $r
    }

    $prevNemu = @{}
    $prevTime = $null
    $connected = @{}
    $cycle = 0
    $memCache = @{}
    $waitCache = @{}
    $schedCache = @{}
    $lastData = @{}
    $cursor = 0

    while (-not $sync.Stop) {
        try {
            $cycle++
            $now  = Get-Date
            $out  = @{}
            $span = 30.0
            if ($prevTime) {
                $d = ($now - $prevTime).TotalSeconds
                if ($d -gt 1) { $span = $d }
            }

            # 升级信息变化慢，每 3 轮（约 90 秒）读一次
            $readMem = ($cycle % 3 -eq 1)

            # 错峰轮询：每轮只查一批实例，避免多开时采集开销过大
            $all = @($deviceList)
            $batch = [int]$batchSize
            if ($batch -lt 1) { $batch = 2 }
            if ($all.Count -eq 0) {
                $sync.Data = @{}
                $sync.Heartbeat = $now
                Start-Sleep -Seconds 15
                continue
            }
            $take = [math]::Min($batch, $all.Count)
            $slice = @()
            for ($k = 0; $k -lt $take; $k++) { $slice += $all[(($cursor + $k) % $all.Count)] }
            $cursor = ($cursor + $take) % $all.Count

            foreach ($dev in $slice) {
                $i = "$($dev.Index)"
                $port = $dev.Port
                if (-not $port) { continue }

                $serial = "127.0.0.1:$port"
                if (-not $connected.ContainsKey($serial)) {
                    try { & $adbExe connect $serial *> $null } catch { }
                    $connected[$serial] = $true
                }

                $online = $null
                $game   = $null
                $cur    = $null

                # 一次 shell 调用同时取「紫孔雀进程」「游戏进程」「nemuinit 时间」
                $cmd = "echo READY; echo SCRIPT; pidof $pkgScript; echo GAME; pidof $pkgGame; echo SEP; ps -A -o TIME+,NAME 2>/dev/null | grep nemuinit"
                if ($readMem) {
                    $cmd += "; echo MEM; su -c 'base64 /storage/emulated/0/zkqFiles/memory.json 2>/dev/null'"
                    $cmd += "; echo LOG; su -c 'tail -20 /data/data/$pkgScript/files/logs/info.log 2>/dev/null | base64'"
                    $cmd += "; echo SCH; su -c 'grep -o `"upgrade_time_scheduling[^,]*`" /storage/emulated/0/zkqFiles/zkq_config.json 2>/dev/null'"
                }
                $res = ''
                try { $res = ((& $adbExe -s $serial shell $cmd 2>$null) -join "`n") } catch { }

                if ($res -notmatch 'READY') {
                    try { & $adbExe connect $serial *> $null } catch { }
                    Start-Sleep -Milliseconds 400
                    try { $res = ((& $adbExe -s $serial shell $cmd 2>$null) -join "`n") } catch { }
                }

                if ($res -match 'READY') {
                    $online = $true
                    # 切成 SCRIPT / GAME / SEP 三段
                    $scriptPart = ''
                    $gamePart   = ''
                    $psPart     = ''
                    if ($res -match '(?s)SCRIPT\s*(.*?)\s*GAME') { $scriptPart = $Matches[1] }
                    if ($res -match '(?s)GAME\s*(.*?)\s*SEP')   { $gamePart   = $Matches[1] }
                    if ($res -match '(?s)SEP\s*(.*)$')          { $psPart     = $Matches[1] }

                    $scriptOn = ($scriptPart -match '\d{2,}')
                    $gameOn   = ($gamePart   -match '\d{2,}')

                    # nemuinit 时间在 SEP 段，升级信息在 MEM 段
                    if ($res -match '(?s)SEP\s*(.*?)(?:MEM|$)') { $psPart = $Matches[1] }
                    if ($psPart -match '(\d+(?::\d+){1,2})') { $cur = Convert-TimePlus $Matches[1] }

                    if ($readMem) {
                        $b64 = ''
                        if ($res -match '(?s)MEM\s*(.*?)(?:LOG|$)') { $b64 = $Matches[1] }
                        $memCache[$i] = Get-UpgradeInfo $b64
                        if ($b64 -and $b64.Trim().Length -gt 20) { $sync.RootOk = $true }
                        elseif ($online -eq $true -and $scriptOn -eq $true) { $sync.RootOk = $false }

                        # 判断脚本是否只是在等升级（日志里只剩升级倒计时）
                        $logB64 = ''
                        if ($res -match '(?s)LOG\s*(.*?)(?:SCH|$)') { $logB64 = $Matches[1] }
                        $waitCache[$i] = Test-Waiting $logB64

                        # 升级时间上号是否开启
                        $schedCache[$i] = ($res -match 'upgrade_time_scheduling"\s*:\s*"1"')
                    }
                } else {
                    $online = $false
                    $scriptOn = $null
                    $gameOn   = $null
                }

                $spin = $null
                if ($null -ne $cur -and $prevNemu.ContainsKey($i)) {
                    $delta = $cur - $prevNemu[$i]
                    if ($delta -ge 0) { $spin = [math]::Round($delta / $span * 100, 1) }
                }
                if ($null -ne $cur) { $prevNemu[$i] = $cur }

                $out["$i"] = [pscustomobject]@{
                    Online  = $online
                    Script  = $scriptOn
                    Game    = $gameOn
                    Spin    = $spin
                    Upgrade = $(if ($memCache.ContainsKey($i)) { $memCache[$i] } else { $null })
                    Waiting = $(if ($waitCache.ContainsKey($i)) { $waitCache[$i] } else { $null })
                    Sched   = $(if ($schedCache.ContainsKey($i)) { $schedCache[$i] } else { $null })
                }
            }

            $prevTime = $now
            # 合并到累计数据，未轮询到的实例保留上次结果
            foreach ($k in @($out.Keys)) { $lastData[$k] = $out[$k] }
            $sync.Data = $lastData
            $sync.Heartbeat = $now
        } catch { }

        # 窗口不可见时降低采集频率，减少 adb 进程创建开销
        $idle = $false
        try { $idle = [bool]$sync.Idle } catch { }
        if ($idle) { Start-Sleep -Seconds 120 } else { Start-Sleep -Seconds 15 }
    }
}

$rs = [runspacefactory]::CreateRunspace()
$rs.ApartmentState = 'MTA'
$rs.ThreadOptions  = 'ReuseThread'
$rs.Open()
$workerPs = [powershell]::Create()
$workerPs.Runspace = $rs
# 传给采集线程的实例清单（编号 + 端口）
$devList = @($script:instances | Where-Object { $_.AdbPort -gt 0 } | ForEach-Object {
    [pscustomobject]@{ Index = $_.Index; Port = $_.AdbPort }
})
if ($devList.Count -eq 0) { $devList = @([pscustomobject]@{ Index = '1'; Port = 16416 }) }

# 每批查几个：3 个以内全查，超过就分批（每批约 15 秒，一轮覆盖全部）
$batchSize = if ($devList.Count -le 3) { $devList.Count } else { [math]::Max(2, [int][math]::Ceiling($devList.Count / 5)) }

[void]$workerPs.AddScript($workerScript).AddArgument($script:adbSync).AddArgument($MuMuRoot).AddArgument($AdbExe).AddArgument($PkgScript).AddArgument($PkgGame).AddArgument((Join-Path $Root 'lib\90-pure.ps1')).AddArgument($devList).AddArgument($batchSize)
$workerHandle = $workerPs.BeginInvoke()

# ---------------- 主界面 XAML ----------------

$xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="MuMuGuard" Width="360" Height="214"
        WindowStartupLocation="CenterScreen"
        WindowStyle="None" AllowsTransparency="True" Background="Transparent"
        ResizeMode="CanMinimize" FontFamily="Microsoft YaHei UI">

  <Window.Resources>
    <Style x:Key="Btn" TargetType="Button">
      <Setter Property="Foreground" Value="{DynamicResource T_E8EDF5}"/>
      <Setter Property="FontSize" Value="12.5"/>
      <Setter Property="FontWeight" Value="SemiBold"/>
      <Setter Property="Padding" Value="16,0"/>
      <Setter Property="Height" Value="36"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border x:Name="bd" CornerRadius="8" Background="{TemplateBinding Background}" Padding="{TemplateBinding Padding}">
              <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="bd" Property="Opacity" Value="0.86"/></Trigger>
              <Trigger Property="IsPressed" Value="True"><Setter TargetName="bd" Property="Opacity" Value="0.66"/></Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>

    <Style x:Key="Ghost" TargetType="Button">
      <Setter Property="Foreground" Value="#8A94A6"/>
      <Setter Property="FontSize" Value="12"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border x:Name="bd" CornerRadius="7" Background="#00000000" Padding="10,4">
              <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True">
                <Setter TargetName="bd" Property="Background" Value="#161C26"/>
                <Setter Property="Foreground" Value="#E6EAF2"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>

    <Style x:Key="Mini" TargetType="Button">
      <Setter Property="Foreground" Value="#8A94A6"/>
      <Setter Property="FontSize" Value="11"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border x:Name="bd" CornerRadius="6" Background="#161C26" Padding="10,4">
              <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True">
                <Setter TargetName="bd" Property="Background" Value="#1A2130"/>
                <Setter Property="Foreground" Value="#E6EAF2"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <Style TargetType="ScrollBar">
      <Setter Property="Width" Value="8"/>
      <Setter Property="Background" Value="Transparent"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="ScrollBar">
            <Grid Background="Transparent">
              <Track x:Name="PART_Track" IsDirectionReversed="True">
                <Track.Thumb>
                  <Thumb>
                    <Thumb.Template>
                      <ControlTemplate TargetType="Thumb">
                        <Border CornerRadius="4" Background="#1A2130"/>
                      </ControlTemplate>
                    </Thumb.Template>
                  </Thumb>
                </Track.Thumb>
              </Track>
            </Grid>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
  </Window.Resources>

  <Border CornerRadius="16" Background="#0A0D14" BorderBrush="#161C26" BorderThickness="1">
    <Border.Effect><DropShadowEffect BlurRadius="30" ShadowDepth="0" Opacity="0.65" Color="Black"/></Border.Effect>

    <Grid>
      <Grid.RowDefinitions>
        <RowDefinition Height="72"/>
        <RowDefinition Height="*"/>
        <RowDefinition Height="96"/>
      </Grid.RowDefinitions>

      <!-- 顶栏 -->
      <Grid x:Name="Header" Grid.Row="0" Background="Transparent">
        <StackPanel Orientation="Horizontal" Margin="24,0,0,0" VerticalAlignment="Center">
          <Border x:Name="LogoBox" Width="40" Height="40" CornerRadius="11" Background="#00000000">
            <Image x:Name="LogoImg" Stretch="Uniform"/>
          </Border>
          <StackPanel Margin="12,0,0,0" VerticalAlignment="Center">
            <StackPanel Orientation="Horizontal"><TextBlock Text="MuMuGuard" Foreground="#E6EAF2" FontSize="17" FontWeight="Bold"/><TextBlock x:Name="TxtVersion" Text="" Foreground="#4B566B" FontSize="10" VerticalAlignment="Bottom" Margin="6,0,0,3"/></StackPanel>
            <TextBlock Text="模拟器看护面板" Foreground="#8A94A6" FontSize="10.5" Margin="0,2,0,0"/>
          </StackPanel>
        </StackPanel>

        <StackPanel Orientation="Horizontal" HorizontalAlignment="Right" VerticalAlignment="Center" Margin="0,0,12,0">
          <Button x:Name="BtnCompact" Content="概要" Style="{StaticResource Mini}" Margin="0,0,10,0" VerticalAlignment="Center"/>
          <Border x:Name="StatusPill" CornerRadius="12" Padding="14,7" Background="#161C26" VerticalAlignment="Center">
            <StackPanel Orientation="Horizontal">
              <Ellipse x:Name="StatusDot" Width="8" Height="8" Fill="#8A94A6" VerticalAlignment="Center"/>
              <TextBlock x:Name="TxtStatus" Text="初始化" Foreground="#8A94A6" FontSize="12"
                         FontWeight="Bold" Margin="8,0,0,0"/>
            </StackPanel>
          </Border>
          <Button x:Name="BtnMin" Content="&#x2014;" Width="34" Height="34" Margin="10,0,0,0" Style="{StaticResource Ghost}"/>
          <Button x:Name="BtnClose" Content="&#x2715;" Width="34" Height="34" Style="{StaticResource Ghost}"/>
        </StackPanel>
      </Grid>

      <!-- 主体 -->
      <Grid Grid.Row="1" Margin="20,0,20,0">
        <Grid.ColumnDefinitions>
          <ColumnDefinition Width="1.32*"/>
          <ColumnDefinition Width="16"/>
          <ColumnDefinition Width="1*"/>
        </Grid.ColumnDefinitions>

        <!-- 左：实例 + 事件 -->
        <Grid Grid.Column="0">
          <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="*"/>
          </Grid.RowDefinitions>

          <StackPanel x:Name="PnlInstances" Grid.Row="0"/>

          <Border Grid.Row="1" CornerRadius="12" Background="#0F141C" BorderBrush="#161C26"
                  BorderThickness="1" Padding="16,14" Margin="0,4,0,0">
            <Grid>
              <Grid.RowDefinitions>
                <RowDefinition Height="Auto"/>
                <RowDefinition Height="*"/>
              </Grid.RowDefinitions>

              <DockPanel Grid.Row="0" Margin="0,0,0,8">
                <TextBlock Text="事件" Foreground="#8A94A6" FontSize="10.5" VerticalAlignment="Center"/>
                <StackPanel Orientation="Horizontal" HorizontalAlignment="Right">
                  <Button x:Name="BtnAll" Content="全部" Style="{StaticResource Mini}" Margin="0,0,6,0"/>
                  <Button x:Name="BtnWarn" Content="仅告警" Style="{StaticResource Mini}"/>
                </StackPanel>
              </DockPanel>

              <ScrollViewer Grid.Row="1" VerticalScrollBarVisibility="Auto" Padding="0,0,6,0">
                <StackPanel x:Name="PnlEvents"/>
              </ScrollViewer>
            </Grid>
          </Border>
        </Grid>

        <!-- 右：内存 + 健康 + 趋势 -->
        <Grid Grid.Column="2">
          <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="*"/>
          </Grid.RowDefinitions>

          <Border Grid.Row="0" CornerRadius="12" Background="#0F141C" BorderBrush="#161C26"
                  BorderThickness="1" Padding="18,16" Margin="0,0,0,12">
            <StackPanel>
              <TextBlock Text="主机内存" Foreground="#8A94A6" FontSize="10.5"/>
              <StackPanel Orientation="Horizontal" Margin="0,3,0,0">
                <TextBlock x:Name="TxtAvail" Text="--" Foreground="#E6EAF2" FontSize="25" FontWeight="Bold"
                           FontFamily="Consolas"/>
                <TextBlock x:Name="TxtTotal" Text="" Foreground="#8A94A6" FontSize="11"
                           VerticalAlignment="Bottom" Margin="8,0,0,5"/>
              </StackPanel>

              <Grid x:Name="MemBarHost" Height="8" Margin="0,11,0,0">
                <Border CornerRadius="4" Background="#161C26"/>
                <Border x:Name="MemBarFill" CornerRadius="4" Background="#3DDC84" HorizontalAlignment="Left" Width="0"/>
              </Grid>
              <Grid Margin="0,4,0,0">
                <Grid.ColumnDefinitions>
                  <ColumnDefinition Width="*"/>
                  <ColumnDefinition Width="*"/>
                </Grid.ColumnDefinitions>
                <TextBlock Grid.Column="0" Text="0" Foreground="#414B5E" FontSize="9.5"/>
                <TextBlock Grid.Column="1" Text="16 GB" Foreground="#414B5E" FontSize="9.5" HorizontalAlignment="Right"/>
              </Grid>

              <Grid Margin="0,12,0,0">
                <Grid.ColumnDefinitions>
                  <ColumnDefinition Width="*"/>
                  <ColumnDefinition Width="*"/>
                </Grid.ColumnDefinitions>
                <StackPanel Grid.Column="0">
                  <TextBlock Text="提交内存" Foreground="#8A94A6" FontSize="10"/>
                  <TextBlock x:Name="TxtCommit" Text="--" Foreground="#E6EAF2" FontSize="14"
                             FontWeight="SemiBold" FontFamily="Consolas" Margin="0,2,0,0"/>
                </StackPanel>
                <StackPanel Grid.Column="1">
                  <TextBlock Text="页面文件" Foreground="#8A94A6" FontSize="10"/>
                  <TextBlock x:Name="TxtPage" Text="--" Foreground="#E6EAF2" FontSize="14"
                             FontWeight="SemiBold" FontFamily="Consolas" Margin="0,2,0,0"/>
                </StackPanel>
              </Grid>
            </StackPanel>
          </Border>

          <Border Grid.Row="1" CornerRadius="12" Background="#0F141C" BorderBrush="#161C26"
                  BorderThickness="1" Padding="18,14" Margin="0,0,0,12">
            <StackPanel>
              <TextBlock Text="健康检查" Foreground="#8A94A6" FontSize="10.5" Margin="0,0,0,8"/>
              <StackPanel x:Name="PnlHealth"/>
            </StackPanel>
          </Border>

          <Border Grid.Row="2" CornerRadius="12" Background="#0F141C" BorderBrush="#161C26"
                  BorderThickness="1" Padding="18,14">
            <Grid>
              <Grid.RowDefinitions>
                <RowDefinition Height="Auto"/>
                <RowDefinition Height="*"/>
              </Grid.RowDefinitions>
              <DockPanel Grid.Row="0" Margin="0,0,0,6">
                <TextBlock Text="可用内存趋势 · 1 小时" Foreground="#8A94A6" FontSize="10.5"/>
                <TextBlock x:Name="TxtTrendMin" Text="" Foreground="#414B5E" FontSize="10" HorizontalAlignment="Right"/>
              </DockPanel>
              <Grid Grid.Row="1">
                <Canvas x:Name="TrendCanvas" ClipToBounds="True">
                  <Polyline x:Name="TrendLine" Stroke="#3DDC84" StrokeThickness="1.6"/>
                </Canvas>
                <TextBlock x:Name="TxtTrendHint" Text="采样中 · 每 30 秒一个点"
                           Foreground="#414B5E" FontSize="10.5"
                           HorizontalAlignment="Center" VerticalAlignment="Center"/>
              </Grid>
            </Grid>
          </Border>
        </Grid>
      </Grid>

      <!-- 底部 -->
      <Grid Grid.Row="2" Margin="20,0,20,0">
        <Grid.RowDefinitions>
          <RowDefinition Height="Auto"/>
          <RowDefinition Height="*"/>
        </Grid.RowDefinitions>

        <TextBlock x:Name="TxtInfo" Grid.Row="0" Text="" Foreground="#8A94A6" FontSize="10.5" Margin="2,0,0,0"/>

        <DockPanel Grid.Row="1" VerticalAlignment="Center" Margin="0,0,0,4">
          <StackPanel Orientation="Horizontal" DockPanel.Dock="Left">
            <Button x:Name="BtnGuard" Content="启动看护" Width="112" Style="{StaticResource Btn}" Background="#E8EDF5"/>
            <Button x:Name="BtnSleep" Content="休眠 开" Width="84" Margin="10,0,0,0" Style="{StaticResource Btn}" Background="#141A24" ToolTip="升级等待时自动关闭模拟器省内存"/>
            <Button x:Name="BtnClean" Content="立即清理" Width="102" Margin="10,0,0,0" Style="{StaticResource Btn}" Background="#141A24"/>
            <Button x:Name="BtnLog" Content="打开日志" Width="94" Margin="10,0,0,0" Style="{StaticResource Btn}" Background="#161C26"/>
            <Button x:Name="BtnAllRestart" Content="全部重启" Width="86" Margin="10,0,0,0" Style="{StaticResource Btn}" Background="#141A24" Visibility="Collapsed" ToolTip="重启所有运行中的实例"/>
            <Button x:Name="BtnAllSleep" Content="全部休眠" Width="86" Margin="10,0,0,0" Style="{StaticResource Btn}" Background="#141A24" Visibility="Collapsed" ToolTip="关闭所有可休眠的实例"/>
            <Button x:Name="BtnAllWake" Content="全部唤醒" Width="86" Margin="10,0,0,0" Style="{StaticResource Btn}" Background="#141A24" Visibility="Collapsed" ToolTip="唤醒所有休眠中的实例"/>
          </StackPanel>
          <StackPanel Orientation="Horizontal" DockPanel.Dock="Right" HorizontalAlignment="Right" VerticalAlignment="Center">
            <Button x:Name="BtnExport" Content="导出报告" Style="{StaticResource Mini}" Margin="0,0,8,0" MinWidth="76" ToolTip="导出当前状态到文本报告"/>
            <Button x:Name="BtnUpdate" Content="检查更新" Style="{StaticResource Mini}" Margin="0,0,8,0" MinWidth="76" ToolTip="从 GitHub 检查是否有新版本"/>
            <Button x:Name="BtnSettings" Content="设置" Style="{StaticResource Mini}" MinWidth="56" ToolTip="阈值与路径设置"/>
          </StackPanel>
        </DockPanel>
      </Grid>
    </Grid>
  </Border>
</Window>
'@

$xaml = Convert-XamlTheme $xaml
$win = [Windows.Markup.XamlReader]::Parse($xaml)

# 主题资源：必须在界面显示前设好，DynamicResource 才能取到
Set-ThemeResources $win (Get-ActiveTheme)

# 独立的任务栏身份：否则会并入 powershell.exe 分组，显示 PowerShell 的图标
if (-not ('AppId' -as [type])) {
    try {
        Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public static class AppId {
    [DllImport("shell32.dll", CharSet = CharSet.Unicode, PreserveSig = true)]
    private static extern int SetCurrentProcessExplicitAppUserModelID(string appId);
    public static void Set(string id) { SetCurrentProcessExplicitAppUserModelID(id); }
}
"@
    } catch { }
}
try { [AppId]::Set('Titen.MuMuGuard.Panel') } catch { }

# 窗口 / 任务栏图标
try {
    $icoPath = Join-Path $Root 'MuMuGuard.ico'
    if (Test-Path $icoPath) {
        $win.Icon = [System.Windows.Media.Imaging.BitmapFrame]::Create([Uri]$icoPath)
    }
        $logoImg = $win.FindName('LogoImg')
        if ($logoImg) {
            # 优先用 256px PNG，缩小后更清晰
            $pngPath = Join-Path $Root 'icon.png'
            $src = if (Test-Path $pngPath) { $pngPath } else { $icoPath }
            try { $logoImg.Source = [System.Windows.Media.Imaging.BitmapFrame]::Create([Uri]$src) } catch { }
            try { [System.Windows.Media.RenderOptions]::SetBitmapScalingMode($logoImg, 'HighQuality') } catch { }
        }
} catch { }

$header     = $win.FindName('Header')
$statusPill = $win.FindName('StatusPill')
$statusDot  = $win.FindName('StatusDot')
$txtStatus  = $win.FindName('TxtStatus')
$pnlCards   = $win.FindName('PnlInstances')
$pnlEvents  = $win.FindName('PnlEvents')
$pnlHealth  = $win.FindName('PnlHealth')
$txtAvail   = $win.FindName('TxtAvail')
$txtTotal   = $win.FindName('TxtTotal')
$memHost    = $win.FindName('MemBarHost')
$memFill    = $win.FindName('MemBarFill')
$txtCommit  = $win.FindName('TxtCommit')
$txtPage    = $win.FindName('TxtPage')
$txtInfo    = $win.FindName('TxtInfo')
$txtVersion = $win.FindName('TxtVersion')
$btnAllRestart = $win.FindName('BtnAllRestart')
$btnAllSleep   = $win.FindName('BtnAllSleep')
$btnAllWake    = $win.FindName('BtnAllWake')
$trendCanvas = $win.FindName('TrendCanvas')
$trendLine  = $win.FindName('TrendLine')
$txtTrendMin = $win.FindName('TxtTrendMin')
$txtTrendHint = $win.FindName('TxtTrendHint')
$btnGuard   = $win.FindName('BtnGuard')
$btnClean   = $win.FindName('BtnClean')
$btnLog     = $win.FindName('BtnLog')
$btnExport  = $win.FindName('BtnExport')
$btnSettings = $win.FindName('BtnSettings')
$btnUpdate   = $win.FindName('BtnUpdate')
$btnSleep    = $win.FindName('BtnSleep')
$btnAll     = $win.FindName('BtnAll')
$btnWarn    = $win.FindName('BtnWarn')
$btnMin     = $win.FindName('BtnMin')
$btnCompact = $win.FindName('BtnCompact')
$btnClose   = $win.FindName('BtnClose')

$txtTotal.Text = ('/ {0:N0} MB' -f $script:totalMB)

# ---------------- 紧凑视图（默认） ----------------

$compactXaml = @'
<Border xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        CornerRadius="14" Background="#0A0D14" BorderBrush="#161C26" BorderThickness="1">
  <Border.Effect><DropShadowEffect BlurRadius="24" ShadowDepth="0" Opacity="0.65" Color="Black"/></Border.Effect>
  <Border.Resources>
    <Style x:Key="CplPrimary" TargetType="Button">
      <Setter Property="Foreground" Value="#0A0D14"/>
      <Setter Property="FontSize" Value="11"/>
      <Setter Property="FontWeight" Value="Bold"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border x:Name="bd" CornerRadius="6" Background="{TemplateBinding Background}">
              <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="bd" Property="Opacity" Value="0.88"/></Trigger>
              <Trigger Property="IsPressed" Value="True"><Setter TargetName="bd" Property="Opacity" Value="0.7"/></Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <Style x:Key="CplSecondary" TargetType="Button">
      <Setter Property="Foreground" Value="#8A94A6"/>
      <Setter Property="FontSize" Value="11"/>
      <Setter Property="FontWeight" Value="Bold"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border x:Name="bd" CornerRadius="6" Background="{TemplateBinding Background}">
              <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True">
                <Setter TargetName="bd" Property="Background" Value="#1A2130"/>
                <Setter Property="Foreground" Value="#E6EAF2"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <Style x:Key="CplGhost" TargetType="Button">
      <Setter Property="Foreground" Value="#414B5E"/>
      <Setter Property="FontSize" Value="10"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border x:Name="bd" CornerRadius="5" Background="#00000000">
              <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True">
                <Setter TargetName="bd" Property="Background" Value="#151B26"/>
                <Setter Property="Foreground" Value="#E6EAF2"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
  </Border.Resources>

  <Grid Margin="18,10,18,10">
    <Grid.RowDefinitions>
      <RowDefinition Height="18"/>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="0"/>
      <RowDefinition Height="Auto"/>
    </Grid.RowDefinitions>

    <!-- 顶栏 -->
    <DockPanel x:Name="CmpHeader" Grid.Row="0" Background="Transparent">
      <StackPanel Orientation="Horizontal" DockPanel.Dock="Right" VerticalAlignment="Center">
        <Ellipse x:Name="CmpGuardDot" Width="5" Height="5" Fill="#414B5E" VerticalAlignment="Center"/>
        <TextBlock x:Name="CmpGuardText" Text="已停止" Foreground="#414B5E" FontSize="8.5"
                   Margin="5,0,10,0" VerticalAlignment="Center"/>
        <Button x:Name="CmpMin" Content="&#x2014;" Width="18" Height="18" Style="{StaticResource CplGhost}"/>
        <Button x:Name="CmpClose" Content="&#x2715;" Width="18" Height="18" Style="{StaticResource CplGhost}"/>
      </StackPanel>
      <TextBlock Text="MuMuGuard" Foreground="#414B5E" FontSize="9" FontWeight="Bold"
                 VerticalAlignment="Center"/>
    </DockPanel>

    <!-- 实例区：≤5 个用环，>5 个自动切列表 -->
    <Grid x:Name="CmpRingsHost" Grid.Row="1" Margin="16,8,16,0">
      <StackPanel x:Name="CmpRings" Orientation="Horizontal"
                  HorizontalAlignment="Center" VerticalAlignment="Center"/>
      <StackPanel x:Name="CmpList" Visibility="Collapsed"/>
    </Grid>

    <!-- 内存标题 -->
    <DockPanel Grid.Row="2" Margin="0,10,0,0">
      <TextBlock Text="内存" Foreground="#414B5E" FontSize="9" VerticalAlignment="Center"/>
      <TextBlock x:Name="CmpMemText" Text="" Foreground="#414B5E" FontSize="8.5"
                 HorizontalAlignment="Right" VerticalAlignment="Center"/>
    </DockPanel>

    <!-- 16 格 -->
    <StackPanel x:Name="CmpCells" Grid.Row="3" Orientation="Horizontal" Margin="0,6,0,0" Height="14"/>
<!-- 按钮 -->
    <DockPanel Grid.Row="7" Margin="0,10,0,0">
      <Button x:Name="CmpDetailBtn" DockPanel.Dock="Right" Content="详情" Width="104" Height="27"
              Style="{StaticResource CplSecondary}" Background="#141A24"/>
      <Button x:Name="CmpGuardBtn" Content="启动看护" Height="27" Margin="0,0,10,0"
              Style="{StaticResource CplPrimary}" Background="#E8EDF5"/>
    </DockPanel>
  </Grid>
</Border>
'@

$compactXaml = Convert-XamlTheme $compactXaml
$compact = [Windows.Markup.XamlReader]::Parse($compactXaml)
$script:detailContent = $win.Content
$script:viewMode = 'compact'
$script:cmpMap = @{}
$script:cellMap = @()

$cmpHeader    = $compact.FindName('CmpHeader')
$cmpGuardDot  = $compact.FindName('CmpGuardDot')
$cmpGuardText = $compact.FindName('CmpGuardText')
$cmpMin       = $compact.FindName('CmpMin')
$cmpClose     = $compact.FindName('CmpClose')
$cmpRings     = $compact.FindName('CmpRings')
$cmpList      = $compact.FindName('CmpList')
$cmpRingsHost = $compact.FindName('CmpRingsHost')
$cmpMemText   = $compact.FindName('CmpMemText')
$cmpCells     = $compact.FindName('CmpCells')
$cmpGuardBtn  = $compact.FindName('CmpGuardBtn')
$cmpDetailBtn = $compact.FindName('CmpDetailBtn')

$RingSize   = 87
$RingRadius = 38.5
$RingStroke = 10





# ---------------- 实例卡片 ----------------




# ---------------- 升级休眠 ----------------




# 面板启动时补唤醒：处理"电脑关机/崩溃期间错过唤醒时间"的情况


# ---------------- 自动恢复 ----------------




# ---------------- 事件 ----------------


# ---------------- 健康 ----------------


# ---------------- 趋势 ----------------





# ---------------- 刷新 ----------------


# ---------------- 设置对话框 ----------------

$settingsXaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="设置" Width="420" Height="530"
        WindowStartupLocation="CenterOwner"
        WindowStyle="None" AllowsTransparency="True" Background="Transparent"
        ResizeMode="NoResize" FontFamily="Microsoft YaHei UI">
  <Window.Resources>
    <Style x:Key="MiniBtn" TargetType="Button">
      <Setter Property="Foreground" Value="#E6EAF2"/>
      <Setter Property="FontSize" Value="12"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border CornerRadius="7" Background="{TemplateBinding Background}" Padding="10,4">
              <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
  </Window.Resources>
  <Border CornerRadius="14" Background="#0A0D14" BorderBrush="#161C26" BorderThickness="1" Padding="24">
    <Border.Effect><DropShadowEffect BlurRadius="24" ShadowDepth="0" Opacity="0.6" Color="Black"/></Border.Effect>
    <Grid>
      <Grid.RowDefinitions>
        <RowDefinition Height="Auto"/>
        <RowDefinition Height="*"/>
        <RowDefinition Height="Auto"/>
      </Grid.RowDefinitions>

      <TextBlock Grid.Row="0" Text="阈值设置" Foreground="#E6EAF2" FontSize="16" FontWeight="Bold" Margin="0,0,0,16"/>

      <StackPanel Grid.Row="1" x:Name="PnlFields"/>

      <StackPanel Grid.Row="2" Orientation="Horizontal" HorizontalAlignment="Right" Margin="0,14,0,0">
        <Button x:Name="BtnCancel" Content="取消" Width="88" Height="34" Style="{StaticResource MiniBtn}" Background="#161C26"/>
        <Button x:Name="BtnSave" Content="保存" Width="96" Height="34" Margin="8,0,0,0"
                Style="{StaticResource MiniBtn}" Background="#E8EDF5"/>
      </StackPanel>
    </Grid>
  </Border>
</Window>
'@


# ---------------- 导出报告 ----------------


# ---------------- 事件绑定 ----------------

$header.Add_MouseLeftButtonDown({ try { $win.DragMove() } catch { } })
$cmpHeader.Add_MouseLeftButtonDown({ try { $win.DragMove() } catch { } })
$cmpMin.Add_Click({ $win.WindowState = 'Minimized' })
$cmpClose.Add_Click({ Hide-Panel })
$cmpDetailBtn.Add_Click({ Set-View 'detail'; Update-Ui })

$cmpGuardBtn.Add_Click({ Set-GuardState })
$btnClose.Add_Click({ Hide-Panel })
$btnMin.Add_Click({ $win.WindowState = 'Minimized' })
$btnCompact.Add_Click({ Set-View 'compact'; Update-Ui })

$btnGuard.Add_Click({ Set-GuardState })

$btnClean.Add_Click({ [void](Invoke-GuardCleanup); Update-Ui })
$btnLog.Add_Click({ if (Test-Path $LogDir) { Start-Process explorer.exe -ArgumentList $LogDir } })
$btnExport.Add_Click({ Export-Report })
$btnSettings.Add_Click({ Show-Settings })
$btnUpdate.Add_Click({ Invoke-UpdateCheckUI -Silent $false })

$btnAllRestart.Add_Click({
    $n = @($script:lastInstances | Where-Object { $_.Index -ne '-' }).Count
    if ($n -eq 0) { $txtInfo.Text = '没有运行中的实例'; return }
    $res = [System.Windows.MessageBox]::Show("重启全部 $n 个实例？`n`n每个实例都会断线重登，过程约 1-2 分钟。", 'MuMuGuard', 'YesNo', 'Warning')
    if ($res -ne 'Yes') { return }
    $c = Invoke-BatchRestart
    $txtInfo.Text = "已开始重启 $c 个实例"
})

$btnAllSleep.Add_Click({
    $res = [System.Windows.MessageBox]::Show(
        "休眠所有可休眠的实例？`n`n只有「有升级完成时间」的实例能休眠，其余会跳过。`n休眠后会在升级完成前自动唤醒。",
        'MuMuGuard', 'YesNo', 'Question')
    if ($res -ne 'Yes') { return }
    $r = Invoke-BatchSleep
    $txtInfo.Text = ('已休眠 {0} 个，跳过 {1} 个（无升级数据或时间太近）' -f $r.Slept, $r.Skipped)
    Update-Ui
})

$btnAllWake.Add_Click({
    $c = @(Get-SleepList).Count
    if ($c -eq 0) { $txtInfo.Text = '没有处于休眠的实例'; return }
    $res = [System.Windows.MessageBox]::Show("唤醒全部 $c 个休眠中的实例？", 'MuMuGuard', 'YesNo', 'Question')
    if ($res -ne 'Yes') { return }
    $n = Invoke-BatchWake
    $txtInfo.Text = "正在唤醒 $n 个实例"
    Update-Ui
})

$btnSleep.Add_Click({
    $script:cfg.AutoSleep = -not ([bool]$script:cfg.AutoSleep)
    Save-Config
    Update-SleepButton
    Update-Ui
})


$btnAll.Add_Click({
    $script:eventFilter = 'all'
    $btnAll.Foreground = Brush '#E6EAF2'
    $btnWarn.Foreground = Brush '#8A94A6'
    $script:lastEventSig = ''
    Sync-Events
})
$btnWarn.Add_Click({
    $script:eventFilter = 'warn'
    $btnWarn.Foreground = Brush '#F5A524'
    $btnAll.Foreground = Brush '#8A94A6'
    $script:lastEventSig = ''
    Sync-Events
})

# ---------------- 开机自启 ----------------

$script:runKey  = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
$script:runName = 'MuMuGuard'



# ---------------- 托盘 ----------------

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$script:reallyExit = $false
$script:trayTipShown = $false


# 注意：不能用 $win.Hide()。窗口被隐藏会让 ShowDialog() 的消息循环结束，
# 脚本跑完末尾后进程退出，托盘图标也跟着消失。
# 改成"最小化 + 移出任务栏"，窗口对象仍然存在。





$tray = New-Tray
Update-TrayMenu

# 唤醒失败告警：检测新出现的 WAKE_FAIL 事件，弹托盘气泡

# ---------------- 计时器 ----------------

$timer = New-Object System.Windows.Threading.DispatcherTimer
$timer.Interval = [TimeSpan]::FromSeconds(5)
$timer.Add_Tick({
    $script:tickCount++
    # 通知后台采集：窗口不可见时降频
    try {
        $script:adbSync.Idle = ($win.WindowState -eq 'Minimized') -or (-not $win.IsVisible)
    } catch { }
    Update-Ui
    if ($script:tickCount % 6 -eq 0) {
        try {
            $mi2 = [MemInfo]::Get()
            Add-TrendSample ([int]($mi2[1] / 1MB))
            if ($script:viewMode -eq 'detail') { Sync-Trend }
        } catch { }
    }
    # 每小时清理一次过期日志
    if ($script:tickCount % 720 -eq 0) {
        Invoke-LogRotation
        Save-Trend
    }
})

$guardTimer = New-Object System.Windows.Threading.DispatcherTimer
$guardTimer.Interval = [TimeSpan]::FromMinutes([double]$script:cfg.GuardMinute)
$guardTimer.Add_Tick({
    [void](Invoke-GuardCleanup)
    Update-Ui
})

# 掉线检测：看护运行时按间隔检查，脚本掉了自动拉起
$recoverTimer = New-Object System.Windows.Threading.DispatcherTimer
$recoverTimer.Interval = [TimeSpan]::FromSeconds([double]$script:cfg.RecoverCheckSec)
$recoverTimer.Add_Tick({
    try {
        Invoke-AutoRecover
    } catch { }
    try {
        Invoke-AutoSleep
    } catch { }
    try {
        Invoke-AlertScan
    } catch { }
})

# 启动 20 秒后检查一次更新（不阻塞启动）
$updateTimer = New-Object System.Windows.Threading.DispatcherTimer
$updateTimer.Interval = [TimeSpan]::FromSeconds(20)
$updateTimer.Add_Tick({
    $updateTimer.Stop()
    try { Invoke-AutoUpdateCheck } catch { }
})
$win.Add_Loaded({
    Invoke-LogRotation
    $updateTimer.Start()
    Load-Trend
    Set-View 'compact'
    if ($txtVersion) { $txtVersion.Text = 'v' + $script:appVersion }
    Update-SleepButton
    Update-Ui
    if ($script:viewMode -eq 'detail') { Sync-Trend }
    # 有休眠任务就确保唤醒进程在跑；错过时间的立即补唤醒
    Invoke-CatchUpWake
    # 恢复上次的看护状态
    if ($script:cfg.GuardRunning -eq $true) {
        $script:guardRunning = $true
        $guardTimer.Interval = [TimeSpan]::FromMinutes([double]$script:cfg.GuardMinute)
        $guardTimer.Start()
        $recoverTimer.Interval = [TimeSpan]::FromSeconds([double]$script:cfg.RecoverCheckSec)
        $recoverTimer.Start()
        Update-Ui
    }
    $timer.Start()
})

$win.Add_Closing({
    param($s, $e)
    if ($script:reallyExit) { return }

    # 默认收进托盘。注意：不能在 Closing 里直接 Hide，
    # 否则 ShowDialog 的消息循环会提前结束，进程退出、托盘图标消失。
    # 这里先取消关闭，再用 Dispatcher 延后隐藏。
    $e.Cancel = $true
    $win.Dispatcher.BeginInvoke([Action]{
        try { Hide-Panel } catch { }
    }) | Out-Null

    if (-not $script:trayTipShown) {
        $script:trayTipShown = $true
        try {
            $tray.ShowBalloonTip(3000, 'MuMuGuard', '已收进托盘，看护仍在后台运行。右键托盘图标可退出。',
                [System.Windows.Forms.ToolTipIcon]::Info)
        } catch { }
    }
})

$win.Add_Closed({
    $timer.Stop()
    $guardTimer.Stop()
    $recoverTimer.Stop()
    $script:adbSync.Stop = $true
    try {
        $script:cfg.WindowLeft = [math]::Round($win.Left)
        $script:cfg.WindowTop  = [math]::Round($win.Top)
        $script:cfg.GuardRunning = $script:guardRunning
        Save-Config
    } catch { }
    Save-Trend
    try { $workerPs.Stop() } catch { }
    # 彻底退出：连唤醒器一起关掉
    Stop-AllWakers
    try { $tray.Visible = $false; $tray.Dispose() } catch { }
    try { $script:mutex.ReleaseMutex(); $script:mutex.Dispose() } catch { }
})

[void]$win.ShowDialog()
