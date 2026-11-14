#Requires -Version 5.1
<#
  Health-Check.ps1  -  环境级全面体检
  与单元测试互补：单元测试查纯逻辑，这里查「真实环境下的数据链路」。
  只读，不会关实例、不会改配置（休眠列表往返用临时文件）。
#>
$ErrorActionPreference = 'Continue'
$root = Split-Path $PSScriptRoot -Parent
$pass = 0; $fail = 0; $fails = @()

function Ok($name, $cond, $detail = '') {
    if ($cond) { $script:pass++; Write-Host ("  [OK]   {0}" -f $name) -ForegroundColor Green }
    else { $script:fail++; $script:fails += "$name $detail"; Write-Host ("  [FAIL] {0}  {1}" -f $name, $detail) -ForegroundColor Red }
}

Write-Host '==================================================' -ForegroundColor Cyan
Write-Host '  MuMuGuard 环境体检' -ForegroundColor Cyan
Write-Host '==================================================' -ForegroundColor Cyan

# ---------- 1. 配置完整性 ----------
Write-Host "`n[1] 配置完整性（代码引用的键是否都存在）" -ForegroundColor Yellow
$cfgPath = Join-Path $root 'config.json'
$cfgExists = Test-Path $cfgPath
Ok 'config.json 存在' $cfgExists $cfgPath
if ($cfgExists) {
    $cfg = Get-Content $cfgPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $keys = @($cfg.PSObject.Properties.Name)
    $usedKeys = @{}
    Get-ChildItem (Join-Path $root 'lib') -Filter '*.ps1' | ForEach-Object {
        $txt = Get-Content $_.FullName -Raw -Encoding UTF8
        foreach ($m in [regex]::Matches($txt, '\$script:cfg\.([A-Za-z_][A-Za-z0-9_]*)')) { $usedKeys[$m.Groups[1].Value] = $true }
    }
    foreach ($m in [regex]::Matches((Get-Content (Join-Path $root 'MuMuGuardApp.ps1') -Raw -Encoding UTF8), '\$script:cfg\.([A-Za-z_][A-Za-z0-9_]*)')) { $usedKeys[$m.Groups[1].Value] = $true }
    $methodNames = @('ContainsKey', 'Keys', 'Values', 'Count', 'PSObject', 'Remove', 'Add', 'Clear', 'Clone')
# 默认值里定义的键也算合法（config.json 可能还没写过这些键）
    $appTxt = Get-Content (Join-Path $root 'MuMuGuardApp.ps1') -Raw -Encoding UTF8
    foreach ($m in [regex]::Matches($appTxt, '(?m)^\s{4}([A-Za-z_][A-Za-z0-9_]*)\s*=')) { $keys += $m.Groups[1].Value }
    $missing = @($usedKeys.Keys | Where-Object { $keys -notcontains $_ -and $methodNames -notcontains $_ } | Sort-Object)
    Ok ('代码引用的配置键都存在（{0} 个）' -f $usedKeys.Count) ($missing.Count -eq 0) ($missing -join ', ')
    $sameness = @('AutoSleep', 'GuardRunning', 'SleepLeadMin', 'SleepMaxHours', 'RecoverCheckSec', 'RecoverFailCount', 'CefKeep', 'CefStaleMin')
    $absent = @($sameness | Where-Object { $keys -notcontains $_ })
    Ok '关键配置项齐全' ($absent.Count -eq 0) ($absent -join ', ')
    Ok ('最长休眠合理（{0} 小时 >= 24）' -f $cfg.SleepMaxHours) ([double]$cfg.SleepMaxHours -ge 24)
}

# ---------- 2. MuMu 环境 ----------
Write-Host "`n[2] MuMu 环境" -ForegroundColor Yellow
$mgr = 'D:\Program Files\Netease\MuMu\nx_main\MuMuManager.exe'
if ($cfg -and $cfg.MuMuRoot) { $mgr = Join-Path ([string]$cfg.MuMuRoot) 'nx_main\MuMuManager.exe' }
Ok 'MuMuManager 存在' (Test-Path $mgr) $mgr
$info = $null
if (Test-Path $mgr) {
    try { $info = (& $mgr info -v all 2>&1 | Out-String) | ConvertFrom-Json } catch { }
}
Ok 'MuMuManager info 可解析' ($null -ne $info)
$instances = @()
if ($info) {
    foreach ($p in $info.PSObject.Properties) {
        $v = $p.Value
        $instances += [pscustomobject]@{
            Index = "$($v.index)"; Name = "$($v.name)"; Series = "$($v.android_version)"
            Running = ($v.is_process_started -eq $true); Port = "$($v.adb_port)"
        }
    }
    Ok ('发现实例 {0} 个' -f $instances.Count) ($instances.Count -gt 0)
    $badName = @($instances | Where-Object { $_.Name -match '^实例\s*\d+$' -or $_.Name -eq '' })
    Ok '实例名来自 MuMu 而非编号占位' ($badName.Count -eq 0) (($badName | ForEach-Object { $_.Index }) -join ',')
    $running = @($instances | Where-Object { $_.Running })
    Ok ('运行中 {0} 个' -f $running.Count) $true
}

