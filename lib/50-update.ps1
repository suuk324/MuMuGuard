#Requires -Version 5.1
#
# 更新：从 GitHub Releases 检查、下载并替换程序
# 供 MuMuGuardApp.ps1 dot-source（共享同一 $script: 作用域）

# 当前程序文件（exe 或 ps1）
function Get-CurrentExecutable {
    try {
        $p = [System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
        if ($p -and (Test-Path $p)) { return $p }
    } catch { }
    return (Join-Path $Root 'MuMuGuardApp.ps1')
}

# 是否以编译后的 exe 运行
function Test-RunningAsExe {
    $exe = Get-CurrentExecutable
    return ($exe -match '\.exe$')
}

# 应用镜像前缀（留空则直连 GitHub）
function Add-Mirror([string]$Url) {
    $m = [string]$script:cfg.UpdateMirror
    if (-not $m) { return $Url }
    $m = $m.Trim()
    if (-not $m.EndsWith('/')) { $m += '/' }
    return ($m + $Url)
}

# 查询最新 Release；返回 @{Ok; Version; Url; Notes; Sha256Url; Error}
function Get-LatestRelease {
    $repo = [string]$script:cfg.UpdateRepo
    if (-not $repo) { return [pscustomobject]@{ Ok = $false; Error = '未配置 UpdateRepo' } }

    $api = Add-Mirror ("https://api.github.com/repos/$repo/releases/latest")
    $headers = @{ 'User-Agent' = 'MuMuGuard'; 'Accept' = 'application/vnd.github+json' }

    try {
        $j = Invoke-RestMethod -Uri $api -Headers $headers -TimeoutSec 8 -UseBasicParsing -ErrorAction Stop
    } catch {
        Write-Diag "检查更新失败: $($_.Exception.Message)"
        return [pscustomobject]@{ Ok = $false; Error = $_.Exception.Message }
    }

    $ver = "$($j.tag_name)"
    $exeUrl = ''
    $shaUrl = ''
    foreach ($a in @($j.assets)) {
        $n = "$($a.name)"
        $u = "$($a.browser_download_url)"
        if ($n -match '\.exe$') { $exeUrl = $u }
        elseif ($n -match '\.sha256$') { $shaUrl = $u }
    }

    return [pscustomobject]@{
        Ok        = $true
        Version   = $ver
        Url       = $exeUrl
        Sha256Url = $shaUrl
        Notes     = "$($j.body)"
        PageUrl   = "$($j.html_url)"
        Error     = ''
    }
}

# 检查是否有新版；返回 @{HasUpdate; Local; Remote; Info}
function Test-UpdateAvailable {
    $local = [string]$script:appVersion
    $rel = Get-LatestRelease
    if (-not $rel.Ok) {
        return [pscustomobject]@{ HasUpdate = $false; Local = $local; Remote = ''; Info = $rel; Error = $rel.Error }
    }
    $has = Test-NewerVersion -Local $local -Remote $rel.Version
    return [pscustomobject]@{ HasUpdate = $has; Local = $local; Remote = $rel.Version; Info = $rel; Error = '' }
}

# 下载到临时目录，返回文件路径
function Save-UpdatePackage($ReleaseInfo) {
    if (-not $ReleaseInfo -or -not $ReleaseInfo.Url) { throw '发布中没有可下载的 exe' }
    $dir = Join-Path $env:TEMP 'MuMuGuard_update'
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $dst = Join-Path $dir 'MuMuGuard_new.exe'

    $url = Add-Mirror $ReleaseInfo.Url
    $headers = @{ 'User-Agent' = 'MuMuGuard' }
    Invoke-WebRequest -Uri $url -OutFile $dst -Headers $headers -TimeoutSec 60 -UseBasicParsing -ErrorAction Stop

    if (-not (Test-Path $dst) -or (Get-Item $dst).Length -lt 10240) {
        throw '下载文件异常（过小）'
    }

    # 校验 SHA256（若 Release 里提供了 .sha256）
    if ($ReleaseInfo.Sha256Url) {
        try {
            $txt = Invoke-RestMethod -Uri (Add-Mirror $ReleaseInfo.Sha256Url) -Headers $headers -TimeoutSec 15 -UseBasicParsing
            $expect = ("$txt" -split '\s+')[0].Trim().ToLower()
            $actual = (Get-FileHash $dst -Algorithm SHA256).Hash.ToLower()
            if ($expect -and $expect -ne $actual) {
                Remove-Item $dst -Force -ErrorAction SilentlyContinue
                throw 'SHA256 校验不通过，已取消更新'
            }
        } catch {
            if ($_.Exception.Message -like '*SHA256*') { throw }
            Write-Diag "SHA256 校验跳过: $($_.Exception.Message)"
        }
    }

    return $dst
}

# 启动独立的更新助手：等主程序退出 → 替换 → 重启
function Start-UpdateInstall([string]$NewFile) {
    $target = Get-CurrentExecutable
    if ($target -notmatch '\.exe$') { throw '当前不是以 exe 运行，无法自动替换' }

    $helper = Get-HelperScript 'Update-Helper.ps1'
    if (-not (Test-Path $helper)) { throw '缺少 Update-Helper.ps1' }

    $argList = @(
        '-NoProfile', '-ExecutionPolicy', 'Bypass', '-WindowStyle', 'Hidden',
        '-File', $helper,
        '-TargetPath', $target,
        '-NewPath', $NewFile,
        '-ProcessId', "$PID",
        '-Restart'
    )
    Start-Process -FilePath 'C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe' `
        -ArgumentList $argList -WindowStyle Hidden | Out-Null

    $script:reallyExit = $true
    try { $win.Close() } catch { }
}

# 检查更新（带界面提示）
function Invoke-UpdateCheckUI([bool]$Silent) {
    if (-not $Silent) { $txtInfo.Text = '正在检查更新…' }

    $r = Test-UpdateAvailable
    if ($r.Error) {
        if (-not $Silent) {
            $res = [System.Windows.MessageBox]::Show(
                "检查更新失败：`n`n$($r.Error)`n`n可能是网络无法访问 GitHub。要继续打开下载页面吗？",
                'MuMuGuard', 'YesNo', 'Warning')
            if ($res -eq 'Yes') {
                Start-Process ("https://github.com/$($script:cfg.UpdateRepo)/releases")
            }
        }
        return
    }

    if (-not $r.HasUpdate) {
        if (-not $Silent) {
            [System.Windows.MessageBox]::Show("已是最新版本 v$($r.Local)", 'MuMuGuard', 'OK', 'Information') | Out-Null
        }
        return
    }

    if ($Silent -and $script:cfg.SkippedVersion -eq $r.Remote) { return }

    $notes = "$($r.Info.Notes)"
    if ($notes.Length -gt 600) { $notes = $notes.Substring(0, 600) + '…' }
    $msg = "发现新版本：v$($r.Local) → $($r.Remote)`n`n$notes`n`n是否立即下载并安装？`n（安装时程序会关闭，完成后自动重启）"

    $res = [System.Windows.MessageBox]::Show($msg, 'MuMuGuard 更新', 'YesNo', 'Question')
    if ($res -ne 'Yes') {
        if ($Silent) {
            $script:cfg.SkippedVersion = $r.Remote
            Save-Config
        }
        return
    }

    try {
        $txtInfo.Text = '正在下载更新…'
        $file = Save-UpdatePackage $r.Info
        Start-UpdateInstall $file
    } catch {
        [System.Windows.MessageBox]::Show("更新失败：`n`n$($_.Exception.Message)`n`n可手动到 GitHub 下载。", 'MuMuGuard', 'OK', 'Error') | Out-Null
        Write-Diag "更新失败: $($_.Exception.Message)"
    }
}

# 启动后静默检查（24 小时内不重复）
function Invoke-AutoUpdateCheck {
    if ($script:cfg.AutoUpdateCheck -ne $true) { return }
    $last = "$($script:cfg.LastUpdateCheck)"
    if ($last) {
        try {
            if (((Get-Date) - [datetime]$last).TotalHours -lt 24) { return }
        } catch { }
    }
    $script:cfg.LastUpdateCheck = (Get-Date).ToString('yyyy-MM-ddTHH:mm:ss')
    Save-Config

    try { Invoke-UpdateCheckUI -Silent $true } catch { Write-Diag "自动更新检查异常: $($_.Exception.Message)" }
}