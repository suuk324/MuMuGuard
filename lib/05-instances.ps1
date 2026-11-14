#Requires -Version 5.1
#
# 实例发现与配置读取（适配多开、MuMu 12/15、自定义名称）
# 供 MuMuGuardApp.ps1 dot-source（共享同一 $script: 作用域）

# 从 install_config.json 定位 MuMu 实际安装信息（支持 MuMu 12 / 15 等多引擎）
function Get-MuMuInstallInfo {
    param([string]$Root)

    $info = [pscustomobject]@{
        Found        = $false
        Root         = $Root
        Version      = ''
        AndroidVer   = ''
        AdbExe       = ''
        ManagerExe   = ''
        VmsDir       = ''
        InstallCfg   = ''
    }

    if (-not $Root) { return $info }

    $installCfg = Join-Path $env:APPDATA 'Netease\MuMuPlayer\install_config.json'
    if (Test-Path $installCfg) {
        $info.InstallCfg = $installCfg
        try {
            $j = Get-Content $installCfg -Raw -Encoding UTF8 | ConvertFrom-Json
            if ($j.product.version) { $info.Version = [string]$j.product.version }

            # 优先用 install_config 里登记的引擎目录
            if ($j.engines) {
                foreach ($eng in $j.engines.PSObject.Properties) {
                    $player = $eng.Value.player
                    if ($player -and $player.install_dir -and (Test-Path (Join-Path $player.install_dir 'adb.exe'))) {
                        $info.AdbExe = Join-Path $player.install_dir 'adb.exe'
                        if ($player.android_version) { $info.AndroidVer = [string]$player.android_version }
                        break
                    }
                }
                foreach ($eng in $j.engines.PSObject.Properties) {
                    $vms = $eng.Value.vms
                    if ($vms -and $vms.install_dir -and (Test-Path $vms.install_dir)) {
                        $info.VmsDir = [string]$vms.install_dir
                        break
                    }
                }
            }
        } catch { Write-Diag "解析 install_config.json 失败: $($_.Exception.Message)" }
    }

    # 回退：在安装目录里广泛搜索（MuMu 12 / 15 结构不同，逐个试）
    if (-not $info.AdbExe) {
        $probe = @()
        $probe += (Get-ChildItem (Join-Path $Root 'nx_device') -Directory -ErrorAction SilentlyContinue |
                   Sort-Object Name -Descending | ForEach-Object { Join-Path $_.FullName 'shell\adb.exe' })
        $probe += (Join-Path $Root 'shell\adb.exe')
        $probe += (Join-Path $Root 'adb.exe')
        $probe += (Get-ChildItem $Root -Directory -ErrorAction SilentlyContinue |
                   ForEach-Object { Join-Path $_.FullName 'shell\adb.exe' })
        foreach ($p in $probe) {
            if ($p -and (Test-Path $p)) { $info.AdbExe = $p; break }
        }
    }

    # 再不行就从 PATH 里找
    if (-not $info.AdbExe) {
        $cmd = Get-Command 'adb.exe' -ErrorAction SilentlyContinue
        if ($cmd) { $info.AdbExe = $cmd.Source }
    }

    if (-not $info.VmsDir) {
        foreach ($p in @((Join-Path $Root 'vms'), (Join-Path $Root 'MuMuPlayer-12.0\vms'), (Join-Path $Root 'MuMuPlayer\vms'))) {
            if (Test-Path $p) { $info.VmsDir = $p; break }
        }
    }

    # MuMuManager 位置也做多种尝试
    foreach ($p in @(
        (Join-Path $Root 'nx_main\MuMuManager.exe'),
        (Join-Path $Root 'MuMuManager.exe'),
        (Join-Path $Root 'shell\MuMuManager.exe'),
        (Join-Path $Root 'nx_device\MuMuManager.exe')
    )) {
        if (Test-Path $p) { $info.ManagerExe = $p; break }
    }

    # 仍然没找到？从 adb 路径反推安装根（MuMu 装在别的盘时 $Root 可能是旧值）
    if (-not $info.ManagerExe -and $info.AdbExe) {
        try {
            $p = $info.AdbExe
            # ...\nx_device\<版本>\shell\adb.exe  → 往上三层就是安装根
            $pRoot = Split-Path (Split-Path (Split-Path (Split-Path $p -Parent) -Parent) -Parent) -Parent
            foreach ($cand in @(
                (Join-Path $pRoot 'nx_main\MuMuManager.exe'),
                (Join-Path $pRoot 'MuMuManager.exe')
            )) {
                if (Test-Path $cand) { $info.ManagerExe = $cand; $info.Root = $pRoot; break }
            }
        } catch { }
    }

    # 只要找到 MuMuManager 就可用（adb 只是兜底通道）
    $info.Found = [bool]($info.ManagerExe -or $info.AdbExe)
    return $info
}

