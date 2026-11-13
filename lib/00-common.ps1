#Requires -Version 5.1
#
# 公共：日志、配置、画刷等基础函数
# 本文件由拆分脚本生成，供 MuMuGuardApp.ps1 dot-source（共享同一 $script: 作用域）

function Write-Diag([string]$msg) {
    try {
        if (-not (Test-Path $LogDir)) { New-Item -ItemType Directory -Path $LogDir -Force | Out-Null }
        Add-Content -Path $script:diagFile -Value ('[{0:yyyy-MM-dd HH:mm:ss}] {1}' -f (Get-Date), $msg) -Encoding UTF8
    } catch { }
}


function Save-Config {    try {
        $script:cfg | ConvertTo-Json -Depth 4 | Set-Content -Path $CfgPath -Encoding UTF8
    } catch {
        Write-Diag "保存配置失败: $($_.Exception.Message)"
    }
}


function Brush([string]$hex) {
    return New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.ColorConverter]::ConvertFromString($hex))
}


function Get-LogFile { param([datetime]$d = (Get-Date)) Join-Path $LogDir ('guard-{0:yyyyMMdd}.csv' -f $d) }


function Write-GuardLog {
    param([string]$Action, [string]$Instance, [string]$Detail)
    $file = Get-LogFile
    $line = '{0:yyyy-MM-dd HH:mm:ss},{1},{2},{3}' -f (Get-Date), $Action, $Instance, $Detail
    try {
        if (-not (Test-Path $file)) { 'Time,Action,Instance,Detail' | Set-Content -Path $file -Encoding UTF8 }
        Add-Content -Path $file -Value $line -Encoding UTF8
    } catch { }
}


function Invoke-LogRotation {
    try {
        $limit = (Get-Date).AddDays(-[int]$script:cfg.LogKeepDays)
        Get-ChildItem $LogDir -Filter 'guard-*.csv' -ErrorAction SilentlyContinue |
            Where-Object { $_.LastWriteTime -lt $limit } |
            Remove-Item -Force -ErrorAction SilentlyContinue
    } catch { }
}


function Update-LogInfo {
    $file = Get-LogFile
    if (-not (Test-Path $file)) {
        $script:logClean = 0; $script:logKilled = 0; $script:logAlert = 0
        return
    }
    # 只在日志文件变化时重新解析
    try {
        $fi = Get-Item $file
        if ($script:logCache -and
            $fi.Length -eq $script:logCache.Len -and
            $fi.LastWriteTime -eq $script:logCache.Time) {
            $script:logClean  = $script:logCache.Clean
            $script:logKilled = $script:logCache.Killed
            $script:logAlert  = $script:logCache.Alert
            return
        }
    } catch { }

    $clean = 0; $killed = 0; $alert = 0
    try {
        foreach ($r in (Import-Csv $file -ErrorAction Stop)) {
            switch ($r.Action) {
                'CLEAN_CEF'  { $clean++; if ($r.Detail -match 'killed=(\d+)') { $killed += [int]$Matches[1] } }
                'ALERT_SPIN' { $alert++ }
                'LOW_MEM'    { $alert++ }
                'ALERT_MEM'  { $alert++ }
                'ALERT_SCRIPT' { $alert++ }
                'RECOVER_FAIL' { $alert++ }
                'WAKE_FAIL'    { $alert++ }
                'AUTO_RECOVER' { $clean++ }
                'AUTO_RESTART' { $clean++ }
                'RECOVER_OK'   { $clean++ }
                'SLEEP'        { $clean++ }
                'WAKE_MANUAL'  { $clean++ }
                'WAKE_LATE'    { $clean++ }
                'WAKE_OK'      { $clean++ }
                'ROOT_FAIL'    { $alert++ }
            }
        }
    } catch { }
    $script:logClean = $clean; $script:logKilled = $killed; $script:logAlert = $alert
    try {
        $script:logCache = @{ Len = $fi.Length; Time = $fi.LastWriteTime; Clean = $clean; Killed = $killed; Alert = $alert }
    } catch { }
}

# ---------------- 辅助脚本定位 ----------------
# 编译成 exe 后没有 lib\ 目录，Waker / Restart-Instance / Update-Helper 需要释放到本地目录
# 开发模式下直接用脚本目录里的原文件

function Get-HelperDir {
    $d = Join-Path $env:LOCALAPPDATA 'MuMuGuard'
    if (-not (Test-Path $d)) { New-Item -ItemType Directory -Path $d -Force | Out-Null }
    return $d
}

function Get-HelperScript([string]$Name) {
    # 开发模式：脚本目录下存在就直接用（确保改完立即生效）
    $devPath = Join-Path $Root $Name
    if ((Test-Path $devPath) -and (-not $script:EmbeddedHelpers)) { return $devPath }

    # 编译模式：把内嵌内容写到本地目录
    $dir = Get-HelperDir
    $target = Join-Path $dir $Name

    $content = $null
    if ($script:EmbeddedHelpers -and $script:EmbeddedHelpers.ContainsKey($Name)) {
        $content = $script:EmbeddedHelpers[$Name]
    }

    if ($null -eq $content) {
        if (Test-Path $devPath) { return $devPath }
        return $target
    }

    # 内容不一致才重写，避免每次启动都写盘
    $needWrite = $true
    if (Test-Path $target) {
        try {
            $cur = [System.IO.File]::ReadAllText($target, [System.Text.Encoding]::UTF8)
            if ($cur -eq $content) { $needWrite = $false }
        } catch { }
    }
    if ($needWrite) {
        try { [System.IO.File]::WriteAllText($target, $content, (New-Object System.Text.UTF8Encoding $true)) }
        catch { Write-Diag "释放辅助脚本失败: $Name $($_.Exception.Message)" }
    }
    return $target
}