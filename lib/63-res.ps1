# 游戏界面资源读取（OCR，只读）
# 只在游戏在前台时才有意义；读不到就返回 $null，绝不编造数字。
# 世界判定：主世界 4 条资源槽（国服 5 条，多一个点券），夜世界 3 条（国服 4 条），
#           资源槽永远在右上角这一列的最上面，下面多出来的行是建造工人计时/计数。
# 国服与国际服靠前台包名区分，不靠画面猜。

$script:resCache = @{}
$script:resMinGapSec = 60
$script:resSamples = @{}
$script:resSampleMax = 8
$script:resSampleInterval = 3

# ---------------- Windows 自带 OCR（WinRT）----------------
try { Add-Type -AssemblyName System.Runtime.WindowsRuntime -ErrorAction Stop } catch { }
try { $null = [Windows.Storage.StorageFile, Windows.Foundation, ContentType = WindowsRuntime] } catch { }
try { $null = [Windows.Graphics.Imaging.BitmapDecoder, Windows.Foundation, ContentType = WindowsRuntime] } catch { }
try { $null = [Windows.Media.Ocr.OcrEngine, Windows.Foundation, ContentType = WindowsRuntime] } catch { }
try { $null = [Windows.Globalization.Language, Windows.Foundation, ContentType = WindowsRuntime] } catch { }

