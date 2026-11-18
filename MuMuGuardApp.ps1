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

# 启动阶段的兜底：万一在窗口出现前就出错，至少留下痕迹（此时模块函数还没加载）
trap {
    try {
        $__dir = Join-Path $env:LOCALAPPDATA 'MuMuGuard'
        if (-not (Test-Path $__dir)) { New-Item -ItemType Directory -Path $__dir -Force | Out-Null }
        Add-Content -Path (Join-Path $__dir 'startup-crash.log') -Encoding UTF8 -Value ('[{0:yyyy-MM-dd HH:mm:ss}] {1}' -f (Get-Date), $_)
    } catch { }
    continue
}

# 子进程（MuMuManager / adb）输出 UTF-8，隐藏窗口默认 GBK，不设会中文乱码
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch { }

$Root     = $PSScriptRoot

# ---------------- 加载模块 ----------------
$libPath = Join-Path $Root 'lib'
foreach ($f in @('90-pure', '00-common', '15-theme', '05-instances', '10-data', '20-actions', '30-ui', '32-shell', '33-render', '34-announce', '40-tray', '50-update', '70-qr', '60-remote', '61-outbound')) {
    $p = Join-Path $libPath ($f + '.ps1')
    if (Test-Path $p) { . $p }
    else { throw "缺少模块: $p" }
}

# 数据目录：优先复用已有数据，保证「脚本版」和「exe 版」看到同一份实例与设置
#   1) _dist（用户实际运行的 exe 目录）有配置就用它
#   2) 程序目录有配置就用它
#   3) LOCALAPPDATA 有配置就用它（装在 Program Files 的情况）
#   4) 都没有：程序目录可写就放旁边，否则退回 LOCALAPPDATA
$DataDir = $Root
$subDist = Join-Path $Root '_dist'
$appDataDir = Join-Path $env:LOCALAPPDATA 'MuMuGuard'
$existingCfg = @()
if (Test-Path (Join-Path $subDist 'config.json')) { $existingCfg += $subDist }
if (Test-Path (Join-Path $Root 'config.json')) { $existingCfg += $Root }
if (Test-Path (Join-Path $appDataDir 'config.json')) { $existingCfg += $appDataDir }
if ($existingCfg.Count -gt 0) {
    $DataDir = $existingCfg[0]
} else {
    try {
        $probe = Join-Path $Root '.write_test'
        [System.IO.File]::WriteAllText($probe, 'x')
        Remove-Item $probe -Force -ErrorAction SilentlyContinue
    } catch {
        $DataDir = $appDataDir
        if (-not (Test-Path $DataDir)) { New-Item -ItemType Directory -Path $DataDir -Force | Out-Null }
    }
}

# ---------------- 图标资源 ----------------
# 单文件 exe 分发时目录里没有图标文件，从内嵌资源释放到数据目录
function Resolve-Asset {
    param([string]$Name)
    $p = Join-Path $Root $Name
    if (Test-Path $p) { return $p }
    $p2 = Join-Path $DataDir $Name
    if (Test-Path $p2) { return $p2 }
    if ($script:EmbeddedAssets -and $script:EmbeddedAssets.ContainsKey($Name)) {
        try { [System.IO.File]::WriteAllBytes($p2, $script:EmbeddedAssets[$Name]); return $p2 } catch { }
    }
    return $null
}
$script:IconIco = Resolve-Asset 'MuMuGuard.ico'
$script:IconPng = Resolve-Asset 'icon.png'

$LogDir   = Join-Path $DataDir 'logs'
$CfgPath  = Join-Path $DataDir 'config.json'
$TrendFile = Join-Path $DataDir 'trend.json'
$SleepFile = Join-Path $DataDir 'sleep.json'
# 安装目录留空，稍后用 Find-MuMuRoot 自动定位（不再假设 D 盘存在）
$MuMuRoot = ''
$AdbExe   = ''
$MuMuMgr  = ''
$PkgScript = 'com.coc.zkqcode'
$PkgGame   = 'com.tencent.tmgp.supercell.clashofclans com.supercell.clashofclans'

