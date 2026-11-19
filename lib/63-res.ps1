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
    # 只扫数字本身所在的横向区间：左边避开绿色「+」按钮，右边避开图标，
    # 否则「+」按钮的白色十字会多出一条亮带，把真正的资源行挤掉（主世界被误判成夜世界就是这么来的）
    $x0 = [int]($Bmp.Width * 0.885)
    $x1 = [int]($Bmp.Width * 0.955)
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
# 返回每行文本 + 该行在裁剪图里的纵向中心（Y），供上层按「行位置」对齐两种语言的识别结果
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
        foreach ($ln in $res.Lines) {
            $ys = @()
            try { foreach ($wd in $ln.Words) { $r = $wd.BoundingRect; $ys += ($r.Y + $r.Height / 2) } } catch { }
            $cy = $null
            if ($ys.Count -gt 0) { $cy = ($ys | Measure-Object -Average).Average }
            $lines += [pscustomobject]@{ Text = "$($ln.Text)"; Y = $cy }
        }
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
        # 把绿色「+」按钮整块涂黑：它中间的白色十字会被 OCR 认成数字
        # （"6 395" 曾被读成 "46.395"）。按钮是饱和度极高的亮绿，草地达不到这个亮度，
        # 只在左侧按钮区域（<0.90W）抹除，右侧宝石图标不动。
        try {
            $gb = [System.Drawing.Graphics]::FromImage($crop)
            $br = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::Black)
            $xLimit = [int]($Bmp.Width * 0.90)
            for ($y = $y0; $y -le $y1; $y++) {
                $mn = [int]::MaxValue; $mx = -1
                for ($x = $x0; $x -le $xLimit; $x++) {
                    $c = $Bmp.GetPixel($x, $y)
                    if ($c.G -ge 205 -and ($c.G - $c.R) -ge 90 -and ($c.G - $c.B) -ge 120) {
                        if ($x -lt $mn) { $mn = $x }
                        if ($x -gt $mx) { $mx = $x }
                    }
                }
                if ($mx -ge 0 -and ($mx - $mn) -ge 6) {
                    $gb.FillRectangle($br, [int](($mn - $x0 - 1) * $scale), [int](($y - $y0) * $scale),
                                      [int](($mx - $mn + 2) * $scale), ([int]$scale + 1))
                }
            }
            $br.Dispose(); $gb.Dispose()
        } catch { }
        $crop.Save($tmp, [System.Drawing.Imaging.ImageFormat]::Png)
        $crop.Dispose()
        foreach ($lang in @('en-US', 'zh-Hans-CN')) {
            $cands = @()
            $lines = @(Get-OcrLines $tmp $lang)
            foreach ($ln in $lines) {
                if (-not $ln) { continue }
                $raw = "$($ln.Text)"
                if (-not $raw) { continue }
                $clean = [regex]::Replace($raw, '[\u4e00-\u9fa5]', '')
                if (-not $clean) { continue }
                $v = ConvertTo-BestDigits @($clean) 9
                if ($null -eq $v) { continue }
                $cy = -1
                if ($null -ne $ln.Y) { $cy = [double]$ln.Y }
                $cands += [pscustomobject]@{ Y = $cy; Value = $v }
            }
            $byLang[$lang] = $cands
        }
    } catch { } finally {
        try { Remove-Item $tmp -Force -ErrorAction SilentlyContinue } catch { }
    }

    # 关键：两种语言按「行在图片里的纵向位置」对齐，不能按下标。
    # 两个引擎经常会漏行（中文漏第一行、英文漏最后一行），按下标合并会把上一行的数字顶到下一行。
    $rowCenters = @()
    foreach ($b in $arr) { $rowCenters += (((($b.Y0 + $b.Y1) / 2) - $y0) * $scale) }
    $tol = [Math]::Max(8, 0.55 * $avgH * $scale)

    $en = @($byLang['en-US'])
    $zh = @($byLang['zh-Hans-CN'])
    $pick = {
        param($Cands, $Cy)
        $best = $null; $bestD = [double]::MaxValue
        foreach ($c in $Cands) {
            if ($c.Y -lt 0) { continue }
            $d = [Math]::Abs($c.Y - $Cy)
            if ($d -lt $bestD) { $bestD = $d; $best = $c }
        }
        if ($best -and $bestD -le $tol) { return $best }
        return $null
    }
    $lens = { param($x) if ($null -eq $x) { return -1 } else { return ("$([long]$x)").Length } }
    $merged = @()
    for ($i = 0; $i -lt $rowCenters.Count; $i++) {
        $cy = $rowCenters[$i]
        $a = & $pick $en $cy
        $b = & $pick $zh $cy
        $va = $(if ($a) { $a.Value } else { $null })
        $vb = $(if ($b) { $b.Value } else { $null })
        $la = & $lens $va
        $lb = & $lens $vb
        $merged += $(if ($la -ge $lb) { $va } else { $vb })
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

# 看右侧图标列里有没有「黑油」图标：
#   主世界的第三行是黑油，图标接近纯黑、几乎没有色彩；
#   夜世界没有黑油，四个图标（金/圣/宝石/点券）都是鲜艳色。
# 只认「上下都被亮色图标夹住」的近黑块，避免把深色背景、兵营条之类当成图标。
function Get-IconWorld([System.Drawing.Bitmap]$Bmp) {
    try {
        $W = $Bmp.Width; $H = $Bmp.Height
        if ($W -lt 200 -or $H -lt 100) { return $null }
        $x0 = [int]($W * 0.955); $x1 = [int]($W * 0.995)
        $yLimit = [int]($H * 0.40)
        if ($x1 -le $x0 -or $yLimit -lt 40) { return $null }

        # 逐行取图标条的平均色，分成「亮而鲜艳」「近黑而灰」两类
        $kind = New-Object System.Collections.Generic.List[string]
        $ys = New-Object System.Collections.Generic.List[int]
        for ($y = 0; $y -lt $yLimit; $y++) {
            $sR = 0; $sG = 0; $sB = 0; $n = 0
            for ($x = $x0; $x -lt $x1; $x += 2) {
                $c = $Bmp.GetPixel($x, $y)
                $sR += $c.R; $sG += $c.G; $sB += $c.B; $n++
            }
            if ($n -le 0) { continue }
            $r = $sR / $n; $g = $sG / $n; $b = $sB / $n
            $lum = 0.299 * $r + 0.587 * $g + 0.114 * $b
            $mx = [Math]::Max($r, [Math]::Max($g, $b))
            $mn = [Math]::Min($r, [Math]::Min($g, $b))
            $k = ''
            if ($lum -gt 90 -and ($mx - $mn) -gt 70) { $k = 'bright' }
            elseif ($lum -lt 70 -and ($mx - $mn) -lt 25) { $k = 'dark' }
            $kind.Add($k); $ys.Add($y)
        }
        if ($kind.Count -lt 30) { return $null }

        # 合并成连续区段
        $runs = @()
        $cur = $kind[0]; $start = $ys[0]
        for ($i = 1; $i -lt $kind.Count; $i++) {
            if ($kind[$i] -ne $cur) {
                if ($cur -and ($ys[$i] - $start) -ge 6) { $runs += @{ Kind = $cur; Y0 = $start; Y1 = $ys[$i] } }
                $cur = $kind[$i]; $start = $ys[$i]
            }
        }
        if ($cur -and ($ys[$ys.Count - 1] - $start) -ge 6) { $runs += @{ Kind = $cur; Y0 = $start; Y1 = $ys[$ys.Count - 1] } }

        $brightCount = @($runs | Where-Object { $_.Kind -eq 'bright' }).Count
        if ($brightCount -lt 2) { return $null }   # 图标列看不清，判不了

        for ($i = 0; $i -lt $runs.Count; $i++) {
            $r = $runs[$i]
            if ($r.Kind -ne 'dark') { continue }
            $h = $r.Y1 - $r.Y0
            if ($h -lt 12 -or $h -gt 40) { continue }
            $above = $false; $below = $false
            for ($j = $i - 1; $j -ge 0; $j--) {
                if ($runs[$j].Kind -eq 'bright') { if (($r.Y0 - $runs[$j].Y1) -lt 60) { $above = $true }; break }
            }
            for ($j = $i + 1; $j -lt $runs.Count; $j++) {
                if ($runs[$j].Kind -eq 'bright') { if (($runs[$j].Y0 - $r.Y1) -lt 60) { $below = $true }; break }
            }
            if ($above -and $below) { return 'main' }
        }
        return 'bb'
    } catch { return $null }
}

function Get-ExpectedBarCount([string]$GameVer, [string]$World) {
    if ($GameVer -eq 'cn') { if ($World -eq 'main') { return 5 } else { return 4 } }
    if ($GameVer -eq 'global') { if ($World -eq 'main') { return 4 } else { return 3 } }
    return 0
}

# 世界以「图标列有没有黑油」为准；条数只做交叉校验，
# 对不上就不记录（宁可显示尚未采集，也不把主世界的数值记到夜世界名下）。
function Resolve-World([string]$GameVer, [int]$TotalBands, [string]$IconWorld) {
    if (-not $GameVer -or $TotalBands -le 0) { return $null }
    $nMain = Get-ExpectedBarCount $GameVer 'main'
    $nBb = Get-ExpectedBarCount $GameVer 'bb'
    if ($IconWorld -eq 'main') {
        if ($nMain -gt 0 -and $TotalBands -ge $nMain) { return [pscustomobject]@{ World = 'main'; Bars = $nMain } }
        return $null
    }
    if ($IconWorld -eq 'bb') {
        if ($nBb -gt 0 -and $TotalBands -ge $nBb) { return [pscustomobject]@{ World = 'bb'; Bars = $nBb } }
        return $null
    }
    # 图标列看不清时的兜底：条数必须正好等于某个世界的应有条数
    if ($nMain -gt 0 -and $TotalBands -eq $nMain) { return [pscustomobject]@{ World = 'main'; Bars = $nMain } }
    if ($nBb -gt 0 -and $TotalBands -eq $nBb) { return [pscustomobject]@{ World = 'bb'; Bars = $nBb } }
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
                $iconWorld = Get-IconWorld $bmp
                $res = Resolve-World $gameVer $group.Count $iconWorld
                if (-not $res) {
                    Write-Diag ("资源采样：认不出世界（版本={0} 图标={1} 带数={2} 数字={3}）" -f $gameVer, $iconWorld, $group.Count, $nums.Count)
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
                        Write-Diag ("资源采样：版本={0} 世界={1} 图标={2} 带数={3} 数字={4} 金={5} 圣={6} 黑={7} 宝={8} 券={9}" -f $gameVer, $res.World, $iconWorld, $group.Count, $nums.Count, $result.Gold, $result.Elixir, $result.Dark, $result.Gems, $result.Extra)
                        [void](Save-ResShot $Index $result $png)
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
# ---------------- 成功采集时把截图留下来（卡片里做可视化）----------------
$script:resShotInfo = @{}

function Get-ResShotDir {
    $dir = $null
    try { if ($DataDir) { $dir = Join-Path $DataDir 'shots' } } catch { }
    if (-not $dir) { $dir = Join-Path $env:LOCALAPPDATA 'MuMuGuard\shots' }
    try { if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null } } catch { }
    return $dir
}

# 只裁右上角那摞资源条，存成图；同一实例同一世界只保留最新一张
function Save-ResShot([string]$Index, $Sample, [string]$Png) {
    try {
        if (-not $Png -or -not (Test-Path $Png)) { return $null }
        $dir = Get-ResShotDir
        if (-not $dir) { return $null }
        Add-Type -AssemblyName System.Drawing -ErrorAction SilentlyContinue
        $src = [System.Drawing.Bitmap]::FromFile($Png)
        try {
            # 存整张画面（缩到 960 宽，保留全部布局信息），卡片里显示缩略图，点开能看细节
            $maxW = 960
            $outW = $src.Width
            $outH = $src.Height
            if ($outW -gt $maxW) {
                $outH = [int]($src.Height * ($maxW / $src.Width))
                $outW = $maxW
            }
            if ($outW -lt 40 -or $outH -lt 40) { return $null }
            $out = Join-Path $dir ("{0}_{1}.png" -f $Index, $Sample.World)
            $img = New-Object System.Drawing.Bitmap $outW, $outH
            $g = [System.Drawing.Graphics]::FromImage($img)
            $g.InterpolationMode = 'HighQualityBicubic'
            $g.DrawImage($src, (New-Object System.Drawing.Rectangle 0, 0, $outW, $outH),
                         (New-Object System.Drawing.Rectangle 0, 0, $src.Width, $src.Height), [System.Drawing.GraphicsUnit]::Pixel)
            $g.Dispose()
            $img.Save($out, [System.Drawing.Imaging.ImageFormat]::Png)
            $img.Dispose()
            if (-not $script:resShotInfo.ContainsKey($Index)) { $script:resShotInfo[$Index] = @{} }
            $script:resShotInfo[$Index]["$($Sample.World)"] = @{ Path = $out; At = (Get-Date) }
            # 顺手把这次读到的数值也存下来，进程重启后卡片还能显示（标注「上次」）
            try {
                $metaPath = [System.IO.Path]::ChangeExtension($out, '.json')
                $meta = [pscustomobject]@{ Gold = $Sample.Gold; Elixir = $Sample.Elixir; Dark = $Sample.Dark; Gems = $Sample.Gems; Extra = $Sample.Extra; GameVer = $Sample.GameVer; World = $Sample.World; At = (Get-Date).ToString('o') }
                [System.IO.File]::WriteAllText($metaPath, ($meta | ConvertTo-Json -Compress), (New-Object System.Text.UTF8Encoding $false))
            } catch { }
            return $out
        } finally { try { $src.Dispose() } catch { } }
    } catch { return $null }
}

# 取某个实例某个世界最近一次的截图信息
function Get-ResShot([string]$Index, [string]$World) {
    try {
        if ($script:resShotInfo.ContainsKey($Index) -and $script:resShotInfo[$Index].ContainsKey($World)) {
            $info = $script:resShotInfo[$Index][$World]
            if ($info -and (Test-Path $info.Path)) { return $info }
        }
        $dir = Get-ResShotDir
        if (-not $dir) { return $null }
        $p = Join-Path $dir ("{0}_{1}.png" -f $Index, $World)
        if (Test-Path $p) { return @{ Path = $p; At = (Get-Item $p).LastWriteTime } }
    } catch { }
    return $null
}

# 清理异常退出留下的 OCR 临时图（正常情况用完就删了）
function Clear-OrphanTempShots {
    try {
        $cut = (Get-Date).AddHours(-1)
        Get-ChildItem $env:TEMP -Filter 'mmg-*.png' -ErrorAction SilentlyContinue |
            Where-Object { $_.LastWriteTime -lt $cut } |
            ForEach-Object { try { Remove-Item $_.FullName -Force -ErrorAction SilentlyContinue } catch { } }
    } catch { }
}
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

# 进程重启后从磁盘恢复上一次的数值（标记为「上次」）
function Get-ResMeta([string]$Index, [string]$World) {
    try {
        $dir = Get-ResShotDir
        if (-not $dir) { return $null }
        $p = Join-Path $dir ("{0}_{1}.json" -f $Index, $World)
        if (-not (Test-Path $p)) { return $null }
        $j = Get-Content $p -Raw -Encoding UTF8 | ConvertFrom-Json
        return [pscustomobject]@{
            World = "$($j.World)"; GameVer = "$($j.GameVer)"
            Gold = $j.Gold; Elixir = $j.Elixir; Dark = $j.Dark; Gems = $j.Gems; Extra = $j.Extra
            Samples = 1; At = [datetime]::Parse($j.At); Stale = $true
        }
    } catch { return $null }
}

function Get-ResStable([string]$Index, [string]$World) {
    # 后台采样线程算好的结果优先（UI 线程只读，不再自己跑 OCR）
    try {
        if ($script:resLive) {
            $lk = "$Index|$World"
            if ($script:resLive.ContainsKey($lk)) {
                $lv = $script:resLive[$lk]
                if ($lv) {
                    # 超过 60 秒没刷新就标成「上次」，不把旧读数当实时值
                    try {
                        if ($lv.At -and ((Get-Date) - [datetime]$lv.At).TotalSeconds -gt 60) {
                            $lv | Add-Member -NotePropertyName Stale -NotePropertyValue $true -Force
                        }
                    } catch { }
                    return $lv
                }
            }
        }
    } catch { }
    if (-not $script:resSamples.ContainsKey($Index)) { return (Get-ResMeta $Index $World) }
    $all = @($script:resSamples[$Index])
    $world = $(if ($World) { $World } else { "$($all[$all.Count - 1].World)" })
    $same = @($all | Where-Object { "$($_.World)" -eq $world })
    if ($same.Count -eq 0) { return (Get-ResMeta $Index $World) }
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

# ---------------- 后台采样线程 ----------------
# 一次 OCR 要 1~2 秒，如果跑在 UI 线程上，界面每隔几秒就会卡住一下。
# 这里把整轮采样放到独立 runspace 里，UI 线程只用 Get-ResStable 读结果（纯内存，微秒级）。
$script:resLive = $null
$script:resBg = $null

$script:resBgScript = {
    param($Sync)
    $ErrorActionPreference = 'SilentlyContinue'

    function Write-Diag([string]$msg) {
        try {
            $p = Join-Path $Sync.DataDir 'logs\diag.log'
            $line = "[{0}] {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $msg
            [System.IO.File]::AppendAllText($p, $line + "`r`n", (New-Object System.Text.UTF8Encoding $false))
        } catch { }
    }

    # 后台线程自己的模块上下文
    $script:cfg = [pscustomobject]@{ MuMuRoot = "$($Sync.MuMuRoot)" }
    $script:adbSync = [pscustomobject]@{ Data = @{} }
    $script:AdbExe = "$($Sync.AdbExe)"
    $script:resSamples = @{}
    $script:resShotInfo = @{}
    $script:resCache = @{}
    if ($Sync.ZkqModule -and (Test-Path "$($Sync.ZkqModule)")) { . "$($Sync.ZkqModule)" }
    . "$($Sync.ResModule)"

    while (-not $Sync.Stop) {
        $keys = @($Sync.Serials.Keys)
        foreach ($k in $keys) {
            if ($Sync.Stop) { break }
            try {
                $idx = "$k"
                $ser = "$($Sync.Serials[$k])"
                if (-not $ser) { continue }
                $script:adbSync = [pscustomobject]@{ Data = @{ $idx = [pscustomobject]@{ Serial = $ser } } }
                try {
                    $sv = Get-ZkqUpgradeSchedule $idx
                    $Sync.Sched[$idx] = $sv
                } catch { if (-not $Sync.Dbg) { $Sync.Dbg = 1; Write-Diag "后台读升级上号异常: $($_.Exception.Message)" } }
                $r = Update-ResSamples $idx
                $Sync.Busy = $false
                if (-not $r) { continue }
                $Sync.Last[$idx] = $r
                foreach ($w in @('main', 'bb')) {
                    $st = Get-ResStable $idx $w
                    if ($st) { $Sync.Snap["$idx|$w"] = $st }
                }
            } catch {
                try { Write-Diag "后台采样异常（$k）: $($_.Exception.Message)" } catch { }
            }
        }
        # 分片睡眠，停止命令能及时生效
        for ($i = 0; $i -lt 25; $i++) {
            if ($Sync.Stop) { break }
            Start-Sleep -Milliseconds 100
        }
    }
}

function Start-ResBackground {
    param(
        [string]$Root,
        [string]$DataDir,
        [string]$MuMuRoot,
        [string]$AdbExe,
        $Serials           # 形如 @{ '3' = '127.0.0.1:16480' }
    )
    try {
        if ($script:resBg -and $script:resBg.PS -and -not $script:resBg.PS.IsCompleted) { return $true }
        $resModPath = Join-Path $Root 'lib\63-res.ps1'
        $zkqModPath = Join-Path $Root 'lib\62-zkq.ps1'
        if (-not (Test-Path $resModPath)) {
            # 单文件 exe：没有 lib 目录，后台 runspace 没法 dot-source 文件。
            # 构建时把这两个模块以 base64 内嵌进来了，这里释放到本地缓存再用。
            try {
                $cacheDir = Join-Path $env:LOCALAPPDATA 'MuMuGuard\libcache'
                if (-not (Test-Path $cacheDir)) { New-Item -ItemType Directory -Path $cacheDir -Force | Out-Null }
                foreach ($nm in @('62-zkq', '63-res')) {
                    $b64 = $null
                    try { if ($script:EmbeddedLib) { $b64 = "$($script:EmbeddedLib[$nm])" } } catch { }
                    if ($b64) {
                        $txt = [System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($b64))
                        [System.IO.File]::WriteAllText((Join-Path $cacheDir ($nm + '.ps1')), $txt, (New-Object System.Text.UTF8Encoding $true))
                    }
                }
                if (Test-Path (Join-Path $cacheDir '63-res.ps1')) {
                    $resModPath = Join-Path $cacheDir '63-res.ps1'
                    $zkqModPath = Join-Path $cacheDir '62-zkq.ps1'
                }
            } catch { }
        }
        $sync = [hashtable]::Synchronized(@{
            Stop      = $false
            Busy      = $false
            Dbg       = 0
            Snap      = [hashtable]::Synchronized(@{})
            Last      = [hashtable]::Synchronized(@{})
            Serials   = [hashtable]::Synchronized(@{})
            Sched     = [hashtable]::Synchronized(@{})
            MuMuRoot  = "$MuMuRoot"
            AdbExe    = "$AdbExe"
            DataDir   = "$DataDir"
            ResModule = $resModPath
            ZkqModule = $zkqModPath
        })
        if ($Serials) {
            foreach ($k in $Serials.Keys) { $sync.Serials["$k"] = "$($Serials[$k])" }
        }
        $rs = [runspacefactory]::CreateRunspace()
        $rs.ApartmentState = 'MTA'
        $rs.ThreadOptions = 'ReuseThread'
        $rs.Open()
        $ps = [powershell]::Create()
        $ps.Runspace = $rs
        [void]$ps.AddScript($script:resBgScript).AddArgument($sync)
        $h = $ps.BeginInvoke()
        $script:resBg = @{ PS = $ps; Handle = $h; Runspace = $rs; Sync = $sync }
        $script:resLive = $sync.Snap
        return $true
    } catch {
        Write-Diag "后台采样启动失败: $($_.Exception.Message)"
        return $false
    }
}

function Update-ResSerials($Map) {
    try {
        if (-not $script:resBg) { return }
        $q = $script:resBg.Sync.Serials
        if (-not $Map) { return }
        foreach ($k in @($Map.Keys)) { $q["$k"] = "$($Map[$k])" }
    } catch { }
}

function Stop-ResBackground {
    try {
        if (-not $script:resBg) { return }
        $script:resBg.Sync.Stop = $true
        try { [void]$script:resBg.PS.EndInvoke($script:resBg.Handle) } catch { }
        try { $script:resBg.PS.Dispose() } catch { }
        try { $script:resBg.Runspace.Dispose() } catch { }
    } catch { }
    $script:resBg = $null
    $script:resLive = $null
}

# 后台最新一次原始读数（不含中位数处理），给手机端和调试用
function Get-ResLatest([string]$Index) {
    try {
        if ($script:resBg -and $script:resBg.Sync.Last.ContainsKey("$Index")) { return $script:resBg.Sync.Last["$Index"] }
    } catch { }
    return $null
}

# 后台线程读到的「升级上号」开关状态（避免 UI 线程为了读它去调 adb）
function Get-ZkqSchedCached([string]$Index) {
    try {
        if ($script:resBg -and $script:resBg.Sync.Sched.ContainsKey("$Index")) { return $script:resBg.Sync.Sched["$Index"] }
    } catch { }
    return $null
}

function Set-ZkqSchedCached([string]$Index, $Value) {
    try {
        if ($script:resBg) { $script:resBg.Sync.Sched["$Index"] = $Value }
    } catch { }
}