$script:ocrAsTask = $null
try {
    $script:ocrAsTask = ([System.WindowsRuntimeSystemExtensions].GetMethods() | Where-Object {
        $_.Name -eq 'AsTask' -and $_.GetParameters().Count -eq 1 -and $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncOperation`1'
    })[0]
} catch { }
$script:ocrEngines = @{}

function Await-Op($Op, $ResultType) {
    $task = $script:ocrAsTask.MakeGenericMethod($ResultType).Invoke($null, @($Op))
    $task.Wait(-1) | Out-Null
    return $task.Result
}

function Get-OcrEngine([string]$LangTag) {
    if ($script:ocrEngines.ContainsKey($LangTag)) { return $script:ocrEngines[$LangTag] }
    $eng = $null
    try {
        $lang = New-Object Windows.Globalization.Language $LangTag
        $eng = [Windows.Media.Ocr.OcrEngine]::TryCreateFromLanguage($lang)
    } catch { $eng = $null }
    $script:ocrEngines[$LangTag] = $eng
    return $eng
}

function Invoke-WinOcr([string]$Path, [string]$LangTag) {
    if (-not $script:ocrAsTask) { return '' }
    $eng = Get-OcrEngine $LangTag
    if (-not $eng) { return '' }
    try {
        $file = Await-Op ([Windows.Storage.StorageFile]::GetFileFromPathAsync($Path)) ([Windows.Storage.StorageFile])
        $stream = Await-Op ($file.OpenAsync([Windows.Storage.FileAccessMode]::Read)) ([Windows.Storage.Streams.IRandomAccessStream])
        $decoder = Await-Op ([Windows.Graphics.Imaging.BitmapDecoder]::CreateAsync($stream)) ([Windows.Graphics.Imaging.BitmapDecoder])
        $bitmap = Await-Op ($decoder.GetSoftwareBitmapAsync()) ([Windows.Graphics.Imaging.SoftwareBitmap])
        $res = Await-Op ($eng.RecognizeAsync($bitmap)) ([Windows.Media.Ocr.OcrResult])
        $txt = ($res.Lines | ForEach-Object { $_.Text }) -join ' '
        try { $stream.Dispose() } catch { }
        return $txt
    } catch { return '' }
}

# ---------------- adb：设备定位与截图 ----------------
function Get-AdbExePath {
    try { if ($script:AdbExe -and (Test-Path $script:AdbExe)) { return $script:AdbExe } } catch { }
    try {
        $root = [string]$script:cfg.MuMuRoot
        if ($root) {
            foreach ($v in @('15.0', '12.0')) {
                $c = Join-Path $root "nx_device\$v\shell\adb.exe"
                if (Test-Path $c) { return $c }
            }
        }
    } catch { }
    return $null
}

function Get-DeviceSerial([string]$Index) {
    try {
        $s = [string]$script:adbSync.Data[$Index].Serial
        if ($s -and $s -ne '') { return $s }
    } catch { }
    try {
        $c = $null
        if ($script:instanceMap -and $script:instanceMap.ContainsKey("$Index")) { $c = $script:instanceMap["$Index"] }
        if ($c -and $c.AdbPort) { return ("127.0.0.1:" + [int]$c.AdbPort) }
    } catch { }
    try {
        $root = [string]$script:cfg.MuMuRoot
        $vms = Join-Path $root 'vms'
        if (Test-Path $vms) {
            $dir = Get-ChildItem $vms -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -match ('-' + [regex]::Escape("$Index") + '$') } | Select-Object -First 1
            if ($dir) {
                $vmc = Join-Path $dir.FullName 'configs\vm_config.json'
                if (Test-Path $vmc) {
                    $j = Get-Content $vmc -Raw -Encoding UTF8 | ConvertFrom-Json
                    $port = $j.vm.nat.port_forward.adb.host_port
                    if ($port) { return ("127.0.0.1:" + [int]$port) }
                }
            }
        }
    } catch { }
    return $null
}

function Get-ForegroundPkg([string]$Index) {
    $adb = Get-AdbExePath
    $serial = Get-DeviceSerial $Index
    if (-not $adb -or -not $serial) { return '' }
    try {
        $o = (& $adb -s $serial shell "dumpsys activity activities | grep topResumedActivity | head -1" 2>&1) -join ' '
        if ($o -match '([A-Za-z0-9_.]+)/') { return $Matches[1] }
    } catch { }
    return ''
}

function Get-GameVersionByFg([string]$FgPkg) {
    if ($FgPkg -eq 'com.tencent.tmgp.supercell.clashofclans') { return 'cn' }
    if ($FgPkg -eq 'com.supercell.clashofclans') { return 'global' }
    return ''
}

function Test-GameForeground([string]$Index) {
    $fg = Get-ForegroundPkg $Index
    if (-not $fg) { return $false }
    return ($fg -eq 'com.tencent.tmgp.supercell.clashofclans') -or ($fg -eq 'com.supercell.clashofclans')
}

function Save-DeviceScreenshot([string]$Index) {
    $adb = Get-AdbExePath
    if (-not $adb) { return $null }
    $serial = Get-DeviceSerial $Index
    if (-not $serial) { return $null }
    $tmp = Join-Path $env:TEMP ('mmg-shot-' + [guid]::NewGuid().ToString('N').Substring(0, 8) + '.png')
    $remote = '/sdcard/mmg_tmp_shot.png'
    try {
        & $adb -s $serial shell screencap -p $remote 2>&1 | Out-Null
        & $adb -s $serial pull $remote $tmp 2>&1 | Out-Null
        & $adb -s $serial shell rm $remote 2>&1 | Out-Null
        if (Test-Path $tmp) { return $tmp }
    } catch { }
    return $null
}

# ---------------- 画面有效性判断 ----------------
# 被弹窗压暗/遮挡时整块会变暗，这时读出来全是垃圾值
function Test-BarReadable([System.Drawing.Bitmap]$Bmp) {
    if (-not $Bmp) { return $false }
    $x0 = [int]($Bmp.Width * 0.85)
    $x1 = [int]($Bmp.Width * 0.95)
    $yLimit = [int]($Bmp.Height * 0.30)
    if ($x1 -le $x0) { return $false }
    for ($y = 0; $y -lt $yLimit; $y++) {
        for ($x = $x0; $x -lt $x1; $x += 2) {
            $c = $Bmp.GetPixel($x, $y)
            $lum = 0.299 * $c.R + 0.587 * $c.G + 0.114 * $c.B
            if ($lum -ge 210) { return $true }
        }
    }
    return $false
}

# ---------------- 找资源条位置 ----------------
function Find-NumberBands([System.Drawing.Bitmap]$Bmp) {
    $bands = @()
    $yLimit = [int]($Bmp.Height * 0.42)
    $x0 = [int]($Bmp.Width * 0.84)
    $x1 = [int]($Bmp.Width * 0.975)
    $stepX = [Math]::Max(1, [int](($x1 - $x0) / 60))
    $inBand = $false; $startY = 0
    for ($y = 0; $y -lt $yLimit; $y++) {
        $cnt = 0
        for ($x = $x0; $x -lt $x1; $x += $stepX) {
            $c = $Bmp.GetPixel($x, $y)
            $lum = 0.299 * $c.R + 0.587 * $c.G + 0.114 * $c.B
            if ($lum -gt 200) { $cnt++ }
        }
        if ($cnt -ge 3 -and -not $inBand) { $inBand = $true; $startY = $y }
        elseif ($cnt -lt 3 -and $inBand) {
            $inBand = $false
            if (($y - $startY) -ge 8 -and ($y - $startY) -le 40) { $bands += @{ Y0 = $startY; Y1 = $y } }
        }
    }
    return $bands
}

# 资源槽是等间距的一列，从最上面开始连续取
function Group-ResourceBands($Bands) {
    $arr = @($Bands | Sort-Object { $_.Y0 })
    if ($arr.Count -eq 0) { return @() }
    $keep = @($arr[0])
    for ($i = 1; $i -lt $arr.Count; $i++) {
        $gap = $arr[$i].Y0 - $arr[$i - 1].Y0
        $h1 = $arr[$i - 1].Y1 - $arr[$i - 1].Y0
        $h2 = $arr[$i].Y1 - $arr[$i].Y0
        if ($gap -lt 30 -or $gap -gt 75) { break }
        if ([Math]::Abs($h2 - $h1) -gt 16) { break }
        $keep += $arr[$i]
    }
    return $keep
}

# 整列一次性 OCR：资源条整块裁下来识别一次（实测比逐条稳，且快）
function Get-OcrLines([string]$Path, [string]$LangTag) {
    if (-not $script:ocrAsTask) { return @() }
    $eng = Get-OcrEngine $LangTag
    if (-not $eng) { return @() }
    try {
        $file = Await-Op ([Windows.Storage.StorageFile]::GetFileFromPathAsync($Path)) ([Windows.Storage.StorageFile])
        $stream = Await-Op ($file.OpenAsync([Windows.Storage.FileAccessMode]::Read)) ([Windows.Storage.Streams.IRandomAccessStream])
        $decoder = Await-Op ([Windows.Graphics.Imaging.BitmapDecoder]::CreateAsync($stream)) ([Windows.Graphics.Imaging.BitmapDecoder])
        $bitmap = Await-Op ($decoder.GetSoftwareBitmapAsync()) ([Windows.Graphics.Imaging.SoftwareBitmap])
        $res = Await-Op ($eng.RecognizeAsync($bitmap)) ([Windows.Media.Ocr.OcrResult])
        $lines = @()
        foreach ($ln in $res.Lines) { $lines += $ln.Text }
        try { $stream.Dispose() } catch { }
        return $lines
    } catch { return @() }
}

function Read-ResourceColumn([System.Drawing.Bitmap]$Bmp, $Bands) {
    $arr = @($Bands | Sort-Object { $_.Y0 })
    if ($arr.Count -lt 2) { return @() }
    $y0 = [Math]::Max(0, $arr[0].Y0 - 4)
    $y1 = [Math]::Min($Bmp.Height - 1, $arr[$arr.Count - 1].Y1 + 6)
    $x0 = [int]($Bmp.Width * 0.845)
    $x1 = [int]($Bmp.Width * 0.975)
    $w = $x1 - $x0; $h = $y1 - $y0
    if ($w -lt 40 -or $h -lt 30) { return @() }
    $avgH = 0
    foreach ($b in $arr) { $avgH += ($b.Y1 - $b.Y0) }
    $avgH = $avgH / $arr.Count
    $scale = [Math]::Max(3, [int](70 / [Math]::Max(1, $avgH)))
    $tmp = Join-Path $env:TEMP ('mmg-col-' + [guid]::NewGuid().ToString('N').Substring(0, 8) + '.png')
    $byLang = @{}
    try {
        $crop = New-Object System.Drawing.Bitmap ($w * $scale), ($h * $scale)
        $g = [System.Drawing.Graphics]::FromImage($crop)
        $g.InterpolationMode = 'HighQualityBicubic'
        $g.DrawImage($Bmp, (New-Object System.Drawing.Rectangle 0, 0, ($w * $scale), ($h * $scale)),
                     (New-Object System.Drawing.Rectangle $x0, $y0, $w, $h), [System.Drawing.GraphicsUnit]::Pixel)
        $g.Dispose()
        $crop.Save($tmp, [System.Drawing.Imaging.ImageFormat]::Png)
        $crop.Dispose()
        foreach ($lang in @('en-US', 'zh-Hans-CN')) {
            $vals = @()
            $lines = @(Get-OcrLines $tmp $lang)
            foreach ($ln in $lines) {
                if (-not $ln) { continue }
                $l2 = [regex]::Replace($ln, '[\u4e00-\u9fa5]', '')
                if (-not $l2) { continue }
                $v = ConvertTo-BestDigits @($l2) 9
                if ($null -ne $v) { $vals += $v }
            }
            $byLang[$lang] = $vals
        }
    } catch { } finally {
        try { Remove-Item $tmp -Force -ErrorAction SilentlyContinue } catch { }
    }
    # 两种语言按行位置合并：同一行取位数更多的那个（更可能是完整数字）
    $en = @($byLang['en-US'])
    $zh = @($byLang['zh-Hans-CN'])
    $n = [Math]::Max($en.Count, $zh.Count)
    $merged = @()
    for ($i = 0; $i -lt $n; $i++) {
        $a = $(if ($i -lt $en.Count) { $en[$i] } else { $null })
        $b = $(if ($i -lt $zh.Count) { $zh[$i] } else { $null })
        $lens = { param($x) if ($null -eq $x) { return -1 } else { return ("$([long]$x)").Length } }
        $la = & $lens $a
        $lb = & $lens $b
        if ($la -ge $lb) { $merged += $a } else { $merged += $b }
    }
    return $merged
}

# ---------------- OCR 文本纠正 ----------------
# COC 字体常被认成字母（0->O、5->S、8->B…）
function Repair-OcrDigits([string]$Text) {
    if (-not $Text) { return '' }
    $t = $Text
    $t = $t -creplace 'O', '0'
    $t = $t -creplace 'o', '0'
    $t = $t -creplace 'Q', '0'
    $t = $t -creplace 'D', '0'
    $t = $t -creplace 'I', '1'
    $t = $t -creplace 'l', '1'
    $t = $t -creplace 'i', '1'
    # 竖线/感叹号这类符号不映射成 1，否则会造出假的高位数字
    # （原先的 ! -> 1 曾把 "!41300 ooo" 变成 141300000）
    $t = $t -creplace 'S', '5'
    $t = $t -creplace 's', '5'
    $t = $t -creplace 'B', '8'
    $t = $t -creplace 'b', '8'
    $t = $t -creplace 'Z', '2'
    $t = $t -creplace 'z', '2'
    $t = $t -creplace 'G', '6'
    $t = $t -creplace 'g', '9'
    $t = $t -creplace 'q', '9'
    $t = $t -creplace 'T', '7'
    return $t
}

function ConvertTo-BestDigits([string[]]$Cands, [int]$MaxDigits) {
    $best = ''
    foreach ($c in $Cands) {
        if (-not $c) { continue }
        if ($c -match '[\u4e00-\u9fa5]') { continue }
        $fixed = Repair-OcrDigits $c
        $d = ($fixed -replace '[^0-9]', '')
        if ($d.Length -lt 1 -or $d.Length -gt $MaxDigits) { continue }
        if ($d.Length -gt 1 -and $d.StartsWith('0')) { continue }
        if ($d.Length -eq 1 -and $d -ne '0') { continue }
        if ($d.Length -gt $best.Length) { $best = $d }
    }
    if (-not $best) { return $null }
    return [double]$best
}

# 多候选多数投票：同一个数字被不同方式识别多次，取出现最多的那个（票数相同取位数多的）
function Select-BestValue([double[]]$Cands) {
    $valid = @($Cands | Where-Object { $null -ne $_ })
    if ($valid.Count -eq 0) { return $null }
    $groups = @{}
    foreach ($v in $valid) {
        $k = "$([long]$v)"
        if (-not $groups.ContainsKey($k)) { $groups[$k] = 0 }
        $groups[$k] = $groups[$k] + 1
    }
    $bestKey = $null; $bestVotes = -1; $bestLen = -1
    foreach ($k in $groups.Keys) {
        $votes = $groups[$k]
        $len = $k.Length
        if ($votes -gt $bestVotes -or ($votes -eq $bestVotes -and $len -gt $bestLen)) {
            $bestKey = $k; $bestVotes = $votes; $bestLen = $len
        }
    }
    if (-not $bestKey) { return $null }
    return [double]$bestKey
}

# 这条带是不是资源值（不是「3小时46分钟」这种计时行）
function Test-BandIsNumeric([string[]]$Texts) {
    # 只看英文引擎那段（Get-BandTexts 里英文在前）：
    # 英文结果里出现汉字，说明这行是「3小时46分钟」这类计时行，不是资源
    $en = ''
    if ($Texts.Count -ge 1) { $en = "$($Texts[0])" }
    if ($en -and ($en -match '[\u4e00-\u9fa5]')) { return $false }
    foreach ($t in $Texts) {
        if (-not $t) { continue }
        if ($t -match '[\u4e00-\u9fa5]') { continue }   # 中文引擎的杂字忽略
        $fixed = Repair-OcrDigits $t
        $d = ($fixed -replace '[^0-9]', '')
        if ($d.Length -ge 2) { return $true }
    }
    return $false
}

# ---------------- 单条数值带读取 ----------------
function Get-BandTexts([System.Drawing.Bitmap]$Bmp, $Band) {
    $y0 = [Math]::Max(0, $Band.Y0 - 3)
    $y1 = [Math]::Min($Bmp.Height - 1, $Band.Y1 + 3)
    $bh = $y1 - $y0
    if ($bh -lt 6) { return @() }
    # 实测：固定 0.855~0.975 裁切 + 放大 5 倍以上，英文引擎最稳（宝石那种「6」不会被认成「5」）
    $x0 = [int]($Bmp.Width * 0.855)
    $x1 = [int]($Bmp.Width * 0.975)
    $w = $x1 - $x0
    if ($w -lt 8) { return @() }
    $scale = [Math]::Max(5, [int](64 / [Math]::Max(1, $bh)))
    $texts = @()
    $tmp = Join-Path $env:TEMP ('mmg-band-' + [guid]::NewGuid().ToString('N').Substring(0, 8) + '.png')
    try {
        $crop = New-Object System.Drawing.Bitmap ($w * $scale), ($bh * $scale)
        $g = [System.Drawing.Graphics]::FromImage($crop)
        $g.InterpolationMode = 'HighQualityBicubic'
        $g.DrawImage($Bmp, (New-Object System.Drawing.Rectangle 0, 0, ($w * $scale), ($bh * $scale)),
                     (New-Object System.Drawing.Rectangle $x0, $y0, $w, $bh), [System.Drawing.GraphicsUnit]::Pixel)
        $g.Dispose()
        $crop.Save($tmp, [System.Drawing.Imaging.ImageFormat]::Png)
        $crop.Dispose()
        $t = Invoke-WinOcr $tmp 'en-US'
        if ($t) { $texts += $t }
        $t2 = Invoke-WinOcr $tmp 'zh-Hans-CN'
        if ($t2) { $texts += $t2 }
    } catch { } finally {
        try { Remove-Item $tmp -Force -ErrorAction SilentlyContinue } catch { }
    }
    return $texts
}

# ---------------- 世界判定 ----------------
function Get-ExpectedBarCount([string]$GameVer, [string]$World) {
    if ($GameVer -eq 'cn') { if ($World -eq 'main') { return 5 } else { return 4 } }
    if ($GameVer -eq 'global') { if ($World -eq 'main') { return 4 } else { return 3 } }
    return 0
}

# 资源槽在最上面；用「第 N+1 条不是资源行」来验证某个世界假设
function Resolve-World([string]$GameVer, [int]$TotalBands) {
    if (-not $GameVer -or $TotalBands -le 0) { return $null }
    # 主世界条数多，先试主世界；带数够就算成立（下面多出来的计时行不影响）
    $nMain = Get-ExpectedBarCount $GameVer 'main'
    if ($nMain -gt 0 -and $TotalBands -ge $nMain) { return [pscustomobject]@{ World = 'main'; Bars = $nMain } }
    $nBb = Get-ExpectedBarCount $GameVer 'bb'
    if ($nBb -gt 0 -and $TotalBands -ge $nBb) { return [pscustomobject]@{ World = 'bb'; Bars = $nBb } }
    return $null
}

# ---------------- 主入口 ----------------
function Get-GameResources([string]$Index, [switch]$Force) {
    $now = Get-Date
    if (-not $Force -and $script:resCache.ContainsKey($Index)) {
        $c = $script:resCache[$Index]
        if (($now - $c.At).TotalSeconds -lt $script:resMinGapSec) { return $c.Data }
    }

    $png = Save-DeviceScreenshot $Index
    if (-not $png) { return $null }
    $result = $null
    try {
        Add-Type -AssemblyName System.Drawing -ErrorAction SilentlyContinue
        $bmp = [System.Drawing.Bitmap]::FromFile($png)

        # 游戏是横屏；竖屏说明停在桌面
        if ($bmp.Height -gt $bmp.Width) {
            Write-Diag "资源 OCR：画面不是游戏（竖屏），跳过"
            try { $bmp.Dispose() } catch { }
            $bmp = $null
        }
        if ($bmp -and -not (Test-BarReadable $bmp)) {
            Write-Diag "资源 OCR：画面被遮挡或压暗，跳过"
            try { $bmp.Dispose() } catch { }
            $bmp = $null
        }

        if ($bmp) {
            try {
                $rawBands = @(Find-NumberBands $bmp)
                $group = @(Group-ResourceBands $rawBands)
                $fgPkg = Get-ForegroundPkg $Index
                $gameVer = Get-GameVersionByFg $fgPkg
                # 整列一次 OCR（实测最稳）
                # 整列识别一次
                # 整列识别（快）+ 逐条识别（准）；整列没读出来的行用逐条补
                # 整列识别（快）为主；某行读不出来、或明显被截短时，用逐条识别补
                $colVals = @(Read-ResourceColumn $bmp $group)
                $nums = @()
                for ($ri = 0; $ri -lt $group.Count; $ri++) {
                    $col = $null
                    if ($ri -lt $colVals.Count) { $col = $colVals[$ri] }
                    $band = $null
                    if ($null -eq $col) {
                        $texts = @(Get-BandTexts $bmp $group[$ri])
                        if (Test-BandIsNumeric $texts) { $band = ConvertTo-BestDigits $texts 9 }
                        $nums += , $band
                        continue
                    }
                    # 整列值如果只是逐条值的前缀（被截断），用逐条那个更完整的
                    $texts2 = @(Get-BandTexts $bmp $group[$ri])
                    if (Test-BandIsNumeric $texts2) { $band = ConvertTo-BestDigits $texts2 9 }
                    if ($null -ne $band) {
                        $sc = "$([long]$col)"; $sb = "$([long]$band)"
                        if ($sb.Length -gt $sc.Length -and $sb.StartsWith($sc)) { $col = $band }
                    }
                    $nums += , $col
                }
                # 保留空位：资源行位置必须和世界对应，不能把空值压掉
                $res = Resolve-World $gameVer $group.Count
                if (-not $res) {
                    Write-Diag ("资源采样：认不出世界（版本={0} 带数={1} 数字={2}）" -f $gameVer, $group.Count, $nums.Count)
                } else {
                    $n = [int]$res.Bars
                    $vals = @($nums | Select-Object -First $n)
                    $usable = ($vals.Count -ge 2) -and ($null -ne $vals[0]) -and ($null -ne $vals[1])
                    if (-not $usable) {
                        Write-Diag ("资源采样：数字不够（世界={0} 带数={1} 数字={2}）" -f $res.World, $group.Count, $nums.Count)
                    } else {
                        $v1 = $vals[0]
                        $v2 = $vals[1]
                        $v3 = $(if ($vals.Count -ge 3) { $vals[2] } else { $null })
                        $v4 = $(if ($vals.Count -ge 4) { $vals[3] } else { $null })
                        $v5 = $(if ($vals.Count -ge 5) { $vals[4] } else { $null })
                        if ($res.World -eq 'main') {
                            $result = [pscustomobject]@{
                                World = 'main'; GameVer = $gameVer
                                Gold = $v1; Elixir = $v2; Dark = $v3; Gems = $v4; Extra = $v5
                                Bands = $group.Count; At = $now; Stale = $false
                            }
                        } else {
                            $result = [pscustomobject]@{
                                World = 'bb'; GameVer = $gameVer
                                Gold = $v1; Elixir = $v2; Dark = $null; Gems = $v3; Extra = $v4
                                Bands = $group.Count; At = $now; Stale = $false
                            }
                        }
                        Write-Diag ("资源采样：版本={0} 世界={1} 带数={2} 数字={3} 金={4} 圣={5} 黑={6} 宝={7} 券={8}" -f $gameVer, $res.World, $group.Count, $nums.Count, $result.Gold, $result.Elixir, $result.Dark, $result.Gems, $result.Extra)
                    }
                }
            } finally { try { $bmp.Dispose() } catch { } }
        }
    } catch {
        Write-Diag "资源 OCR 失败: $($_.Exception.Message)"
    } finally {
        try { Remove-Item $png -Force -ErrorAction SilentlyContinue } catch { }
    }

    if ($result) {
        $script:resCache[$Index] = @{ At = $now; Data = $result }
        return $result
    }
    if ($script:resCache.ContainsKey($Index)) {
        $old = $script:resCache[$Index].Data
        try { $old | Add-Member -NotePropertyName Stale -NotePropertyValue $true -Force } catch { }
        return $old
    }
    return $null
}

# ---------------- 连续采样（游戏在前台时每 3 秒一次）----------------
function Update-ResSamples([string]$Index) {
    if (-not (Test-GameForeground $Index)) { return $null }
    $r = Get-GameResources $Index -Force
    if (-not $r) { return $null }
    if (-not $script:resSamples.ContainsKey($Index)) {
        $script:resSamples[$Index] = New-Object System.Collections.ArrayList
    }
    $list = $script:resSamples[$Index]
    [void]$list.Add($r)
    while ($list.Count -gt $script:resSampleMax) { $list.RemoveAt(0) }
    return $r
}

function Get-ResStable([string]$Index) {
    if (-not $script:resSamples.ContainsKey($Index)) { return $null }
    $all = @($script:resSamples[$Index])
    if ($all.Count -eq 0) { return $null }
    $world = "$($all[$all.Count - 1].World)"
    $same = @($all | Where-Object { "$($_.World)" -eq $world })
    if ($same.Count -lt 2) {
        $one = $same[0]
        $one | Add-Member -NotePropertyName Samples -NotePropertyValue 1 -Force
        return $one
    }
    $med = {
        param($arr)
        $v = @($arr | Where-Object { $null -ne $_ } | ForEach-Object { [double]$_ } | Sort-Object)
        if ($v.Count -eq 0) { return $null }
        return $v[[int][math]::Floor($v.Count / 2)]
    }
    $latest = $same[$same.Count - 1]
    return [pscustomobject]@{
        World = $world
        GameVer = $latest.GameVer
        Gold = (& $med ($same | ForEach-Object { $_.Gold }))
        Elixir = (& $med ($same | ForEach-Object { $_.Elixir }))
        Dark = (& $med ($same | ForEach-Object { $_.Dark }))
        Gems = (& $med ($same | ForEach-Object { $_.Gems }))
        Extra = (& $med ($same | ForEach-Object { $_.Extra }))
        Samples = $same.Count
        At = $latest.At
        Stale = $false
    }
}

function Clear-ResSamples([string]$Index) {
    if ($script:resSamples.ContainsKey($Index)) { $script:resSamples.Remove($Index) }
}

function Format-ResAmount($v) {
    if ($null -eq $v) { return '—' }
    $n = [double]$v
    if ($n -ge 100000000) { return ('{0:0.##}亿' -f ($n / 100000000)) }
    if ($n -ge 10000) { return ('{0:0.#}万' -f ($n / 10000)) }
    return ('{0:0}' -f $n)
}