# 扫描所有实例目录，读取名称 / 内存 / CPU / adb 端口 / root
function Get-InstanceConfigs {
    param([string]$VmsDir)

    $list = @()
    if (-not $VmsDir -or -not (Test-Path $VmsDir)) { return $list }

    $dirs = Get-ChildItem $VmsDir -Directory -Filter 'MuMuPlayer-*' -ErrorAction SilentlyContinue
    foreach ($d in $dirs) {
        # 目录名形如 MuMuPlayer-15.0-3 / MuMuPlayer-12.0-0
        if ($d.Name -notmatch 'MuMuPlayer-([\d\.]+)-(\d+)$') { continue }
        $series = $Matches[1]
        $index  = $Matches[2]

        $cfgDir = Join-Path $d.FullName 'configs'
        $entry = [pscustomobject]@{
            Index       = $index
            Series      = $series
            Dir         = $d.FullName
            Name        = ''
            MemoryGB    = 0
            Cpu         = 0
            AdbPort     = 0
            Root        = $false
            MemBaseMB   = 0
        }

        # 名称与机型信息
        $extra = Join-Path $cfgDir 'extra_config.json'
        if (Test-Path $extra) {
            try {
                $j = Get-Content $extra -Raw -Encoding UTF8 | ConvertFrom-Json
                if ($j.playerName) { $entry.Name = [string]$j.playerName }
                if ($j.series -and -not $entry.Series) { $entry.Series = [string]$j.series }
            } catch { }
        }

        # 内存 / CPU / 端口 / root
        $vmCfg = Join-Path $cfgDir 'vm_config.json'
        if (Test-Path $vmCfg) {
            try {
                $j = Get-Content $vmCfg -Raw -Encoding UTF8 | ConvertFrom-Json
                if ($j.vm.memory) { $entry.MemoryGB = [int]$j.vm.memory }
                if ($j.vm.cpu)    { $entry.Cpu      = [int]$j.vm.cpu }
                if ($j.vm.root)   { $entry.Root     = ("$($j.vm.root)" -eq 'true') }
                $port = $j.vm.nat.port_forward.adb.host_port
                if ($port) { $entry.AdbPort = [int]$port }
            } catch { }
        }

        if (-not $entry.Name) { $entry.Name = "实例 $index" }

        # 环的满刻度：客户机内存 + 图形/转译开销
        $entry.MemBaseMB = Get-InstanceMemBase -MemoryGB $entry.MemoryGB

        $list += $entry
    }

    return @($list | Sort-Object { [int]$_.Index })
}


# 显示名：本地别名 > MuMu 的 playerName > 实例 N
function Get-InstanceDisplayName {
    param($Config, $Aliases)

    if ($Aliases -and $Config) {
        # 优先用稳定键（MuMu 创建时间戳）：实例重新编号后别名不会串到别的实例上
        $sid = $null
        if ($Config.PSObject.Properties.Name -contains 'StableId') { $sid = "$($Config.StableId)" }
        if ($sid) {
            $a = $Aliases."$sid"
            if ($a -and "$a".Trim()) { return "$a".Trim() }
        }
        $a = $Aliases."$($Config.Index)"
        if ($a -and "$a".Trim()) { return "$a".Trim() }
    }
    if ($Config -and $Config.Name) { return [string]$Config.Name }
    if ($Config) { return "实例 $($Config.Index)" }
    return '实例 ?'
}

# 用 MuMuManager 查询所有实例（最可靠的来源：不依赖目录结构，安卓 12/15 通用）
# 返回 编号 -> 信息对象
function Get-MuMuInfoAll {
    param([string]$ManagerExe)

    $map = @{}
    if (-not $ManagerExe -or -not (Test-Path $ManagerExe)) { return $map }

    $raw = Invoke-CaptureUtf8 -Exe $ManagerExe -ArgList @('info', '-v', 'all')
    if (-not $raw -or -not $raw.Trim()) {
        Write-Diag 'MuMuManager info 无输出'
        return $map
    }
    try { $j = $raw | ConvertFrom-Json } catch {
        Write-Diag "MuMuManager info 返回无法解析: $($raw.Substring(0, [Math]::Min(200, $raw.Length)))"
        return $map
    }

    foreach ($p in $j.PSObject.Properties) {
        $v = $p.Value
        if (-not $v) { continue }
        $idx = "$($v.index)"
        if (-not $idx) { $idx = "$($p.Name)" }
        $map[$idx] = $v
    }
    return $map
}

