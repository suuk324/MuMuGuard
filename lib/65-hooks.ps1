#Requires -Version 5.1
#
# 实例启动钩子（InstanceHooks）
# 通用能力：实例安卓启动完成后，可自动启动指定 App、执行任意 adb 命令、或运行用户脚本。
# 默认关闭，不影响看护 / 休眠 / 采集等核心流程；失败只写日志和状态，不阻塞主界面。
# 具体加速器通过「自动启动应用 / 启动后命令 / 启动后脚本」由用户自己配置。

$script:hookRt = $null
$script:hookWorkerSb = $null
$script:hookWorkerJob = $null
$script:hookOnceJob = $null
$script:hookWorkerSig = ''

function Initialize-HookRuntime {
    param([string]$ManagerExe, [string]$AdbExe, [string]$DataDir)
    $script:hookRt = @{
        Manager   = $ManagerExe
        Adb       = $AdbExe
        DataDir   = $DataDir
        StatusFile = (Join-Path $DataDir 'hooks-status.json')
        LogFile    = (Join-Path $DataDir 'hooks.log')
    }
    try {
        $hdir = Join-Path $DataDir 'hooks'
        if (-not (Test-Path $hdir)) { New-Item -ItemType Directory -Path $hdir -Force | Out-Null }
    } catch { }
}

function Get-HookRuntimePath([string]$name) {
    if (-not $script:hookRt) { return '' }
    return [string]$script:hookRt[$name]
}

# ---------- 配置读写 ----------

function Get-InstanceHook([string]$Index) {
    $store = $null
    try { $store = $script:cfg.InstanceHooks } catch { }
    return (Get-InstanceHookFromStore $store $Index)
}

function Get-InstanceHooksEnabled {
    $map = @{}
    $store = $null
    try { $store = $script:cfg.InstanceHooks } catch { }
    if ($null -eq $store) { return $map }
    $keys = @()
    try {
        if ($store -is [System.Collections.IDictionary]) { $keys = @($store.Keys) }
        else { $keys = @($store.PSObject.Properties | ForEach-Object { $_.Name }) }
    } catch { }
    foreach ($k in $keys) {
        $h = Get-InstanceHookFromStore $store "$k"
        if ($h.Enabled) { $map["$k"] = $h }
    }
    return $map
}

function Set-InstanceHook {
    param([string]$Index, $Hook)
    $store = @{}
    $old = $null
    try { $old = $script:cfg.InstanceHooks } catch { }
    if ($null -ne $old) {
        try {
            if ($old -is [System.Collections.IDictionary]) { foreach ($k in $old.Keys) { $store["$k"] = $old[$k] } }
            else { foreach ($p in $old.PSObject.Properties) { $store[$p.Name] = $p.Value } }
        } catch { }
    }
    $store["$Index"] = $Hook
    $script:cfg.InstanceHooks = $store
    Save-Config
    Update-HookWorker
}

# ---------- 状态文件 ----------

function Get-HookStatus([string]$Index) {
    $empty = [pscustomobject]@{ State = 'idle'; Message = ''; UpdatedAt = ''; LastRunAt = ''; LastLaunchTime = 0 }
    $f = Get-HookRuntimePath 'StatusFile'
    if (-not $f -or -not (Test-Path $f)) { return $empty }
    try {
        $raw = Get-Content $f -Raw -Encoding UTF8
        if (-not $raw) { return $empty }
        $all = $raw | ConvertFrom-Json
        foreach ($p in $all.PSObject.Properties) {
            if ($p.Name -eq "$Index") { return $p.Value }
        }
    } catch { }
    return $empty
}

function Get-HookStatusText([string]$Index) {
    $st = Get-HookStatus $Index
    $lab = switch ("$($st.State)") {
        'running' { '执行中' }
        'waiting' { '等待安卓启动' }
        'ok'      { '成功' }
        'error'   { '失败' }
        default   { '未执行' }
    }
    $txt = "上次：$lab"
    if ($st.Message) { $txt += "（$($st.Message)）" }
    if ($st.LastRunAt) { $txt += " · $($st.LastRunAt)" }
    return $txt
}

# ---------- 后台 worker（Start-Job，独立进程，避免卡 UI） ----------