if (-not (Test-Path $LogDir)) { New-Item -ItemType Directory -Path $LogDir -Force | Out-Null }


# 诊断日志（必须早于任何 Write-Diag 调用）
$script:diagFile = Join-Path $LogDir 'diag.log'

# ---------------- 换目录后沿用旧配置 ----------------
# 用户把 exe 挪到别的文件夹时，配置不该丢
if (-not (Test-Path $CfgPath)) {
    $cands = @(
        (Join-Path $env:LOCALAPPDATA 'MuMuGuard\config.json'),
        (Join-Path $Root 'config.json')
    ) | Select-Object -Unique
    foreach ($c in $cands) {
        if ($c -eq $CfgPath -or -not (Test-Path $c)) { continue }
        try {
            Copy-Item $c $CfgPath -Force
            $sf = Join-Path (Split-Path $c -Parent) 'sleep.json'
            if (Test-Path $sf) { Copy-Item $sf (Join-Path $DataDir 'sleep.json') -Force }
            Write-Diag ("沿用已有配置：{0}" -f $c)
        } catch { }
        break
    }
}
# ---------------- 配置 ----------------

$defaultCfg = [ordered]@{
    ConfigVersion = 2
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
    # 远程访问
    RemoteEnabled    = $false
    RemotePort       = 8790
    RemoteToken      = ''
    OutboundUid      = ''
    OutboundKey      = ''
    OutboundBroker   = 'broker.emqx.io'
    OutboundPort     = 8883
    OutboundEnabled  = $false
    OutboundPage     = 'https://suuk324.github.io/MuMuGuard/remote/'
    # 自动恢复
    AutoRecover      = $true
    RecoverCheckSec  = 60
    RecoverFailCount = 2
    RecoverCooldown  = 10
    DetectOff        = @()
    # 升级休眠
    AutoSleep        = $false
    SleepLeadMin     = 10
    SleepBackground  = $true      # 游戏切到后台时也允许休眠
    SleepIdleMin     = 10         # 后台空闲多少分钟才判定为脚本在等
    SleepMaxHours   = 168   # 最长休眠时长（小时）：CoC 升级经常几十小时，20 太小
    SleepMinHours   = 1     # 最短休眠时长（小时）：升级很快做完就别睡了，省得反复开关机
    # 路径与包名（可在设置里改）
    MuMuRoot     = ''
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
    AnnounceMuteDate = ''
    WindowLeft   = $null
    WindowTop    = $null
}

$script:cfg = @{}
foreach ($k in $defaultCfg.Keys) { $script:cfg[$k] = $defaultCfg[$k] }

$script:cfgFileVer = 0
if (Test-Path $CfgPath) {
    try {
        $saved = Get-Content $CfgPath -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($saved.PSObject.Properties.Name -contains 'ConfigVersion') { try { $script:cfgFileVer = [int]$saved.ConfigVersion } catch { $script:cfgFileVer = 0 } }
        foreach ($p in $saved.PSObject.Properties) {
            if ($script:cfg.ContainsKey($p.Name)) { $script:cfg[$p.Name] = $p.Value }
        }
    } catch { }
}

# ---------------- 配置版本与迁移 ----------------
$script:cfgVersion = 3
$savedVer = [int]$script:cfgFileVer
if ($savedVer -lt $script:cfgVersion) {
    if (Test-Path $CfgPath) {
        try { Copy-Item $CfgPath ("{0}.v{1}.bak" -f $CfgPath, $savedVer) -Force } catch { }
    }
    # v2 -> v3：最长休眠 20 小时太短（CoC 升级动辄几十小时），默认放宽到 168
    if ($savedVer -lt 3) {
        try { if ([double]$script:cfg.SleepMaxHours -eq 20) { $script:cfg.SleepMaxHours = 168 } } catch { }
    }
    $script:cfg['ConfigVersion'] = $script:cfgVersion
    Save-Config
    Write-Diag ("配置已从 v{0} 迁移到 v{1}（旧文件已备份）" -f $savedVer, $script:cfgVersion)
}

