# 紫孔雀数据读取（只读）
# 数据源：每台实例 /sdcard/zkqFiles/memory.json
#   NextUpgrade<N>       当前升级：{dataId, name, lvl, completionTs}
#   DynamicGold<N>       金币
#   DynamicElixir<N>     圣水
#   DynamicDarkElixir<N> 黑油
#   UpgradeOverviewSig<N> 全部建筑 "dataId_等级,dataId_等级,..."
#   accountNumber        当前账号槽
# 本模块只读，不向设备写入任何内容。

$script:zkqCache = @{}      # index -> @{ At = [datetime]; Data = $obj; Error = '' }
$script:zkqRefreshSec = 20  # 同一实例最短刷新间隔

function Get-ZkqManagerPath {
    $root = ''
    try { $root = [string]$script:cfg.MuMuRoot } catch { }
    if (-not $root) { $root = 'D:\Program Files\Netease\MuMu' }
    $p = Join-Path $root 'nx_main\MuMuManager.exe'
    if (Test-Path $p) { return $p }
    return $null
}

# 直接从设备读原始 JSON 文本；实例没开或文件不存在时返回 $null
function Get-ZkqRawMemory([string]$Index) {
    $mm = Get-ZkqManagerPath
    if (-not $mm) { return $null }
    try {
        $out = & $mm adb -v $Index -c "shell cat /sdcard/zkqFiles/memory.json" 2>&1
    } catch { return $null }
    $txt = ($out | Out-String).Trim()
    if (-not $txt -or $txt -notmatch '^\s*\{') { return $null }
    # 某些情况下前面会混入 adb 的提示行，从第一个 { 开始截
    $i = $txt.IndexOf('{')
    if ($i -gt 0) { $txt = $txt.Substring($i) }
    return $txt
}

function ConvertFrom-ZkqMemory([string]$Json) {
    if (-not $Json) { return $null }
    $j = $null
    try { $j = $Json | ConvertFrom-Json } catch { return $null }
    if (-not $j) { return $null }

    $acct = 0
    try { $acct = [int]$j.accountNumber } catch { $acct = 0 }

    $res = [ordered]@{
        Account      = $acct
        NextName     = ''
        NextLevel    = 0
        NextComplete = $null
        Gold         = $null
        Elixir       = $null
        Dark         = $null
        Buildings    = @{}
        BuildingCount = 0
        Raw          = $j
    }

    # 账号槽可能和 accountNumber 不一致，逐个试 1..3
    $slots = @($acct, 1, 2, 3) | Where-Object { $_ -ge 1 } | Select-Object -Unique

    foreach ($s in $slots) {
        if (-not $res.NextName) {
            $nu = $null
            $prop = $j.PSObject.Properties | Where-Object { $_.Name -eq "NextUpgrade$s" } | Select-Object -First 1
            if ($prop -and $prop.Value) {
                try { $nu = "$($prop.Value)" | ConvertFrom-Json } catch { $nu = $null }
            }
            if ($nu) {
                $res.NextName = [string]$nu.name
                try { $res.NextLevel = [int]$nu.lvl } catch { }
                $ts = 0
                try { $ts = [double]$nu.completionTs } catch { }
                if ($ts -gt 0) {
                    $epoch = New-Object datetime 1970,1,1,0,0,0,([DateTimeKind]::Utc)
                    $res.NextComplete = $epoch.AddSeconds($ts).ToLocalTime()
                }
            }
        }
        if ($null -eq $res.Gold) {
            $g = $j.PSObject.Properties | Where-Object { $_.Name -eq "DynamicGold$s" } | Select-Object -First 1
            if ($g) { try { $res.Gold = [double]$g.Value } catch { } }
        }
        if ($null -eq $res.Elixir) {
            $e = $j.PSObject.Properties | Where-Object { $_.Name -eq "DynamicElixir$s" } | Select-Object -First 1
            if ($e) { try { $res.Elixir = [double]$e.Value } catch { } }
        }
        if ($null -eq $res.Dark) {
            $d = $j.PSObject.Properties | Where-Object { $_.Name -eq "DynamicDarkElixir$s" } | Select-Object -First 1
            if ($d) { try { $res.Dark = [double]$d.Value } catch { } }
        }
        if ($res.BuildingCount -eq 0) {
            $sig = $j.PSObject.Properties | Where-Object { $_.Name -eq "UpgradeOverviewSig$s" } | Select-Object -First 1
            if ($sig -and $sig.Value) {
                $map = @{}
                foreach ($part in ("$($sig.Value)" -split ',')) {
                    $kv = $part -split '_'
                    if ($kv.Count -eq 2) {
                        $id = $kv[0].Trim(); $lv = 0
                        if ([int]::TryParse($kv[1].Trim(), [ref]$lv)) { $map[$id] = $lv }
                    }
                }
                $res.Buildings = $map
                $res.BuildingCount = $map.Count
            }
        }
    }

    return [pscustomobject]$res
}

# 带缓存的状态读取：实例没开时返回缓存里的旧值（并标记 Stale）
function Get-ZkqState([string]$Index, [switch]$Force) {
    $now = Get-Date
    $c = $null
    if ($script:zkqCache.ContainsKey($Index)) { $c = $script:zkqCache[$Index] }
    if (-not $Force -and $c -and ($now - $c.At).TotalSeconds -lt $script:zkqRefreshSec) {
        return $c.Data
    }
    $raw = Get-ZkqRawMemory $Index
    if (-not $raw) {
        # 读不到：保留旧数据，标记过期
        if ($c -and $c.Data) {
            $old = $c.Data
            return [pscustomobject]@{
                Ok = $false; Stale = $true; At = $c.At
                Account = $old.Account; NextName = $old.NextName; NextLevel = $old.NextLevel
                NextComplete = $old.NextComplete; Gold = $old.Gold; Elixir = $old.Elixir
                Dark = $old.Dark; Buildings = $old.Buildings; BuildingCount = $old.BuildingCount
            }
        }
        return $null
    }
    $data = ConvertFrom-ZkqMemory $raw
    if (-not $data) { return $null }
    $data | Add-Member -NotePropertyName Ok -NotePropertyValue $true -Force
    $data | Add-Member -NotePropertyName Stale -NotePropertyValue $false -Force
    $data | Add-Member -NotePropertyName At -NotePropertyValue $now -Force
    $script:zkqCache[$Index] = @{ At = $now; Data = $data }
    return $data
}