# 用 MuMuManager 执行 adb 命令（不依赖 adb.exe 路径与端口映射）
# 返回 @{ Ok; Output; Error }
function Invoke-MuMuAdb {
    param(
        [string]$ManagerExe,
        [string]$Index,
        [string]$ShellCmd,
        [int]$TimeoutSec = 20
    )

    if (-not $ManagerExe -or -not (Test-Path $ManagerExe)) {
        return [pscustomobject]@{ Ok = $false; Output = ''; Error = '缺少 MuMuManager.exe' }
    }

    try {
        $out = (& $ManagerExe adb -v $Index -c "shell $ShellCmd" 2>&1 | Out-String)
        if ($null -eq $out) { $out = '' }
        return [pscustomobject]@{ Ok = $true; Output = $out; Error = '' }
    } catch {
        return [pscustomobject]@{ Ok = $false; Output = ''; Error = $_.Exception.Message }
    }
}

# 合并 MuMuManager 的信息到实例配置（名称/端口/安卓版本以 manager 为准）
function Merge-InstanceInfo {
    param($Configs, $InfoMap)

    if (-not $InfoMap -or $InfoMap.Count -eq 0) { return $Configs }

    foreach ($c in $Configs) {
        $k = "$($c.Index)"
        if (-not $InfoMap.ContainsKey($k)) { continue }
        $info = $InfoMap[$k]
        if ($info.name) { $c.Name = [string]$info.name }
        if ($info.adb_port) { $c.AdbPort = [int]$info.adb_port }
        if ($info.android_version) { $c.Series = [string]$info.android_version }
        if ($info.created_timestamp) {
            # MuMu 的创建时间戳，用于别名稳定绑定（实例重新编号也不串）
            $sid = [string]$info.created_timestamp
            if ($c.PSObject.Properties.Name -contains 'StableId') { $c.StableId = $sid }
            else { $c | Add-Member -NotePropertyName StableId -NotePropertyValue $sid -Force }
        }

        # 配置对象里没有这些字段，动态补上（避免属性不存在报错）
        foreach ($pair in @(
            @{ K = 'Running';        V = [bool]$info.is_process_started },
            @{ K = 'AndroidStarted'; V = [bool]$info.is_android_started },
            @{ K = 'State';          V = "$($info.player_state)" }
        )) {
            if ($c.PSObject.Properties.Name -contains $pair.K) { $c.($pair.K) = $pair.V }
            else { $c | Add-Member -NotePropertyName $pair.K -NotePropertyValue $pair.V -Force }
        }
    }
    return $Configs
}

# 重新扫描实例列表（面板运行期间新开/关闭模拟器无需重启）
# 返回 $true 表示实例数量或编号有变化
function Update-InstanceList {
    param([string]$VmsDir, [string]$ManagerExe)

    $list = @(Get-InstanceConfigs -VmsDir $VmsDir)
    $info = Get-MuMuInfoAll -ManagerExe $ManagerExe
    if ($info.Count -gt 0) { $list = Merge-InstanceInfo -Configs $list -InfoMap $info }

    $oldIdx = (@($script:instances | ForEach-Object { "$($_.Index)" }) -join ',')
    $newIdx = (@($list | ForEach-Object { "$($_.Index)" }) -join ',')

    $script:instances = $list
    $script:instanceMap = @{}
    foreach ($ic in $script:instances) { $script:instanceMap["$($ic.Index)"] = $ic }

    # 采集线程的清单跟着更新（新开或关掉的实例都能自动生效）
    try {
        $script:adbSync.Devices = @($list | Where-Object {
            $r = $true
            if ($_.PSObject.Properties.Name -contains 'Running') { $r = ($_.Running -eq $true) }
            $r
        } | ForEach-Object { [pscustomobject]@{ Index = $_.Index; Port = $_.AdbPort } })
    } catch { }

    if ($oldIdx -ne $newIdx) {
        Write-Diag ("实例列表已更新：{0}" -f $newIdx)
        try { $script:cardMap = @{}; if ($pnlCards) { [void]$pnlCards.Children.Clear() } } catch { }
        try { $script:cmpMap = @{}; if ($cmpRings) { [void]$cmpRings.Children.Clear() } } catch { }
        return $true
    }
    return $false
}