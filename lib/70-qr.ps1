#Requires -Version 5.1
#
# 二维码生成（本地实现，不联网）
# 只支持 Byte 模式、纠错等级 M、版本 1~6（足够放下局域网地址 + 令牌）
#
# 供 MuMuGuardApp.ps1 dot-source

# GF(256) 乘法
$script:QrExp = New-Object int[] 512
$script:QrLog = New-Object int[] 256
$script:QrInit = $false

function Initialize-QrTables {
    if ($script:QrInit) { return }
    $x = 1
    for ($i = 0; $i -lt 255; $i++) {
        $script:QrExp[$i] = $x
        $script:QrLog[$x] = $i
        $x = $x -shl 1
        if ($x -band 0x100) { $x = $x -bxor 0x11D }
    }
    for ($i = 255; $i -lt 512; $i++) { $script:QrExp[$i] = $script:QrExp[$i - 255] }
    $script:QrInit = $true
}

function Qr-Multiply([int]$a, [int]$b) {
    if ($a -eq 0 -or $b -eq 0) { return 0 }
    return $script:QrExp[$script:QrLog[$a] + $script:QrLog[$b]]
}

# 生成多项式
function Get-QrGenerator([int]$degree) {
    $poly = New-Object int[] ($degree)
    $poly[$degree - 1] = 1
    $root = 1
    for ($i = 0; $i -lt $degree; $i++) {
        for ($j = 0; $j -lt $degree; $j++) {
            $poly[$j] = Qr-Multiply $poly[$j] $root
            if ($j + 1 -lt $degree) { $poly[$j] = $poly[$j] -bxor $poly[$j + 1] }
        }
        $root = Qr-Multiply $root 2
    }
    return $poly
}

# RS 纠错码
function Get-QrEcc([int[]]$data, [int]$ecLen) {
    $gen = Get-QrGenerator $ecLen
    $res = New-Object int[] $ecLen
    foreach ($d in $data) {
        $factor = $d -bxor $res[0]
        for ($i = 0; $i -lt $ecLen - 1; $i++) { $res[$i] = $res[$i + 1] -bxor (Qr-Multiply $gen[$i] $factor) }
        $res[$ecLen - 1] = Qr-Multiply $gen[$ecLen - 1] $factor
    }
    return $res
}

# 版本参数（EC 等级 M）
$script:QrVersions = @{
    1  = @{ Total = 26;  Data = 16;  Ec = 10; Blocks = 1; Align = @() }
    2  = @{ Total = 44;  Data = 28;  Ec = 16; Blocks = 1; Align = @(6) }
    3  = @{ Total = 70;  Data = 44;  Ec = 26; Blocks = 1; Align = @(6, 22) }
    4  = @{ Total = 100; Data = 64;  Ec = 18; Blocks = 2; Align = @(6, 26) }
    5  = @{ Total = 134; Data = 86;  Ec = 24; Blocks = 2; Align = @(6, 30) }
    6  = @{ Total = 172; Data = 108; Ec = 16; Blocks = 4; Align = @(6, 34) }
}

function Get-QrVersionFor([int]$byteLen) {
    for ($v = 1; $v -le 6; $v++) {
        $info = $script:QrVersions[$v]
        # 模式(4) + 长度(8) + 数据 + 终止符，向上取整到字节
        $needBits = 4 + 8 + ($byteLen * 8)
        $capBits = $info.Data * 8
        if ($needBits -le $capBits) { return $v }
    }
    return 0
}