# 用配置覆盖路径与包名
if ($script:cfg.PkgScript) { $PkgScript = [string]$script:cfg.PkgScript }
if ($script:cfg.PkgGame)   { $PkgGame   = [string]$script:cfg.PkgGame }

# 定位 MuMu：配置值 → install_config.json → 注册表 → 各真实磁盘（不会去碰不存在的盘）
$MuMuRoot = Find-MuMuRoot ([string]$script:cfg.MuMuRoot)
$script:muMissing = -not $MuMuRoot
if ($MuMuRoot) {
    if ([string]$script:cfg.MuMuRoot -ne $MuMuRoot) { $script:cfg.MuMuRoot = $MuMuRoot; Save-Config }
    Write-Diag "MuMu 安装目录: $MuMuRoot"
} else {
    Write-Diag "未找到 MuMu 安装目录（配置值：'$($script:cfg.MuMuRoot)'）。请在设置里填写正确路径。"
}

# ---------------- 实例发现 ----------------
# 从 install_config.json 定位 adb / manager（自动适配 MuMu 12 / 15）
# 版本号
$script:appVersion     = '2.0.3'
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
# 用 MuMuManager 校准名称 / adb 端口 / 安卓版本（不依赖目录结构，安卓 12 同样适用）
$script:infoAll = Get-MuMuInfoAll -ManagerExe $MuMuMgr
if ($script:infoAll.Count -gt 0) {
    $script:instances = Merge-InstanceInfo -Configs $script:instances -InfoMap $script:infoAll
    $script:instanceMap = @{}
    foreach ($ic in $script:instances) { $script:instanceMap["$($ic.Index)"] = $ic }
    Write-Diag ("MuMuManager 信息已合并：{0} 个实例" -f $script:infoAll.Count)
} else {
    Write-Diag "MuMuManager info 无返回，改用目录扫描结果"
}
Write-Diag ("adb 路径: {0}" -f $AdbExe)
Write-Diag ("MuMuManager: {0}" -f $MuMuMgr)

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
$script:adbErrAt     = @{}
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
$script:adbSync = [hashtable]::Synchronized(@{ Stop = $false; Data = @{}; Idle = $false; RootOk = $true; Devices = @(); Force = @{} })

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
    param($sync, $mumuRoot, $adbExe, $pkgScript, $pkgGame, $purePath, $deviceList, $batchSize, $mumuMgr, $pureFuncText)

    try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch { }
    # 载入纯函数，保证与主程序逻辑一致
    if ($purePath -and (Test-Path $purePath)) { . $purePath }
    # exe 版没有 lib 目录，函数定义由主线程直接传进来
    if ($pureFuncText) { try { . ([scriptblock]::Create($pureFuncText)) } catch { } }

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


    $prevNemu = @{}
    $prevTime = $null
    $connected = @{}
    $cycle = 0
    $memCache = @{}
    $schedCache = @{}
    $lastData = @{}
    $cursor = 0
    $mgrAdbFail = 0
    $mgrAdbSkip = $false
    $mgrAdbSkip = $false
    while (-not $sync.Stop) {
        try {
            $cycle++
            # 一次抖动就会永久降级，导致实例再也采不到数据；每 10 轮重试一次主通道
            if ($mgrAdbSkip -and ($cycle % 10 -eq 0)) { $mgrAdbSkip = $false; $mgrAdbFail = 0 }
            $now  = Get-Date
            $out  = @{}
            $span = 30.0
            if ($prevTime) {
                $d = ($now - $prevTime).TotalSeconds
                if ($d -gt 1) { $span = $d }
            }

            # 升级信息变化慢，每 3 轮（约 90 秒）读一次
            $readMem = ($cycle % 3 -eq 1)
            # 手动唤醒后强制重读该实例（清缓存、立即重新抓取）
            $forceSet = @{}
            try { foreach ($fk in @($sync.Force.Keys)) { $forceSet["$fk"] = $true } } catch { }

            # 错峰轮询：每轮只查一批实例，避免多开时采集开销过大
            $all = @($sync.Devices)
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

                $online = $null
                $installed = $null
                $game   = $null
                $cur    = $null

                # 一次 shell 调用同时取「紫孔雀进程」「游戏进程」「nemuinit 时间」
                $cmd = "echo READY; echo SCRIPT; pidof $pkgScript; echo GAME; pidof $pkgGame; echo INST; pm path $pkgScript 2>/dev/null; echo FG; dumpsys window 2>/dev/null | grep mCurrentFocus; echo SEP; ps -A -o TIME+,NAME 2>/dev/null | grep nemuinit"
                if ($readMem -or (-not $schedCache.ContainsKey($i)) -or $forceSet.ContainsKey($i)) {
                    $cmd += "; echo ROOT; su -c 'id' 2>/dev/null; echo MEM; su -c 'base64 /storage/emulated/0/zkqFiles/memory.json 2>/dev/null'"
                    $cmd += "; echo SCH; su -c 'grep -o `"upgrade_time_scheduling[^,]*`" /storage/emulated/0/zkqFiles/zkq_config.json 2>/dev/null'"
                }

                $res = ''
                $errText = ''
                $chan = ''

                # 通道一：MuMuManager adb（不依赖 adb 路径与端口，安卓 12/15 通吃）
                if ($mumuMgr -and -not $mgrAdbSkip -and (Test-Path $mumuMgr)) {
                    try {
                        $out1 = (& $mumuMgr adb -v $i -c "shell $cmd" 2>&1 | Out-String)
                        if ($null -eq $out1) { $out1 = '' }
                        if ($out1 -match 'READY') {
                            $res = $out1; $chan = 'mumu'; $mgrAdbFail = 0
                        } else {
                            $errText = ($out1 -replace '\s+', ' ').Trim()
                            $mgrAdbFail++
                        }
                    } catch { $errText = $_.Exception.Message; $mgrAdbFail++ }
                }


                # 通道二：MuMuManager sh（直接跑 shell，不经过 adb，部分版本只有这个）
                if ($res -notmatch 'READY' -and $mumuMgr -and (Test-Path $mumuMgr)) {
                    try {
                        $outSh = (& $mumuMgr sh -v $i -c $cmd 2>&1 | Out-String)
                        if ($null -eq $outSh) { $outSh = '' }
                        if ($outSh -match 'READY') { $res = $outSh; $chan = 'mumush' }
                        elseif (-not $errText) { $errText = ($outSh -replace '\s+', ' ').Trim() }
                    } catch { if (-not $errText) { $errText = $_.Exception.Message } }
                }

                # 通道三：直连 adb（兜底）
                if ($res -notmatch 'READY' -and $port) {
                    $serial = "127.0.0.1:$port"
                    try { & $adbExe connect $serial *> $null } catch { }
                    try {
                        $out2 = ((& $adbExe -s $serial shell $cmd 2>&1) -join "`n")
                        if ($out2 -match 'READY') { $res = $out2; $chan = 'adb'; if ($mgrAdbFail -ge 3) { $mgrAdbSkip = $true } }
                        elseif (-not $errText) { $errText = ($out2 -replace '\s+', ' ').Trim() }
                    } catch { if (-not $errText) { $errText = $_.Exception.Message } }
                }

                if (-not $errText) { $errText = '（无返回内容）' }

                if ($res -match 'READY') {
                    $online = $true
                    # 切成 SCRIPT / GAME / SEP 三段
                    $scriptPart = ''
                    $gamePart   = ''
                    $psPart     = ''
                    if ($res -match '(?s)SCRIPT\s*(.*?)\s*GAME') { $scriptPart = $Matches[1] }
                    if ($res -match '(?s)GAME\s*(.*?)(?:\s*INST|\s*SEP)')  { $gamePart   = $Matches[1] }
                    if ($res -match '(?s)SEP\s*(.*)$')          { $psPart     = $Matches[1] }
                    # INST 段：紫孔雀是否已安装（没装就不能当成「掉线」去恢复）
                    $instPart = ''
                    if ($res -match '(?s)INST\s*(.*?)\s*FG') { $instPart = $Matches[1] }
                    $installed = ($instPart -match 'package:')

                    # 前台包名（判断脚本是不是把游戏切到后台了）
                    $fgPart = ''
                    if ($res -match '(?s)FG\s*(.*?)\s*SEP') { $fgPart = $Matches[1] }
                    $fgPkg = ''
                    foreach ($fgLine in ($fgPart -split "`n")) {
                        if ($fgLine -match 'mCurrentFocus=.*?\su\d+\s+([A-Za-z0-9_.]+)/') { $fgPkg = $Matches[1]; break }
                    }

                    # 三态：只有明确解析到段落才判定；解析不到 = 未知（null），不能当成「没在跑」
                    if ($res -match '(?s)SCRIPT\s*(.*?)\s*GAME') { $scriptOn = ($scriptPart -match '(?m)^\s*\d+\s*$') } else { $scriptOn = $null }
                    if ($res -match '(?s)GAME\s*(.*?)(?:\s*INST|\s*SEP)') { $gameOn = ($gamePart -match '(?m)^\s*\d+\s*$') } else { $gameOn = $null }

                    # nemuinit 时间在 SEP 段，升级信息在 MEM 段
                    if ($res -match '(?s)SEP\s*(.*?)(?:MEM|$)') { $psPart = $Matches[1] }
                    if ($psPart -match '(\d+(?::\d+){1,2})') { $cur = Convert-TimePlus $Matches[1] }

                    $readThis = $readMem -or (-not $schedCache.ContainsKey($i)) -or $forceSet.ContainsKey($i)
                    if ($readThis) {
                        # 被强制重读的实例：先丢掉旧缓存
                        if ($forceSet.ContainsKey($i)) { $memCache.Remove($i); $schedCache.Remove($i) }
                        $b64 = ''
                        if ($res -match '(?s)MEM\s*(.*?)(?:SCH|$)') { $b64 = $Matches[1] }
                        # 先看 root 是否可用，再判断升级信息缺失的原因
                        $rootPart = ''
                        if ($res -match '(?s)ROOT\s*(.*?)\s*MEM') { $rootPart = $Matches[1] }
                        $hasRoot = ($rootPart -match 'uid=0')
                        if ($b64 -and $b64.Trim().Length -gt 20) {
                            $sync.RootOk = $true
                            # 解析升级信息（之前这里漏了赋值，导致休眠判定永远拿不到完成时间）
                            $memCache[$i] = Get-UpgradeInfo $b64
                        }
                        elseif ($online -eq $true -and $scriptOn -eq $true) { $sync.RootOk = $hasRoot }

                        # 是否在等升级不再看日志：改由「游戏进程是否退出」判定

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
                    AdbErr  = $errText
                    Chan    = $chan
                    At      = (Get-Date)
                    Script  = $scriptOn
                    Installed = $installed
                    Game    = $gameOn
                    Spin    = $spin
                    Upgrade = $(if ($memCache.ContainsKey($i)) { $memCache[$i] } else { $null })
                    Foreground = $fgPkg
                    Sched   = $(if ($schedCache.ContainsKey($i)) { $schedCache[$i] } else { $null })
                }
                # 强制重读完成，撤掉标记，恢复常态轮询
                if ($forceSet.ContainsKey($i)) { try { $sync.Force.Remove($i) } catch { } }
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

# 传给采集线程的实例清单（只查正在运行的，避免对已关机的实例白跑 adb）
$devList = @($script:instances | Where-Object {
    $running = $true
    if ($_.PSObject.Properties.Name -contains 'Running') { $running = ($_.Running -eq $true) }
    $running
} | ForEach-Object { [pscustomobject]@{ Index = $_.Index; Port = $_.AdbPort } })
# 每批查几个：3 个以内全查，超过就分批（每批约 15 秒，一轮覆盖全部）

# 采集线程每轮读取这个列表，实例增减后无需重启面板
$script:adbSync.Devices = $devList
$batchSize = if ($devList.Count -le 3) { $devList.Count } else { [math]::Max(2, [int][math]::Ceiling($devList.Count / 5)) }

            # 采集线程是独立 runspace，拿不到主线程的函数；exe 版又没有 lib 目录，
            # 所以把解析函数定义成文本传进去，脚本版和 exe 版行为一致
            $pureFuncText = ''
            try { $pureFuncText = 'function Get-UpgradeFromMemoryJson { ' + (Get-Command Get-UpgradeFromMemoryJson -ErrorAction Stop).Definition + ' }' } catch { }
[void]$workerPs.AddScript($workerScript).AddArgument($script:adbSync).AddArgument($MuMuRoot).AddArgument($AdbExe).AddArgument($PkgScript).AddArgument($PkgGame).AddArgument((Join-Path $Root 'lib\90-pure.ps1')).AddArgument($devList).AddArgument($batchSize).AddArgument($MuMuMgr).AddArgument($pureFuncText)
$workerHandle = $workerPs.BeginInvoke()

# ---------------- 主界面 XAML ----------------

# 试验：软件渲染（硬件合成在 150% 缩放下可能丢字顶像素）
if ($env:MMG_SOFTWARE -eq '1') {
    try { [System.Windows.Media.RenderOptions]::ProcessRenderMode = [System.Windows.Interop.RenderMode]::SoftwareOnly } catch { }
}
$script:cfg.SoftwareRender = ($env:MMG_SOFTWARE -eq '1')
$xaml = Convert-XamlTheme (Get-ShellXaml)

$xaml = Convert-XamlTheme $xaml
$win = [Windows.Markup.XamlReader]::Parse($xaml)

# 主题资源：必须在界面显示前设好，DynamicResource 才能取到
Set-ThemeResources $win (Get-ActiveTheme)

# ---------------- 全局异常兜底 ----------------
# UI 线程上的未捕获异常：记日志并继续运行（看护工具不能因为一个界面异常就退出）
try {
    $win.Dispatcher.add_UnhandledException({
        param($s, $e)
        Write-Crash $e.Exception 'UI'
        try { $e.Handled = $true } catch { }
    })
} catch { Write-Diag "注册 UI 异常处理失败: $($_.Exception.Message)" }

# 任何线程上彻底没接住的异常（进程即将退出前）
# 注意：这个回调可能在非 PowerShell 线程上执行，不能用脚本块（会报「没有 Runspace」）
try {
    if (-not ('CrashSink' -as [type])) {
        Add-Type -TypeDefinition @"
using System;
using System.IO;
using System.Text;
public class CrashSink {
    public static string Path;
    public static string Version;
    public static void OnUnhandled(object sender, UnhandledExceptionEventArgs e) {
        try {
            var ex = e.ExceptionObject as Exception;
            var sb = new StringBuilder();
            sb.AppendLine("===== " + DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss") + " AppDomain =====");
            sb.AppendLine("致命异常，进程即将退出");
            if (ex != null) {
                sb.AppendLine("类型: " + ex.GetType().FullName);
                sb.AppendLine("消息: " + ex.Message);
                if (ex.StackTrace != null) sb.AppendLine(ex.StackTrace);
                if (ex.InnerException != null) sb.AppendLine("内部: " + ex.InnerException.Message);
            }
            sb.AppendLine("版本: " + (Version == null ? "" : Version));
            File.AppendAllText(Path, sb.ToString(), Encoding.UTF8);
        } catch { }
    }
    public static void Hook(string path, string ver) {
        Path = path; Version = ver;
        AppDomain.CurrentDomain.UnhandledException += new UnhandledExceptionEventHandler(OnUnhandled);
    }
}
"@
    }
    [CrashSink]::Hook((Join-Path $LogDir 'crash.log'), $script:appVersion)
} catch { Write-Diag "注册进程级异常处理失败: $($_.Exception.Message)" }
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
    $icoPath = $script:IconIco
    if ($icoPath -and (Test-Path $icoPath)) {
        $win.Icon = [System.Windows.Media.Imaging.BitmapFrame]::Create([Uri]$icoPath)
    }
        $logoImg = $win.FindName('LogoImg')
        if ($logoImg) {
            # 优先用 256px PNG，缩小后更清晰
            $pngPath = $script:IconPng
            $src = if (Test-Path $pngPath) { $pngPath } else { $icoPath }
            try { $logoImg.Source = [System.Windows.Media.Imaging.BitmapFrame]::Create([Uri]$src) } catch { }
            try { [System.Windows.Media.RenderOptions]::SetBitmapScalingMode($logoImg, 'HighQuality') } catch { }
        }
} catch { }

# ---------------- 新界面初始化 ----------------
$icoSrc = $null
try {
    if ($script:IconPng -and (Test-Path $script:IconPng)) { $icoSrc = [System.Windows.Media.Imaging.BitmapFrame]::Create([Uri]$script:IconPng) }
} catch { }
$instSrc = $null
try {
    $mIco = Join-Path $MuMuRoot 'nx_device\15.0\shell\MuMuPlayer.ico'
    if (Test-Path $mIco) { $instSrc = [System.Windows.Media.Imaging.BitmapFrame]::Create([Uri]$mIco) }
} catch { }
Initialize-Shell -Win $win -Logo $icoSrc -InstanceIcon $instSrc
if ($env:MMG_UITEST -eq '1') { $script:uiTestPending = $true }
# ---------------- 导出报告 ----------------


# ---------------- 事件绑定（新版在 Initialize-Shell 里完成） ----------------
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
        # 开了远程（局域网或出门用）就别降频，否则手机端拿不到实例
        $remoteOn = ($script:cfg.RemoteEnabled -eq $true) -or ($script:cfg.OutboundEnabled -eq $true)
        $script:adbSync.Idle = (-not $remoteOn) -and (($win.WindowState -eq 'Minimized') -or (-not $win.IsVisible))
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

$script:guardTimer = New-Object System.Windows.Threading.DispatcherTimer
$script:guardTimer.Interval = [TimeSpan]::FromMinutes([double]$script:cfg.GuardMinute)
$script:guardTimer.Add_Tick({
    [void](Invoke-GuardCleanup)
    Update-Ui
})

# 掉线检测：看护运行时按间隔检查，脚本掉了自动拉起
$script:recoverTimer = New-Object System.Windows.Threading.DispatcherTimer
$script:recoverTimer.Interval = [TimeSpan]::FromSeconds([double]$script:cfg.RecoverCheckSec)
$script:recoverTimer.Add_Tick({
    try {
        Invoke-AutoRecover
    } catch { }
    try {
        Invoke-AutoSleep
    } catch { Write-Diag ('自动休眠异常: ' + $_.Exception.Message) }
    # 看门狗：有休眠任务但没有唤醒器进程，就补拉一个（否则实例永远不会被唤醒）
    try { if (@(Get-SleepList).Count -gt 0) { Start-Waker } } catch { }
    try {
        Invoke-AlertScan
    } catch { }
})

# 启动 20 秒后检查一次更新（不阻塞启动）
# 每 2 分钟重扫一次实例：群友新开模拟器不需要重启面板
$rescanTimer = New-Object System.Windows.Threading.DispatcherTimer
$rescanTimer.Interval = [TimeSpan]::FromSeconds(120)
$rescanTimer.Add_Tick({
    try { if ($win -and $win.IsVisible -and $win.WindowState -ne 'Minimized') { [void](Update-InstanceList -VmsDir $script:muInfo.VmsDir -ManagerExe $MuMuMgr) } } catch { }
})
$rescanTimer.Start()

# 远程访问：队列处理（500ms）+ 状态快照刷新
$remoteTimer = New-Object System.Windows.Threading.DispatcherTimer
$remoteTimer.Interval = [TimeSpan]::FromMilliseconds(500)
$remoteTimer.Add_Tick({
    try { Invoke-RemoteCommands } catch { }
})
$remoteTimer.Start()

if ($script:cfg.OutboundEnabled -eq $true) {
    try { [void](Start-Outbound) } catch { Write-Diag "出站通道启动异常: $($_.Exception.Message)" }
}

if ($script:cfg.RemoteEnabled -eq $true) {
    try {
        if (-not (Start-RemoteServer)) { Write-Diag '远程服务未启动（详见日志）' }
    } catch { Write-Diag "远程服务启动异常: $($_.Exception.Message)" }
}

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
    try { Load-OpState } catch { }
    Set-View $(if ($env:MMG_COMPACT -eq '1') { 'compact' } else { 'shell' })
    if ($txtVersion) { $txtVersion.Text = 'v' + $script:appVersion }
    Update-SleepButton
    Update-Ui
    if ($script:viewMode -eq 'detail') { Sync-Trend }
    # 有休眠任务就确保唤醒进程在跑；错过时间的立即补唤醒
    try {
        if (Test-AnnounceDue) { Show-Announcement } else { Write-Diag '公告：今天已提醒过' }
    } catch { Write-Diag "公告调用失败: $($_.Exception.Message)" }
    if ($script:uiTestPending) {
        $script:uiTestTimer = New-Object System.Windows.Threading.DispatcherTimer
        $script:uiTestTimer.Interval = [TimeSpan]::FromSeconds(4)
        $script:uiTestTimer.Add_Tick({
            $script:uiTestTimer.Stop()
            try { Invoke-UiSelfTest } catch { Write-Diag "自检异常: $($_.Exception.Message)" }
            Start-Sleep -Milliseconds 300
            [Environment]::Exit(0)
        })
        $script:uiTestTimer.Start()
    }
    Invoke-CatchUpWake
    # 恢复上次的看护状态
    if ($script:cfg.GuardRunning -eq $true) {
        $script:guardRunning = $true
        $script:guardTimer.Interval = [TimeSpan]::FromMinutes([double]$script:cfg.GuardMinute)
        $guardTimer.Start()
        $script:recoverTimer.Interval = [TimeSpan]::FromSeconds([double]$script:cfg.RecoverCheckSec)
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
    try { Stop-RemoteServer } catch { }
    try { Stop-Outbound } catch { }
    $script:adbSync.Stop = $true
    try {
        if ($win.WindowState -eq 'Normal') {
            $script:cfg.WindowLeft = [math]::Round($win.Left)
            $script:cfg.WindowTop  = [math]::Round($win.Top)
        }
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

# 界面线程兜底：任何未捕获异常都记录并继续运行，避免面板静默退出
try {
    $win.Dispatcher.Add_UnhandledException({
        param($s, $e)
        try {
            Write-Crash "界面线程异常: $($e.Exception.GetType().Name) $($e.Exception.Message)`n$($e.Exception.StackTrace)"
            Write-Diag "界面线程异常已拦截: $($e.Exception.Message)"
        } catch { }
        $e.Handled = $true
    })
} catch { }
[void]$win.ShowDialog()