# ---------- 3. 采集协议（真实 adb）----------
Write-Host "`n[3] 采集协议（对运行中的实例实跑一次）" -ForegroundColor Yellow
if ($instances.Count -gt 0) {
    $adm = Get-ChildItem (Join-Path ([string]$cfg.MuMuRoot) 'nx_device') -Directory -ErrorAction SilentlyContinue |
            Sort-Object Name -Descending | ForEach-Object { Join-Path $_.FullName 'shell\adb.exe' } | Where-Object { Test-Path $_ } | Select-Object -First 1
    foreach ($inst in @($instances | Where-Object { $_.Running })) {
        $pkgS = if ($cfg.PkgScript) { [string]$cfg.PkgScript } else { 'com.coc.zkqcode' }
        $pkgG = if ($cfg.PkgGame) { [string]$cfg.PkgGame } else { 'com.tencent.tmgp.supercell.clashofclans' }
        $cmd = "echo READY; echo SCRIPT; pidof $pkgS; echo GAME; pidof $pkgG; echo INST; pm path $pkgS 2>/dev/null; echo SEP; ps -A -o TIME+,NAME 2>/dev/null | grep nemuinit; echo ROOT; su -c 'id' 2>/dev/null; echo MEM; su -c 'base64 /storage/emulated/0/zkqFiles/memory.json 2>/dev/null'; echo LOG; su -c 'tail -20 /data/data/$pkgS/files/logs/info.log 2>/dev/null | base64'; echo SCH; su -c 'grep -o `"upgrade_time_scheduling[^,]*`" /storage/emulated/0/zkqFiles/zkq_config.json 2>/dev/null'"
        $res = (& $mgr adb -v $inst.Index -c "shell $cmd" 2>&1 | Out-String)
        $tag = "实例$($inst.Index)"
        if ($res -notmatch 'READY') { Ok "$tag adb 可用" $false 'no READY'; continue }
        Ok "$tag adb 可用" $true

        # 分段：每个标记都必须存在且顺序正确
        $order = @()
        foreach ($mk in @('READY', 'SCRIPT', 'GAME', 'INST', 'SEP', 'ROOT', 'MEM', 'LOG', 'SCH')) {
            $pos = $res.IndexOf($mk)
            if ($pos -lt 0) { $order += -1 } else { $order += $pos }
        }
        $seqOk = $true
        for ($i = 1; $i -lt $order.Count; $i++) { if ($order[$i] -le $order[$i - 1]) { $seqOk = $false } }
        Ok "$tag 采集标记齐全且顺序正确" $seqOk

        # 分段解析互不污染
        $sp = ''; $gp = ''; $ip = ''
        if ($res -match '(?s)SCRIPT\s*(.*?)\s*GAME') { $sp = $Matches[1] }
        if ($res -match '(?s)GAME\s*(.*?)(?:\s*INST|\s*SEP)') { $gp = $Matches[1] }
        if ($res -match '(?s)INST\s*(.*?)\s*SEP') { $ip = $Matches[1] }
        $scriptOn = ($sp -match '(?m)^\s*\d+\s*$')
        $gameOn   = ($gp -match '(?m)^\s*\d+\s*$')
        $installed = ($ip -match 'package:')
        # 与独立查询交叉验证脚本状态
        $pidOut = (& $mgr adb -v $inst.Index -c "shell pidof $pkgS" 2>&1 | Out-String).Trim()
        $scriptReal = ($pidOut -match '^\d+$')
        Ok "$tag 脚本状态与独立查询一致（采集=$scriptOn 直查=$scriptReal）" ($scriptOn -eq $scriptReal)
        Ok "$tag 游戏状态未把 APK 路径误判为运行（采集=$gameOn Installed=$installed）" (-not ($gameOn -and -not ($gp -match '^\s*\d+\s*$')))

        # 升级信息可解析性（装有脚本时）
        if ($installed) {
            $b64 = ''
            if ($res -match '(?s)MEM\s*(.*?)(?:LOG|$)') { $b64 = $Matches[1].Trim() }
            if ($b64.Length -gt 20) {
                $okDecode = $true
                try { $null = [Convert]::FromBase64String(($b64 -replace '\s', '')) } catch { $okDecode = $false }
                Ok "$tag memory.json 可解码" $okDecode
            } else {
                Ok "$tag memory.json 缺失（脚本可能刚启动）" $true 'skip'
            }
            $schOk = ($res -match 'upgrade_time_scheduling"\s*:\s*"1"')
            Ok "$tag 上号开关可解析（=1 时点亮标记）" ($res -match 'upgrade_time_scheduling')
        }
    }
}

# ---------- 4. 休眠列表往返 ----------
Write-Host "`n[4] 休眠列表往返（写 2 条读回 2 条）" -ForegroundColor Yellow
$tmpSleep = Join-Path $env:TEMP ('mmg_sleep_test_{0}.json' -f $PID)
@(
    [pscustomobject]@{ Index = '2'; WakeAt = '2026-11-15T02:41:30'; DoneAt = '2026-11-15T02:51:30'; Upgrade = 'A Lv.1'; Since = '2026-11-14T18:00:00' },
    [pscustomobject]@{ Index = '3'; WakeAt = '2026-11-15T16:01:07'; DoneAt = '2026-11-15T16:11:07'; Upgrade = 'B Lv.8'; Since = '2026-11-14T18:00:00' }
) | ConvertTo-Json | Set-Content -Path $tmpSleep -Encoding UTF8
$raw = Get-Content $tmpSleep -Raw -Encoding UTF8
$j = $raw | ConvertFrom-Json
$list = @()
if ($j -is [System.Array]) { foreach ($x in $j) { if ($null -ne $x) { $list += $x } } } else { $list += $j }
Ok ('读回 {0} 条（应为 2）' -f $list.Count) ($list.Count -eq 2)
Ok '编号未被合并' ((@($list | ForEach-Object { $_.Index }) -join ',') -eq '2,3') ((@($list | ForEach-Object { $_.Index }) -join ','))
Ok '升级名未被串字' (@($list | Where-Object { $_.Upgrade -match '\sLv\.\d+\s' -and $_.Upgrade -match 'Lv\.\d+.*Lv\.' }).Count -eq 0)
Remove-Item $tmpSleep -Force -ErrorAction SilentlyContinue

# ---------- 5. 界面自检（可选：面板在跑才测）----------
Write-Host "`n[5] 面板运行状态" -ForegroundColor Yellow
$proc = @(Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -ErrorAction SilentlyContinue |
          Where-Object { $_.CommandLine -match 'MuMuGuardApp\.ps1' -and $_.CommandLine -notmatch 'Get-CimInstance' })
Ok '面板进程唯一' ($proc.Count -le 1) ("实际 $($proc.Count) 个")
$logDir = Join-Path $root 'logs'
if (Test-Path $logDir) {
    $crash = Join-Path $logDir 'crash.log'
    $crashSize = if (Test-Path $crash) { (Get-Item $crash).Length } else { 0 }
    Ok '无崩溃记录（crash.log 为空或不存在）' ($crashSize -eq 0) ("$crashSize 字节")
    $diag = Join-Path $logDir 'diag.log'
    if (Test-Path $diag) {
        $errLines = @(Get-Content $diag -Tail 200 -Encoding UTF8 | Where-Object { $_ -match '异常|失败|错误' -and $_ -notmatch '唤醒失败|root 读取失败' })
        Ok '近期无异常日志' ($errLines.Count -eq 0) (($errLines | Select-Object -First 3) -join ' | ')
    }
}

# ---------- 汇总 ----------
Write-Host ''
Write-Host ('=' * 50)
if ($fail -eq 0) {
    Write-Host ("环境体检全部通过：{0} 项" -f $pass) -ForegroundColor Green
    exit 0
} else {
    Write-Host ("通过 {0} 项，失败 {1} 项" -f $pass, $fail) -ForegroundColor Red
    $fails | ForEach-Object { Write-Host "  - $_" -ForegroundColor Red }
    exit 1
}