$script:hookWorkerSb = [scriptblock]::Create([System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('CiAgICBwYXJhbSgKICAgICAgICBbc3RyaW5nXSRNYW5hZ2VyRXhlLAogICAgICAgIFtzdHJpbmddJEFkYkV4ZSwKICAgICAgICBbc3RyaW5nXSREYXRhRGlyLAogICAgICAgIFtzdHJpbmddJEhvb2tzSnNvbiwKICAgICAgICBbc3RyaW5nXSRTdGF0dXNGaWxlLAogICAgICAgIFtzdHJpbmddJExvZ0ZpbGUsCiAgICAgICAgW2Jvb2xdJE9uY2UsCiAgICAgICAgW3N0cmluZ10kT25seUluZGV4CiAgICApCiAgICAkRXJyb3JBY3Rpb25QcmVmZXJlbmNlID0gJ0NvbnRpbnVlJwogICAgIyDlrZDov5vnqIvpu5jorqTmjInns7vnu58gQU5TSSDop6PnoIHlpJbpg6jlkb3ku6TovpPlh7rvvIxNdU11TWFuYWdlciDmmK8gVVRGLTjvvJvkuI3orr7nva7kvJrmiorkuK3mlofmiZPnoo7vvIjnlJroh7PnoLTlnY8gSlNPTiDlvJXlj7fvvIkKICAgIHRyeSB7IFtDb25zb2xlXTo6T3V0cHV0RW5jb2RpbmcgPSBbU3lzdGVtLlRleHQuRW5jb2RpbmddOjpVVEY4IH0gY2F0Y2ggeyB9CgogICAgZnVuY3Rpb24gV0xvZyhbc3RyaW5nXSRtKSB7CiAgICAgICAgdHJ5IHsgQWRkLUNvbnRlbnQgLVBhdGggJExvZ0ZpbGUgLVZhbHVlICgnW3swOnl5eXktTU0tZGQgSEg6bW06c3N9XSB7MX0nIC1mIChHZXQtRGF0ZSksICRtKSAtRW5jb2RpbmcgVVRGOCB9IGNhdGNoIHsgfQogICAgfQogICAgZnVuY3Rpb24gUmVhZFN0YXR1c0ZpbGUgewogICAgICAgIHRyeSB7CiAgICAgICAgICAgIGlmIChUZXN0LVBhdGggJFN0YXR1c0ZpbGUpIHsKICAgICAgICAgICAgICAgICRyYXcgPSBHZXQtQ29udGVudCAkU3RhdHVzRmlsZSAtUmF3IC1FbmNvZGluZyBVVEY4CiAgICAgICAgICAgICAgICBpZiAoJHJhdykgeyByZXR1cm4gKCRyYXcgfCBDb252ZXJ0RnJvbS1Kc29uKSB9CiAgICAgICAgICAgIH0KICAgICAgICB9IGNhdGNoIHsgfQogICAgICAgIHJldHVybiAkbnVsbAogICAgfQogICAgZnVuY3Rpb24gV3JpdGVTdGF0dXMoW3N0cmluZ10kaWR4LCBbc3RyaW5nXSRzdGF0ZSwgW3N0cmluZ10kbXNnLCAkbGF1bmNoVGltZSkgewogICAgICAgICRhbGwgPSBAe30KICAgICAgICB0cnkgewogICAgICAgICAgICAkY3VyID0gUmVhZFN0YXR1c0ZpbGUKICAgICAgICAgICAgaWYgKCRjdXIpIHsgZm9yZWFjaCAoJHAgaW4gJGN1ci5QU09iamVjdC5Qcm9wZXJ0aWVzKSB7ICRhbGxbJHAuTmFtZV0gPSAkcC5WYWx1ZSB9IH0KICAgICAgICB9IGNhdGNoIHsgfQogICAgICAgICRhbGxbJGlkeF0gPSBbb3JkZXJlZF1AewogICAgICAgICAgICBTdGF0ZSAgICAgICAgICA9ICRzdGF0ZQogICAgICAgICAgICBNZXNzYWdlICAgICAgICA9ICRtc2cKICAgICAgICAgICAgVXBkYXRlZEF0ICAgICAgPSAoR2V0LURhdGUpLlRvU3RyaW5nKCd5eXl5LU1NLWRkIEhIOm1tOnNzJykKICAgICAgICAgICAgTGFzdFJ1bkF0ICAgICAgPSAoR2V0LURhdGUpLlRvU3RyaW5nKCd5eXl5LU1NLWRkIEhIOm1tOnNzJykKICAgICAgICAgICAgTGFzdExhdW5jaFRpbWUgPSAkbGF1bmNoVGltZQogICAgICAgIH0KICAgICAgICB0cnkgewogICAgICAgICAgICAkdG1wID0gIiRTdGF0dXNGaWxlLnRtcCIKICAgICAgICAgICAgKCRhbGwgfCBDb252ZXJ0VG8tSnNvbiAtRGVwdGggNSkgfCBTZXQtQ29udGVudCAtUGF0aCAkdG1wIC1FbmNvZGluZyBVVEY4CiAgICAgICAgICAgIE1vdmUtSXRlbSAtUGF0aCAkdG1wIC1EZXN0aW5hdGlvbiAkU3RhdHVzRmlsZSAtRm9yY2UKICAgICAgICB9IGNhdGNoIHsgfQogICAgfQogICAgZnVuY3Rpb24gR2V0LUluZm8oW3N0cmluZ10kaWR4KSB7CiAgICAgICAgdHJ5IHsKICAgICAgICAgICAgJHJhdyA9ICYgJE1hbmFnZXJFeGUgaW5mbyAtdiAkaWR4IDI+JjEgfCBPdXQtU3RyaW5nCiAgICAgICAgICAgIGlmICgkcmF3IC1tYXRjaCAnImluZGV4IicpIHsgcmV0dXJuICgkcmF3IHwgQ29udmVydEZyb20tSnNvbikgfQogICAgICAgIH0gY2F0Y2ggeyB9CiAgICAgICAgcmV0dXJuICRudWxsCiAgICB9CiAgICBmdW5jdGlvbiBTaChbc3RyaW5nXSRzZXJpYWwsIFtzdHJpbmddJGNtZCkgewogICAgICAgIHRyeSB7IHJldHVybiAoJiAkQWRiRXhlIC1zICRzZXJpYWwgc2hlbGwgJGNtZCAyPiYxIHwgT3V0LVN0cmluZykgfSBjYXRjaCB7IHJldHVybiAnJyB9CiAgICB9CiAgICBmdW5jdGlvbiBSdW4tSG9vayhbc3RyaW5nXSRpZHgsICRob29rLCAkaW5mbykgewogICAgICAgICRzZXJpYWwgPSAnJwogICAgICAgIHRyeSB7ICRzZXJpYWwgPSAiMTI3LjAuMC4xOiQoJGluZm8uYWRiX3BvcnQpIiB9IGNhdGNoIHsgfQogICAgICAgIGlmICgtbm90ICRzZXJpYWwpIHsgV3JpdGVTdGF0dXMgJGlkeCAnZXJyb3InICfmsqHmnIkgYWRiIOerr+WPoycgMDsgcmV0dXJuIH0KICAgICAgICAjIGxhdW5jaF90aW1lIOavj+asoeafpeivouWPr+iDveWPmOWMlu+8jOS4jeiDveW9k+WQr+WKqOagh+ivhu+8m+eUqOWunuS+i+WJjeerr+i/m+eoiyBwaWTvvIjlkIzkuIDov5vnqIvnlJ/lkb3lkajmnJ/lhoXnqLPlrprvvIkKICAgICAgICAkbGF1bmNoVGltZSA9ICcnCiAgICAgICAgdHJ5IHsgJGxhdW5jaFRpbWUgPSAiJCgkaW5mby5waWQpIiB9IGNhdGNoIHsgfQogICAgICAgIGlmICgtbm90ICRsYXVuY2hUaW1lKSB7IHRyeSB7ICRsYXVuY2hUaW1lID0gIiQoJGluZm8ubGF1bmNoX3RpbWUpIiB9IGNhdGNoIHsgfSB9CiAgICAgICAgV0xvZyAi5a6e5L6LJGlkeCDlkK/liqjlkI7liqjkvZzlvIDlp4vvvIhzZXJpYWw9JHNlcmlhbO+8iSIKICAgICAgICAkbnVsbCA9ICYgJEFkYkV4ZSBjb25uZWN0ICRzZXJpYWwgMj4mMQogICAgICAgIFdyaXRlU3RhdHVzICRpZHggJ3dhaXRpbmcnICfnrYnlvoXlronljZPlkK/liqjlrozmiJAnICRsYXVuY2hUaW1lCiAgICAgICAgJGJvb3RlZCA9ICRmYWxzZQogICAgICAgIGZvciAoJGkgPSAwOyAkaSAtbHQgNjA7ICRpKyspIHsKICAgICAgICAgICAgJGIgPSAoU2ggJHNlcmlhbCAnZ2V0cHJvcCBzeXMuYm9vdF9jb21wbGV0ZWQnKS5UcmltKCkKICAgICAgICAgICAgaWYgKCRiIC1tYXRjaCAnMScpIHsgJGJvb3RlZCA9ICR0cnVlOyBicmVhayB9CiAgICAgICAgICAgIFN0YXJ0LVNsZWVwIC1TZWNvbmRzIDEKICAgICAgICB9CiAgICAgICAgaWYgKC1ub3QgJGJvb3RlZCkgeyBXcml0ZVN0YXR1cyAkaWR4ICdlcnJvcicgJ+WuieWNk+WQr+WKqOi2heaXticgJGxhdW5jaFRpbWU7IFdMb2cgIuWunuS+iyRpZHgg5a6J5Y2T5ZCv5Yqo6LaF5pe2IjsgcmV0dXJuIH0KICAgICAgICAkZGVsYXkgPSAwCiAgICAgICAgdHJ5IHsgJGRlbGF5ID0gW2ludF0kaG9vay5EZWxheVNlYyB9IGNhdGNoIHsgfQogICAgICAgIGlmICgkZGVsYXkgLWd0IDApIHsgU3RhcnQtU2xlZXAgLVNlY29uZHMgJGRlbGF5IH0KICAgICAgICBXcml0ZVN0YXR1cyAkaWR4ICdydW5uaW5nJyAn5omn6KGM5ZCv5Yqo5ZCO5pON5L2cJyAkbGF1bmNoVGltZQogICAgICAgICRlcnJzID0gQCgpCiAgICAgICAgZm9yZWFjaCAoJHBrZyBpbiBAKCRob29rLkF1dG9TdGFydEFwcHMpKSB7CiAgICAgICAgICAgIGlmICgiJHBrZyIuVHJpbSgpKSB7CiAgICAgICAgICAgICAgICBXTG9nICLlrp7kvoskaWR4IOWQr+WKqOW6lOeUqCAkcGtnIgogICAgICAgICAgICAgICAgJG51bGwgPSBTaCAkc2VyaWFsICgibW9ua2V5IC1wICRwa2cgLWMgYW5kcm9pZC5pbnRlbnQuY2F0ZWdvcnkuTEFVTkNIRVIgMSIpCiAgICAgICAgICAgICAgICBTdGFydC1TbGVlcCAtU2Vjb25kcyAyCiAgICAgICAgICAgIH0KICAgICAgICB9CiAgICAgICAgZm9yZWFjaCAoJGMgaW4gQCgkaG9vay5Qb3N0U3RhcnRDb21tYW5kcykpIHsKICAgICAgICAgICAgaWYgKCIkYyIuVHJpbSgpKSB7CiAgICAgICAgICAgICAgICBXTG9nICLlrp7kvoskaWR4IOaJp+ihjOWRveS7pCAkYyIKICAgICAgICAgICAgICAgIHRyeSB7CiAgICAgICAgICAgICAgICAgICAgJG91dCA9IChTaCAkc2VyaWFsICIkYyIpCiAgICAgICAgICAgICAgICAgICAgJHRyaW0gPSAkb3V0LlRyaW0oKQogICAgICAgICAgICAgICAgICAgIGlmICgkdHJpbSkgeyBXTG9nICgiICDovpPlh7o6ICIgKyAkdHJpbS5TdWJzdHJpbmcoMCwgW01hdGhdOjpNaW4oMzAwLCAkdHJpbS5MZW5ndGgpKSkgfQogICAgICAgICAgICAgICAgfSBjYXRjaCB7ICRlcnJzICs9ICRfLkV4Y2VwdGlvbi5NZXNzYWdlIH0KICAgICAgICAgICAgfQogICAgICAgIH0KICAgICAgICAkc2MgPSBbc3RyaW5nXSRob29rLlBvc3RTdGFydFNjcmlwdAogICAgICAgIGlmICgkc2MpIHsKICAgICAgICAgICAgJHBhdGggPSAkc2MKICAgICAgICAgICAgaWYgKC1ub3QgW1N5c3RlbS5JTy5QYXRoXTo6SXNQYXRoUm9vdGVkKCRwYXRoKSkgeyAkcGF0aCA9IEpvaW4tUGF0aCAkRGF0YURpciAkcGF0aCB9CiAgICAgICAgICAgIGlmIChUZXN0LVBhdGggJHBhdGgpIHsKICAgICAgICAgICAgICAgIFdMb2cgIuWunuS+iyRpZHgg5omn6KGM6ISa5pysICRwYXRoIgogICAgICAgICAgICAgICAgJGVudjpNTUdfSU5TVEFOQ0UgPSAiJGlkeCIKICAgICAgICAgICAgICAgICRlbnY6TU1HX1NFUklBTCA9ICRzZXJpYWwKICAgICAgICAgICAgICAgICRlbnY6TU1HX0FEQiA9ICRBZGJFeGUKICAgICAgICAgICAgICAgICRlbnY6TU1HX0RBVEFfRElSID0gJERhdGFEaXIKICAgICAgICAgICAgICAgICRvMSA9IEpvaW4tUGF0aCAkRGF0YURpciAnaG9va3Mtc2NyaXB0Lm91dCcKICAgICAgICAgICAgICAgICRvMiA9IEpvaW4tUGF0aCAkRGF0YURpciAnaG9va3Mtc2NyaXB0LmVycicKICAgICAgICAgICAgICAgIHRyeSB7CiAgICAgICAgICAgICAgICAgICAgIyDnlKggLk5FVCBQcm9jZXNzIOebtOaOpei3ke+8jOaJjeiDveWPr+mdoOaLv+WIsCBFeGl0Q29kZe+8iFN0YXJ0LVByb2Nlc3Mg5Zyo6YOo5YiG5oOF5Ya15LiLIEV4aXRDb2RlIOS4uuepuu+8iQogICAgICAgICAgICAgICAgICAgICRwc2kgPSBOZXctT2JqZWN0IFN5c3RlbS5EaWFnbm9zdGljcy5Qcm9jZXNzU3RhcnRJbmZvCiAgICAgICAgICAgICAgICAgICAgJHBzaS5GaWxlTmFtZSA9ICdwb3dlcnNoZWxsLmV4ZScKICAgICAgICAgICAgICAgICAgICAkcHNpLkFyZ3VtZW50cyA9ICctTm9Qcm9maWxlIC1FeGVjdXRpb25Qb2xpY3kgQnlwYXNzIC1XaW5kb3dTdHlsZSBIaWRkZW4gLUZpbGUgIicgKyAkcGF0aCArICciJwogICAgICAgICAgICAgICAgICAgICRwc2kuVXNlU2hlbGxFeGVjdXRlID0gJGZhbHNlCiAgICAgICAgICAgICAgICAgICAgJHBzaS5DcmVhdGVOb1dpbmRvdyA9ICR0cnVlCiAgICAgICAgICAgICAgICAgICAgJHBzaS5SZWRpcmVjdFN0YW5kYXJkT3V0cHV0ID0gJHRydWUKICAgICAgICAgICAgICAgICAgICAkcHNpLlJlZGlyZWN0U3RhbmRhcmRFcnJvciA9ICR0cnVlCiAgICAgICAgICAgICAgICAgICAgJGNoaWxkID0gW1N5c3RlbS5EaWFnbm9zdGljcy5Qcm9jZXNzXTo6U3RhcnQoJHBzaSkKICAgICAgICAgICAgICAgICAgICAkZmluaXNoZWQgPSAkY2hpbGQuV2FpdEZvckV4aXQoMTgwMDAwKQogICAgICAgICAgICAgICAgICAgIGlmICgtbm90ICRmaW5pc2hlZCkgewogICAgICAgICAgICAgICAgICAgICAgICB0cnkgeyAkY2hpbGQuS2lsbCgpIH0gY2F0Y2ggeyB9CiAgICAgICAgICAgICAgICAgICAgICAgICRlcnJzICs9ICfohJrmnKzotoXml7bvvIgxODDnp5LvvIknCiAgICAgICAgICAgICAgICAgICAgfSBlbHNlIHsKICAgICAgICAgICAgICAgICAgICAgICAgdHJ5IHsgU2V0LUNvbnRlbnQgLVBhdGggJG8xIC1WYWx1ZSAkY2hpbGQuU3RhbmRhcmRPdXRwdXQuUmVhZFRvRW5kKCkgLUVuY29kaW5nIFVURjggfSBjYXRjaCB7IH0KICAgICAgICAgICAgICAgICAgICAgICAgdHJ5IHsgU2V0LUNvbnRlbnQgLVBhdGggJG8yIC1WYWx1ZSAkY2hpbGQuU3RhbmRhcmRFcnJvci5SZWFkVG9FbmQoKSAtRW5jb2RpbmcgVVRGOCB9IGNhdGNoIHsgfQogICAgICAgICAgICAgICAgICAgICAgICBpZiAoW2ludF0kY2hpbGQuRXhpdENvZGUgLW5lIDApIHsgJGVycnMgKz0gIuiEmuacrOmAgOWHuueggSAkKCRjaGlsZC5FeGl0Q29kZSkiIH0KICAgICAgICAgICAgICAgICAgICB9CiAgICAgICAgICAgICAgICB9IGNhdGNoIHsgJGVycnMgKz0gJF8uRXhjZXB0aW9uLk1lc3NhZ2UgfQogICAgICAgICAgICB9IGVsc2UgewogICAgICAgICAgICAgICAgJGVycnMgKz0gIuiEmuacrOS4jeWtmOWcqDogJHNjIgogICAgICAgICAgICB9CiAgICAgICAgfQogICAgICAgIGlmICgkZXJycy5Db3VudCAtZ3QgMCkgewogICAgICAgICAgICBXcml0ZVN0YXR1cyAkaWR4ICdlcnJvcicgKCfpg6jliIblpLHotKU6ICcgKyAoJGVycnMgLWpvaW4gJzsgJykpICRsYXVuY2hUaW1lCiAgICAgICAgICAgIFdMb2cgIuWunuS+iyRpZHgg6YOo5YiG5aSx6LSlOiAkKCRlcnJzIC1qb2luICc7ICcpIgogICAgICAgIH0gZWxzZSB7CiAgICAgICAgICAgIFdyaXRlU3RhdHVzICRpZHggJ29rJyAn5ZCv5Yqo5ZCO5pON5L2c5a6M5oiQJyAkbGF1bmNoVGltZQogICAgICAgICAgICBXTG9nICLlrp7kvoskaWR4IOWQr+WKqOWQjuWKqOS9nOWujOaIkCIKICAgICAgICB9CiAgICB9CgogICAgJGhvb2tzID0gQHt9CiAgICB0cnkgewogICAgICAgICRvYmogPSAkSG9va3NKc29uIHwgQ29udmVydEZyb20tSnNvbgogICAgICAgIGZvcmVhY2ggKCRwIGluICRvYmouUFNPYmplY3QuUHJvcGVydGllcykgeyAkaG9va3NbJHAuTmFtZV0gPSAkcC5WYWx1ZSB9CiAgICB9IGNhdGNoIHsgfQogICAgJGxhc3RSdW4gPSBAe30KICAgIHRyeSB7CiAgICAgICAgJHN0ID0gUmVhZFN0YXR1c0ZpbGUKICAgICAgICBpZiAoJHN0KSB7IGZvcmVhY2ggKCRwIGluICRzdC5QU09iamVjdC5Qcm9wZXJ0aWVzKSB7IHRyeSB7ICRsYXN0UnVuWyRwLk5hbWVdID0gIiQoJHAuVmFsdWUuTGFzdExhdW5jaFRpbWUpIiB9IGNhdGNoIHsgfSB9IH0KICAgIH0gY2F0Y2ggeyB9CgogICAgaWYgKCRPbmNlIC1hbmQgJE9ubHlJbmRleCkgewogICAgICAgICRoID0gJGhvb2tzWyRPbmx5SW5kZXhdCiAgICAgICAgZm9yICgkaSA9IDA7ICRpIC1sdCAxMjA7ICRpKyspIHsKICAgICAgICAgICAgJGluZm8gPSBHZXQtSW5mbyAkT25seUluZGV4CiAgICAgICAgICAgIGlmICgkaW5mbyAtYW5kICRpbmZvLmlzX2FuZHJvaWRfc3RhcnRlZCkgewogICAgICAgICAgICAgICAgUnVuLUhvb2sgJE9ubHlJbmRleCAkaCAkaW5mbwogICAgICAgICAgICAgICAgYnJlYWsKICAgICAgICAgICAgfQogICAgICAgICAgICBTdGFydC1TbGVlcCAtU2Vjb25kcyAyCiAgICAgICAgfQogICAgICAgIHJldHVybgogICAgfQoKICAgIHdoaWxlICgkdHJ1ZSkgewogICAgICAgIHRyeSB7CiAgICAgICAgICAgIGZvcmVhY2ggKCRpZHggaW4gQCgkaG9va3MuS2V5cykpIHsKICAgICAgICAgICAgICAgICRoID0gJGhvb2tzWyRpZHhdCiAgICAgICAgICAgICAgICBpZiAoLW5vdCAkaC5FbmFibGVkKSB7IGNvbnRpbnVlIH0KICAgICAgICAgICAgICAgICRpbmZvID0gR2V0LUluZm8gJGlkeAogICAgICAgICAgICAgICAgaWYgKC1ub3QgJGluZm8pIHsgY29udGludWUgfQogICAgICAgICAgICAgICAgJGx0ID0gJycKICAgICAgICAgICAgICAgIHRyeSB7ICRsdCA9ICIkKCRpbmZvLnBpZCkiIH0gY2F0Y2ggeyB9CiAgICAgICAgICAgICAgICBpZiAoLW5vdCAkbHQpIHsgdHJ5IHsgJGx0ID0gIiQoJGluZm8ubGF1bmNoX3RpbWUpIiB9IGNhdGNoIHsgfSB9CiAgICAgICAgICAgICAgICBpZiAoJGluZm8uaXNfYW5kcm9pZF9zdGFydGVkKSB7CiAgICAgICAgICAgICAgICAgICAgJG5lZWQgPSAoLW5vdCAkbGFzdFJ1bi5Db250YWluc0tleSgkaWR4KSkgLW9yICgiJCgkbGFzdFJ1blskaWR4XSkiIC1uZSAiJGx0IikKICAgICAgICAgICAgICAgICAgICBpZiAoJG5lZWQpIHsKICAgICAgICAgICAgICAgICAgICAgICAgIyDpnaLmnb/ph43lkK/lkI7lrp7kvovku43lnKjov5DooYzvvJrlpoLmnpzov5nkuIDova7lkK/liqjlt7Lnu4/lpITnkIbov4fvvIjnirbmgIEgb2svcnVubmluZ++8ie+8jOS4jeimgemHjeWkjeaJp+ihjAogICAgICAgICAgICAgICAgICAgICAgICAkc2FtZUxhdW5jaCA9ICRmYWxzZQogICAgICAgICAgICAgICAgICAgICAgICB0cnkgewogICAgICAgICAgICAgICAgICAgICAgICAgICAgJGN1ciA9IFJlYWRTdGF0dXNGaWxlCiAgICAgICAgICAgICAgICAgICAgICAgICAgICBpZiAoJGN1cikgewogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIGZvcmVhY2ggKCRwcCBpbiAkY3VyLlBTT2JqZWN0LlByb3BlcnRpZXMpIHsKICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgaWYgKCRwcC5OYW1lIC1lcSAiJGlkeCIpIHsKICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICRzdiA9ICRwcC5WYWx1ZQogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgaWYgKCIkKCRzdi5MYXN0TGF1bmNoVGltZSkiIC1lcSAiJGx0IiAtYW5kICIkKCRzdi5TdGF0ZSkiIC1pbiBAKCdvaycsICdlcnJvcicsICdydW5uaW5nJykpIHsgJHNhbWVMYXVuY2ggPSAkdHJ1ZSB9CiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIH0KICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICB9CiAgICAgICAgICAgICAgICAgICAgICAgICAgICB9CiAgICAgICAgICAgICAgICAgICAgICAgIH0gY2F0Y2ggeyB9CiAgICAgICAgICAgICAgICAgICAgICAgIGlmICgkc2FtZUxhdW5jaCkgewogICAgICAgICAgICAgICAgICAgICAgICAgICAgJGxhc3RSdW5bJGlkeF0gPSAiJGx0IgogICAgICAgICAgICAgICAgICAgICAgICB9IGVsc2UgewogICAgICAgICAgICAgICAgICAgICAgICAgICAgUnVuLUhvb2sgJGlkeCAkaCAkaW5mbwogICAgICAgICAgICAgICAgICAgICAgICAgICAgJGxhc3RSdW5bJGlkeF0gPSAiJGx0IgogICAgICAgICAgICAgICAgICAgICAgICB9CiAgICAgICAgICAgICAgICAgICAgfQogICAgICAgICAgICAgICAgfSBlbHNlIHsKICAgICAgICAgICAgICAgICAgICBpZiAoJGxhc3RSdW4uQ29udGFpbnNLZXkoJGlkeCkpIHsgJGxhc3RSdW4uUmVtb3ZlKCRpZHgpIH0KICAgICAgICAgICAgICAgIH0KICAgICAgICAgICAgfQogICAgICAgIH0gY2F0Y2ggewogICAgICAgICAgICBXTG9nICgnd29ya2VyIOW8guW4uDogJyArICRfLkV4Y2VwdGlvbi5NZXNzYWdlKQogICAgICAgIH0KICAgICAgICBTdGFydC1TbGVlcCAtU2Vjb25kcyA1CiAgICB9')))