# 把数字变成紧凑写法：754996 -> 75.5万
function Format-ZkqAmount($v) {
    if ($null -eq $v) { return '—' }
    $n = [double]$v
    if ($n -ge 100000000) { return ('{0:0.##}亿' -f ($n / 100000000)) }
    if ($n -ge 10000) { return ('{0:0.#}万' -f ($n / 10000)) }
    return ('{0:0}' -f $n)
}

# 剩余时间：completionTs -> "3天4小时" / "5分钟" / 已结束
function Format-ZkqRemain($CompleteAt) {
    if (-not $CompleteAt) { return '' }
    $span = $CompleteAt - (Get-Date)
    if ($span.TotalSeconds -le 0) { return '已完成' }
    if ($span.TotalDays -ge 1) { return ('{0}天{1}小时' -f [int][Math]::Floor($span.TotalDays), $span.Hours) }
    if ($span.TotalHours -ge 1) { return ('{0}小时{1}分' -f [int][Math]::Floor($span.TotalHours), $span.Minutes) }
    return ('{0}分钟' -f [Math]::Max(1, [int][Math]::Ceiling($span.TotalMinutes)))
}
# ---------------- 「升级时间上号」开关（读取/修改 紫孔雀 zkq_config.json）----------------
# 配置在每台模拟器各自的 /sdcard/zkqFiles/zkq_config.json
# 键 upgrade_time_scheduling："1" = 升级完成后按时间自动上号，"0" = 关闭
# 修改方式：在设备上跑一个 shell 脚本用 sed 原地替换这一个值，其余字节不动，
#          避免整文件往返把换行改成 CRLF、也避免破坏其它 1430 个键。

function Get-ZkqRawConfig([string]$Index) {
    $mm = Get-ZkqManagerPath
    if (-not $mm) { return $null }
    try {
        $out = & $mm adb -v $Index -c "shell cat /sdcard/zkqFiles/zkq_config.json" 2>&1
    } catch { return $null }
    $txt = ($out | Out-String)
    $i = $txt.IndexOf('{')
    if ($i -lt 0) { return $null }
    return $txt.Substring($i).Trim()
}

# 返回 $true=开启 $false=关闭 $null=读不到（实例没开/文件不存在）
function Get-ZkqUpgradeSchedule([string]$Index) {
    try {
        $raw = Get-ZkqRawConfig $Index
        if (-not $raw) { return $null }
        if ($raw -notmatch '"upgrade_time_scheduling"\s*:\s*"([^"]*)"') { return $null }
        return ($Matches[1].Trim() -eq '1')
    } catch { return $null }
}

# 改开关：推一个 sed 脚本上去执行，再读回校验；被紫孔雀回写就重试一次
function Set-ZkqUpgradeSchedule([string]$Index, [bool]$On) {
    $mm = Get-ZkqManagerPath
    if (-not $mm) { return $null }
    $cur = Get-ZkqUpgradeSchedule $Index
    if ($null -eq $cur) { return $null }
    if ($cur -eq $On) { return $true }

    $val = $(if ($On) { '1' } else { '0' })
    $shLocal = Join-Path $env:TEMP ('mmg-sched-' + [guid]::NewGuid().ToString('N').Substring(0, 8) + '.sh')
    $shDev = '/sdcard/zkqFiles/_mmg_sched.sh'

    # 用单引号模板 + 占位符替换：双引号 here-string 里的 $F 会被 PowerShell 吞掉
    $shTpl = @'
#!/system/bin/sh
F=/sdcard/zkqFiles/zkq_config.json
sed 's/"upgrade_time_scheduling": "[01]"/"upgrade_time_scheduling": "@VAL@"/' "$F" > /sdcard/zkqFiles/_mmg_new.json
if [ -s /sdcard/zkqFiles/_mmg_new.json ]; then
  cat /sdcard/zkqFiles/_mmg_new.json > "$F"
fi
rm -f /sdcard/zkqFiles/_mmg_new.json
'@
    $shText = $shTpl.Replace('@VAL@', $val)
    # shell 脚本必须用 LF，不能带 CR
    [System.IO.File]::WriteAllText($shLocal, $shText.Replace("`r`n", "`n"), (New-Object System.Text.UTF8Encoding $false))

    try {
        for ($try = 1; $try -le 2; $try++) {
            & $mm adb -v $Index -c "push `"$shLocal`" $shDev" 2>&1 | Out-Null
            & $mm adb -v $Index -c "shell su -c 'sh $shDev'" 2>&1 | Out-Null
            Start-Sleep -Milliseconds 500
            $after = Get-ZkqUpgradeSchedule $Index
            if ($after -eq $On) { return $true }
            Start-Sleep -Milliseconds 700
        }
        return $null
    } catch { return $null } finally {
        try { Remove-Item $shLocal -Force -ErrorAction SilentlyContinue } catch { }
        try { & $mm adb -v $Index -c "shell rm -f $shDev" 2>&1 | Out-Null } catch { }
    }
}
