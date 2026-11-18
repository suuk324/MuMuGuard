# 游戏界面资源读取（OCR，只读）
# 只在游戏在前台时才有意义；读不到就返回 $null，绝不编造数字。
# 判据：主世界 = 4 条数值带（金币/圣水/黑油/宝石）；夜世界 = 3 条（兵金/兵圣/宝石）
# 做法：adb 截屏 -> 右上角找白色数字行 -> 裁切放大 -> Windows OCR（中英文双引擎）-> 取最长合理数字

$script:resCache = @{}       # index -> @{ At; Data }
$script:resMinGapSec = 60    # 同一实例最短采集间隔

# ---- Windows 自带 OCR（WinRT）初始化 ----
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

# ---- adb 截图 ----
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

# 解析实例对应的 adb 序列号（127.0.0.1:端口），与程序其它地方保持一致
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
    # 从 MuMu 的 vm_config.json 里取 adb 端口（目录名形如 MuMuPlayer-15.0-2）
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

# ---- 找数值带 ----
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
        if ($cnt -ge 6 -and -not $inBand) { $inBand = $true; $startY = $y }
        elseif ($cnt -lt 6 -and $inBand) {
            $inBand = $false
            if (($y - $startY) -ge 8 -and ($y - $startY) -le 40) { $bands += @{ Y0 = $startY; Y1 = $y } }
        }
    }
    return $bands
}

# COC 的数字字体常被 OCR 认成字母（0->O、5->S、8->B…），先做一次字符纠正
function Repair-OcrDigits([string]$Text) {
    if (-not $Text) { return '' }
    $t = $Text
    # 大小写敏感地逐个替换（哈希表不区分大小写，会撞键）
    $t = $t -creplace 'O', '0'
    $t = $t -creplace 'o', '0'
    $t = $t -creplace 'Q', '0'
    $t = $t -creplace 'D', '0'
    $t = $t -creplace 'I', '1'
    $t = $t -creplace 'l', '1'
    $t = $t -creplace 'i', '1'
    $t = $t -creplace '\|', '1'
    $t = $t -creplace '!', '1'
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
        $fixed = Repair-OcrDigits $c
        $d = ($fixed -replace '[^0-9]', '')
        if ($d.Length -lt 2 -or $d.Length -gt $MaxDigits) { continue }
        # 资源值不该以 0 开头（除非就是个位数）
        if ($d.Length -gt 1 -and $d.StartsWith('0')) { continue }
        if ($d.Length -gt $best.Length) { $best = $d }
    }
    if (-not $best) { return $null }
    return [double]$best
}

function Read-BandNumber([System.Drawing.Bitmap]$Bmp, $Band) {
    $y0 = [Math]::Max(0, $Band.Y0 - 2)
    $y1 = [Math]::Min($Bmp.Height - 1, $Band.Y1 + 2)
    if (($y1 - $y0) -lt 6) { return $null }

    # 先按亮像素找数字的水平范围，紧贴数字裁切（右对齐的短数字也能框准）
    $xMin = -1; $xMax = -1
    for ($x = [int]($Bmp.Width * 0.80); $x -lt [int]($Bmp.Width * 0.98); $x++) {
        $hit = $false
        for ($y = $y0; $y -le $y1; $y++) {
            $c = $Bmp.GetPixel($x, $y)
            $lum = 0.299 * $c.R + 0.587 * $c.G + 0.114 * $c.B
            if ($lum -gt 195) { $hit = $true; break }
        }
        if ($hit) { if ($xMin -lt 0) { $xMin = $x }; $xMax = $x }
    }
    if ($xMin -lt 0 -or ($xMax - $xMin) -lt 10) { return $null }
    $x0 = [Math]::Max(0, $xMin - 3)
    $x1 = [Math]::Min($Bmp.Width - 1, $xMax + 3)
    $w = $x1 - $x0; $bh = $y1 - $y0
    if ($w -lt 12) { return $null }

    $all = @()
    $targetH = 64
    $scale = [Math]::Max(2, [int]($targetH / [Math]::Max(1, $bh)))
    foreach ($mode in @('raw', 'bw')) {
        $tmp = Join-Path $env:TEMP ('mmg-band-' + [guid]::NewGuid().ToString('N').Substring(0, 8) + '.png')
        try {
            $crop = New-Object System.Drawing.Bitmap ($w * $scale), ($bh * $scale)
            $g = [System.Drawing.Graphics]::FromImage($crop)
            $g.InterpolationMode = 'HighQualityBicubic'
            $g.DrawImage($Bmp, (New-Object System.Drawing.Rectangle 0, 0, ($w * $scale), ($bh * $scale)),
                         (New-Object System.Drawing.Rectangle $x0, $y0, $w, $bh), [System.Drawing.GraphicsUnit]::Pixel)
            $g.Dispose()
            if ($mode -eq 'bw') {
                $bw = New-Object System.Drawing.Bitmap $crop.Width, $crop.Height
                for ($yy = 0; $yy -lt $crop.Height; $yy++) {
                    for ($xx = 0; $xx -lt $crop.Width; $xx++) {
                        $c = $crop.GetPixel($xx, $yy)
                        $lum = 0.299 * $c.R + 0.587 * $c.G + 0.114 * $c.B
                        if ($lum -ge 170) { $bw.SetPixel($xx, $yy, [System.Drawing.Color]::Black) }
                        else { $bw.SetPixel($xx, $yy, [System.Drawing.Color]::White) }
                    }
                }
                $crop.Dispose()
                $bw.Save($tmp, [System.Drawing.Imaging.ImageFormat]::Png)
                $bw.Dispose()
            } else {
                $crop.Save($tmp, [System.Drawing.Imaging.ImageFormat]::Png)
                $crop.Dispose()
            }
            $all += (Invoke-WinOcr $tmp 'en-US')
            $all += (Invoke-WinOcr $tmp 'zh-Hans-CN')
        } catch { } finally {
            try { Remove-Item $tmp -Force -ErrorAction SilentlyContinue } catch { }
        }
    }
    return ConvertTo-BestDigits $all 9
}

# ---- 主入口 ----
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
        try {
            $bands = @(Find-NumberBands $bmp)
            $bands = @($bands | Select-Object -First 4)
            if ($bands.Count -ge 2) {
                $vals = @()
                foreach ($b in $bands) { $vals += , (Read-BandNumber $bmp $b) }
                $world = $(if ($bands.Count -ge 4) { 'main' } elseif ($bands.Count -eq 3) { 'bb' } else { 'unknown' })
                $result = [pscustomobject]@{
                    World  = $world
                    Gold   = $(if ($vals.Count -ge 1) { $vals[0] } else { $null })
                    Elixir = $(if ($vals.Count -ge 2) { $vals[1] } else { $null })
                    Dark   = $(if ($world -eq 'main' -and $vals.Count -ge 3) { $vals[2] } else { $null })
                    Gems   = $(if ($world -eq 'main' -and $vals.Count -ge 4) { $vals[3] }
                               elseif ($world -eq 'bb' -and $vals.Count -ge 3) { $vals[2] } else { $null })
                    Bands  = $bands.Count
                    At     = $now
                    Stale  = $false
                }
            }
        } finally { $bmp.Dispose() }
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

function Format-ResAmount($v) {
    if ($null -eq $v) { return '—' }
    $n = [double]$v
    if ($n -ge 100000000) { return ('{0:0.##}亿' -f ($n / 100000000)) }
    if ($n -ge 10000) { return ('{0:0.#}万' -f ($n / 10000)) }
    return ('{0:0}' -f $n)
}