function New-QrMatrix([string]$text) {
    Initialize-QrTables
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($text)
    $ver = Get-QrVersionFor $bytes.Length
    if ($ver -eq 0) { throw "内容太长，超出二维码容量（$($text.Length) 字符）" }

    $info = $script:QrVersions[$ver]
    $size = 17 + ($ver * 4)

    # ---- 数据位流 ----
    $bits = New-Object System.Collections.Generic.List[int]
    function AddBits([int]$val, [int]$count) {
        for ($i = $count - 1; $i -ge 0; $i--) { $bits.Add((($val -shr $i) -band 1)) }
    }
    AddBits 4 4                       # 模式：Byte
    AddBits $bytes.Length 8           # 长度（v1~6 固定 8 位）
    foreach ($b in $bytes) { AddBits $b 8 }

    $capBits = $info.Data * 8
    if ($bits.Count -gt $capBits) { throw "内容超出容量" }
    # 终止符
    $term = [Math]::Min(4, $capBits - $bits.Count)
    for ($i = 0; $i -lt $term; $i++) { $bits.Add(0) }
    # 补齐到字节
    while ($bits.Count % 8 -ne 0) { $bits.Add(0) }
    # 填充字节
    $pad = @(0xEC, 0x11)
    $pi = 0
    while ($bits.Count -lt $capBits) {
        AddBits $pad[$pi % 2] 8
        $pi++
    }

    # 转成数据码字
    $dataWords = New-Object System.Collections.Generic.List[int]
    for ($i = 0; $i -lt $bits.Count; $i += 8) {
        $v = 0
        for ($j = 0; $j -lt 8; $j++) { $v = ($v -shl 1) -bor $bits[$i + $j] }
        $dataWords.Add($v)
    }

    # ---- 分块 + 纠错 + 交织 ----
    $blocks = $info.Blocks
    $ecLen = $info.Ec
    $totalData = $info.Data
    $short = [Math]::Floor($totalData / $blocks)
    $numLong = $totalData % $blocks
    $dataBlocks = @()
    $ecBlocks = @()
    $offset = 0
    for ($b = 0; $b -lt $blocks; $b++) {
        $len = $short + $(if ($b -ge ($blocks - $numLong)) { 1 } else { 0 })
        $blockData = New-Object int[] $len
        for ($i = 0; $i -lt $len; $i++) { $blockData[$i] = $dataWords[$offset + $i] }
        $offset += $len
        $dataBlocks += , $blockData
        $ecBlocks += , (Get-QrEcc $blockData $ecLen)
    }

    $final = New-Object System.Collections.Generic.List[int]
    $maxLen = ($dataBlocks | ForEach-Object { $_.Length } | Measure-Object -Maximum).Maximum
    for ($i = 0; $i -lt $maxLen; $i++) {
        foreach ($blk in $dataBlocks) { if ($i -lt $blk.Length) { $final.Add($blk[$i]) } }
    }
    for ($i = 0; $i -lt $ecLen; $i++) {
        foreach ($blk in $ecBlocks) { $final.Add($blk[$i]) }
    }

    # ---- 画矩阵 ----
    $m = New-Object 'object[,]' $size, $size
    for ($y = 0; $y -lt $size; $y++) { for ($x = 0; $x -lt $size; $x++) { $m[$x, $y] = $null } }

    function Set-Finder([int]$cx, [int]$cy) {
        for ($dy = -1; $dy -le 7; $dy++) {
            for ($dx = -1; $dx -le 7; $dx++) {
                $x = $cx + $dx; $y = $cy + $dy
                if ($x -lt 0 -or $y -lt 0 -or $x -ge $size -or $y -ge $size) { continue }
                $on = ($dx -ge 0 -and $dx -le 6 -and $dy -ge 0 -and $dy -le 6) -and
                      (($dx -eq 0 -or $dx -eq 6 -or $dy -eq 0 -or $dy -eq 6) -or ($dx -ge 2 -and $dx -le 4 -and $dy -ge 2 -and $dy -le 4))
                $m[$x, $y] = [bool]$on
            }
        }
    }
    Set-Finder 0 0
    Set-Finder ($size - 7) 0
    Set-Finder 0 ($size - 7)

    # 定位图形
    for ($i = 8; $i -lt $size - 8; $i++) {
        $m[$i, 6] = ($i % 2 -eq 0)
        $m[6, $i] = ($i % 2 -eq 0)
    }
    # 校正图形
    foreach ($ay in $info.Align) {
        foreach ($ax in $info.Align) {
            # 跳过与定位图形重叠的
            if (($ax -le 8 -and $ay -le 8) -or ($ax -le 8 -and $ay -ge ($size - 9)) -or ($ax -ge ($size - 9) -and $ay -le 8)) { continue }
            for ($dy = -2; $dy -le 2; $dy++) {
                for ($dx = -2; $dx -le 2; $dx++) {
                    $on = ([Math]::Max([Math]::Abs($dx), [Math]::Abs($dy)) -ne 1)
                    $m[($ax + $dx), ($ay + $dy)] = [bool]$on
                }
            }
        }
    }
    # 固定暗模块
    $m[8, ($size - 8)] = $true

    # 格式信息（EC=M, mask=0 → 0x5412）
    $fmt = 0x5412
    for ($i = 0; $i -le 5; $i++) { $m[8, $i] = [bool](($fmt -shr $i) -band 1) }
    $m[8, 7] = [bool](($fmt -shr 6) -band 1)
    $m[8, 8] = [bool](($fmt -shr 7) -band 1)
    $m[7, 8] = [bool](($fmt -shr 8) -band 1)
    for ($i = 9; $i -le 14; $i++) { $m[(14 - $i), 8] = [bool](($fmt -shr $i) -band 1) }
    for ($i = 0; $i -le 7; $i++) { $m[($size - 1 - $i), 8] = [bool](($fmt -shr $i) -band 1) }
    for ($i = 8; $i -le 14; $i++) { $m[8, ($size - 15 + $i)] = [bool](($fmt -shr $i) -band 1) }
    $m[8, ($size - 8)] = $true

    # 记录功能区（不可放数据）
    $reserved = New-Object 'bool[,]' $size, $size
    for ($y = 0; $y -lt $size; $y++) {
        for ($x = 0; $x -lt $size; $x++) {
            if ($null -ne $m[$x, $y]) { $reserved[$x, $y] = $true }
        }
    }
    # 格式信息占用区
    for ($i = 0; $i -lt 9; $i++) { $reserved[8, $i] = $true; $reserved[$i, 8] = $true }
    for ($i = 0; $i -lt 8; $i++) { $reserved[($size - 1 - $i), 8] = $true; $reserved[8, ($size - 1 - $i)] = $true }
    $reserved[8, ($size - 8)] = $true

    # ---- 放置数据（之字形，mask 0: (x+y)%2==0 取反）----
    $bitIdx = 0
    $totalBits = $final.Count * 8
    $up = $true
    for ($col = $size - 1; $col -gt 0; $col -= 2) {
        if ($col -eq 6) { $col = 5 }
        for ($n = 0; $n -lt $size; $n++) {
            $y = if ($up) { $size - 1 - $n } else { $n }
            for ($k = 0; $k -lt 2; $k++) {
                $x = $col - $k
                if ($reserved[$x, $y]) { continue }
                $bit = 0
                if ($bitIdx -lt $totalBits) {
                    $byte = $final[[Math]::Floor($bitIdx / 8)]
                    $bit = ($byte -shr (7 - ($bitIdx % 8))) -band 1
                }
                if ((($x + $y) % 2) -eq 0) { $bit = $bit -bxor 1 }
                $m[$x, $y] = [bool]($bit -eq 1)
                $bitIdx++
            }
        }
        $up = -not $up
    }

    return @{ Matrix = $m; Size = $size; Version = $ver }
}

