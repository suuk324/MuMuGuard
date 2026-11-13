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

    # 回退：直接搜 nx_device\*\shell\adb.exe
    if (-not $info.AdbExe) {
        $cand = Get-ChildItem (Join-Path $Root 'nx_device') -Directory -ErrorAction SilentlyContinue |
                Sort-Object Name -Descending
        foreach ($c in $cand) {
            $p = Join-Path $c.FullName 'shell\adb.exe'
            if (Test-Path $p) {
                $info.AdbExe = $p
                if (-not $info.AndroidVer) { $info.AndroidVer = $c.Name }
                break
            }
        }
    }

    if (-not $info.VmsDir) {
        $p = Join-Path $Root 'vms'
        if (Test-Path $p) { $info.VmsDir = $p }
    }

    $mgr = Join-Path $Root 'nx_main\MuMuManager.exe'
    if (Test-Path $mgr) { $info.ManagerExe = $mgr }

    $info.Found = [bool]($info.AdbExe -and $info.ManagerExe)
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
        $a = $Aliases."$($Config.Index)"
        if ($a -and "$a".Trim()) { return "$a".Trim() }
    }
    if ($Config -and $Config.Name) { return [string]$Config.Name }
    if ($Config) { return "实例 $($Config.Index)" }
    return '实例 ?'
}