function Stop-HookWorker {
    foreach ($j in @($script:hookWorkerJob, $script:hookOnceJob)) {
        if ($j) {
            try { Stop-Job -Job $j -ErrorAction SilentlyContinue } catch { }
            try { Remove-Job -Job $j -Force -ErrorAction SilentlyContinue } catch { }
        }
    }
    $script:hookWorkerJob = $null
    $script:hookOnceJob = $null
    $script:hookWorkerSig = ''
}

function Update-HookWorker {
    if (-not $script:hookRt) { return }
    $enabled = Get-InstanceHooksEnabled
    if ($enabled.Count -eq 0) {
        Stop-HookWorker
        return
    }
    $payload = $enabled | ConvertTo-Json -Depth 5 -Compress
    $sig = "$($script:hookRt.Manager)|$($script:hookRt.Adb)|$($script:hookRt.DataDir)|$payload"
    if ($script:hookWorkerJob -and $script:hookWorkerJob.State -eq 'Running' -and $script:hookWorkerSig -eq $sig) { return }
    Stop-HookWorker
    try {
        $script:hookWorkerJob = Start-Job -ScriptBlock $script:hookWorkerSb -ArgumentList @(
            $script:hookRt.Manager,
            $script:hookRt.Adb,
            $script:hookRt.DataDir,
            $payload,
            $script:hookRt.StatusFile,
            $script:hookRt.LogFile,
            $false,
            ''
        )
        $script:hookWorkerSig = $sig
    } catch {
        Write-Diag "启动后钩子 worker 启动失败: $($_.Exception.Message)"
    }
}