# 生成可直接给 WPF Image 用的位图
function New-QrBitmap([string]$text, [int]$scale = 6, [int]$quiet = 3) {
    $qr = New-QrMatrix $text
    $m = $qr.Matrix
    $size = $qr.Size
    $dim = ($size + $quiet * 2) * $scale

    $bmp = New-Object System.Windows.Media.Imaging.WriteableBitmap($dim, $dim, 96, 96, [System.Windows.Media.PixelFormats]::Bgra32, $null)
    $stride = $dim * 4
    $pixels = New-Object byte[] ($stride * $dim)
    # 白色背景
    for ($i = 0; $i -lt $pixels.Length; $i += 4) { $pixels[$i] = 255; $pixels[$i + 1] = 255; $pixels[$i + 2] = 255; $pixels[$i + 3] = 255 }

    for ($y = 0; $y -lt $size; $y++) {
        for ($x = 0; $x -lt $size; $x++) {
            if (-not $m[$x, $y]) { continue }
            $px0 = ($x + $quiet) * $scale
            $py0 = ($y + $quiet) * $scale
            for ($dy = 0; $dy -lt $scale; $dy++) {
                $row = ($py0 + $dy) * $stride
                for ($dx = 0; $dx -lt $scale; $dx++) {
                    $idx = $row + (($px0 + $dx) * 4)
                    $pixels[$idx] = 0; $pixels[$idx + 1] = 0; $pixels[$idx + 2] = 0; $pixels[$idx + 3] = 255
                }
            }
        }
    }
    $bmp.WritePixels((New-Object System.Windows.Int32Rect 0, 0, $dim, $dim), $pixels, $stride, 0)
    $bmp.Freeze()
    return $bmp
}