function Invoke-HookNow([string]$Index) {
    if (-not $script:hookRt) { return }
    $h = Get-InstanceHook $Index
    if (-not $h.Enabled) { $h.Enabled = $true }
    $payload = @{}
    $payload["$Index"] = $h
    $json = $payload | ConvertTo-Json -Depth 5 -Compress
    try {
        if ($script:hookOnceJob) {
            try { Stop-Job -Job $script:hookOnceJob -ErrorAction SilentlyContinue } catch { }
            try { Remove-Job -Job $script:hookOnceJob -Force -ErrorAction SilentlyContinue } catch { }
        }
        $script:hookOnceJob = Start-Job -ScriptBlock $script:hookWorkerSb -ArgumentList @(
            $script:hookRt.Manager,
            $script:hookRt.Adb,
            $script:hookRt.DataDir,
            $json,
            $script:hookRt.StatusFile,
            $script:hookRt.LogFile,
            $true,
            "$Index"
        )
        Write-GuardLog 'HOOK_RUN' "实例$Index" '手动执行启动后操作'
    } catch {
        Write-Diag "手动执行启动后钩子失败: $($_.Exception.Message)"
    }
}

# ---------- 设置对话框 ----------

function Show-HookDialog([string]$Index) {
    $hook = Get-InstanceHook $Index
    $state = @{ Enabled = [bool]$hook.Enabled }
    $appsTxt = (@($hook.AutoStartApps) -join ' ')
    $cmdsTxt = (@($hook.PostStartCommands) -join "`r`n")
    $scriptTxt = "$($hook.PostStartScript)"
    $delayTxt = "$([int]$hook.DelaySec)"

    $xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="启动后自动操作" Width="500" SizeToContent="Height"
        WindowStyle="None" AllowsTransparency="True" Background="Transparent"
        WindowStartupLocation="CenterOwner" ShowInTaskbar="False">
  <Border x:Name="Root" CornerRadius="14" Background="#232327" BorderBrush="#33FFFFFF" BorderThickness="1">
    <StackPanel Margin="22,20,22,16">
      <TextBlock x:Name="Ttl" Text="启动后自动操作" FontSize="15" FontWeight="SemiBold" Foreground="#F2F2F5"/>
      <TextBlock x:Name="Dsc" Text="实例安卓启动完成后自动执行；失败只写日志，不影响看护。默认关闭。" FontSize="10.5" Foreground="#6E6E78" TextWrapping="Wrap" Margin="0,4,0,10"/>

      <Border x:Name="BtnToggle" Background="#1AFFFFFF" CornerRadius="9" Padding="12,8" Cursor="Hand">
        <TextBlock x:Name="TxtToggle" Text="启用：已关闭（点击开启）" FontSize="11.5" Foreground="#E6E6EC"/>
      </Border>

      <TextBlock Text="自动启动应用（包名，空格或逗号分隔，可留空）" FontSize="10.5" Foreground="#6E6E78" Margin="0,12,0,5"/>
      <Border Background="#1A1A1E" CornerRadius="9" BorderBrush="#33FFFFFF" BorderThickness="1" Padding="10,7">
        <TextBox x:Name="InpApps" Text="" FontSize="12" Foreground="#F2F2F5" Background="Transparent" BorderThickness="0"/>
      </Border>

      <StackPanel Margin="0,10,0,0">
        <TextBlock Text="延迟（秒）" FontSize="10.5" Foreground="#6E6E78" Margin="0,0,0,5"/>
        <Border Background="#1A1A1E" CornerRadius="9" BorderBrush="#33FFFFFF" BorderThickness="1" Padding="10,7">
          <TextBox x:Name="InpDelay" Text="" FontSize="12" Foreground="#F2F2F5" Background="Transparent" BorderThickness="0"/>
        </Border>
      </StackPanel>

      <TextBlock Text="启动后命令（每行一条 adb shell 命令，可留空）" FontSize="10.5" Foreground="#6E6E78" Margin="0,12,0,5"/>
      <Border Background="#1A1A1E" CornerRadius="9" BorderBrush="#33FFFFFF" BorderThickness="1" Padding="10,7">
        <TextBox x:Name="InpCmds" Text="" FontSize="11.5" Foreground="#F2F2F5" Background="Transparent" BorderThickness="0" AcceptsReturn="True" TextWrapping="Wrap" Height="58" VerticalScrollBarVisibility="Auto"/>
      </Border>

      <TextBlock Text="启动后脚本（.ps1 路径，可留空；相对路径按数据目录算）" FontSize="10.5" Foreground="#6E6E78" Margin="0,12,0,5"/>
      <Grid>
        <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="8"/><ColumnDefinition Width="64"/></Grid.ColumnDefinitions>
        <Border Grid.Column="0" Background="#1A1A1E" CornerRadius="9" BorderBrush="#33FFFFFF" BorderThickness="1" Padding="10,7">
          <TextBox x:Name="InpScript" Text="" FontSize="11.5" Foreground="#F2F2F5" Background="Transparent" BorderThickness="0"/>
        </Border>
        <Border x:Name="BtnBrowse" Grid.Column="2" Background="#1AFFFFFF" CornerRadius="9" Padding="0,8" Cursor="Hand">
          <TextBlock Text="浏览" FontSize="11" Foreground="#E6E6EC" HorizontalAlignment="Center"/>
        </Border>
      </Grid>

      <TextBlock x:Name="TxtStatus" Text="" FontSize="10.5" Foreground="#8E9AAA" TextWrapping="Wrap" Margin="0,12,0,0"/>

      <StackPanel Orientation="Horizontal" HorizontalAlignment="Right" Margin="0,14,0,0">
        <Border x:Name="BtnRun" Background="#1AFFFFFF" CornerRadius="8" Padding="12,7" Margin="0,0,8,0" Cursor="Hand">
          <TextBlock Text="立即执行" FontSize="11.5" Foreground="#E6E6EC"/>
        </Border>
        <Border x:Name="BtnSave" Background="#F2F2F5" CornerRadius="8" Padding="14,7" Margin="0,0,8,0" Cursor="Hand">
          <TextBlock Text="保存" FontSize="11.5" Foreground="#1B1B1F" FontWeight="SemiBold"/>
        </Border>
        <Border x:Name="BtnClose" Background="#1AFFFFFF" CornerRadius="8" Padding="14,7" Cursor="Hand">
          <TextBlock Text="关闭" FontSize="11.5" Foreground="#E6E6EC"/>
        </Border>
      </StackPanel>
    </StackPanel>
  </Border>
</Window>
'@
    $dlg = [Windows.Markup.XamlReader]::Parse((Convert-XamlTheme $xaml))
    Bring-DialogFront $dlg
    try { Set-ThemeResources $dlg (Get-ActiveTheme) } catch { }
    Enable-WindowDrag $dlg.FindName('Root') $dlg
    $dlg.FindName('Ttl').Text = "启动后自动操作 · 实例 $Index"
    $dlg.FindName('InpApps').Text = $appsTxt
    $dlg.FindName('InpCmds').Text = $cmdsTxt
    $dlg.FindName('InpScript').Text = $scriptTxt
    $dlg.FindName('InpDelay').Text = $delayTxt
    $dlg.FindName('TxtStatus').Text = (Get-HookStatusText $Index)

    $refreshToggle = {
        if ($state.Enabled) {
            $dlg.FindName('TxtToggle').Text = '启用：已开启（点击关闭）'
            $dlg.FindName('TxtToggle').Foreground = Brush '#34C759'
        } else {
            $dlg.FindName('TxtToggle').Text = '启用：已关闭（点击开启）'
            $dlg.FindName('TxtToggle').Foreground = Brush '#9E9EA6'
        }
    }
    & $refreshToggle
    $dlg.FindName('BtnToggle').Add_MouseLeftButtonUp({ $state.Enabled = -not $state.Enabled; & $refreshToggle }.GetNewClosure())

    $collect = {
        $apps = @((($dlg.FindName('InpApps').Text) -split '[,\s]+') | ForEach-Object { $_.Trim() } | Where-Object { $_ })
        $cmds = @((($dlg.FindName('InpCmds').Text) -split "`r?`n") | ForEach-Object { $_.TrimEnd() } | Where-Object { "$_".Trim() })
        $delay = 8
        try { $delay = [Math]::Max(0, [int]$dlg.FindName('InpDelay').Text) } catch { }
        return [ordered]@{
            Enabled           = [bool]$state.Enabled
            DelaySec          = $delay
            AutoStartApps     = $apps
            PostStartCommands = $cmds
            PostStartScript   = $dlg.FindName('InpScript').Text.Trim()
        }
    }

    $dlg.FindName('BtnBrowse').Add_MouseLeftButtonUp({
        try {
            $ofd = New-Object Microsoft.Win32.OpenFileDialog
            $ofd.Filter = 'PowerShell 脚本 (*.ps1)|*.ps1|所有文件 (*.*)|*.*'
            $ofd.Title = '选择启动后要执行的脚本'
            if ($ofd.ShowDialog()) { $dlg.FindName('InpScript').Text = $ofd.FileName }
        } catch { }
    }.GetNewClosure())


    $dlg.FindName('BtnRun').Add_MouseLeftButtonUp({
        try {
            $h3 = New-InstanceHook (& $collect)
            Set-InstanceHook -Index $Index -Hook $h3
            Invoke-HookNow $Index
            $dlg.FindName('TxtStatus').Text = '已开始执行，稍后看结果（约 10~30 秒）'
            Update-Ui
        } catch {
            $dlg.FindName('TxtStatus').Text = "执行失败：$($_.Exception.Message)"
        }
    }.GetNewClosure())

    $dlg.FindName('BtnSave').Add_MouseLeftButtonUp({
        try {
            $h4 = New-InstanceHook (& $collect)
            Set-InstanceHook -Index $Index -Hook $h4
            $dlg.Close()
            Update-Ui
        } catch {
            $dlg.FindName('TxtStatus').Text = "保存失败：$($_.Exception.Message)"
        }
    }.GetNewClosure())

    $dlg.FindName('BtnClose').Add_MouseLeftButtonUp({ $dlg.Close() })
    if ($script:dlgAudit) { $script:dlgAuditErrs += (Test-DialogTheme $dlg '启动后操作'); try { $dlg.Close() } catch { }; return }
    if ($script:shellWin) { try { $dlg.Owner = $script:shellWin } catch { } }
    [void]$dlg.ShowDialog()
}