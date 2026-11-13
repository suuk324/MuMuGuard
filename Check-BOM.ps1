#Requires -Version 5.1
<#
  Check-BOM.ps1
  检查（并可选修复）本项目所有 .ps1 / .vbs 的编码问题。

  背景：
    PowerShell 5.1 会把没有 UTF-8 BOM 的 .ps1 按系统 ANSI（简体中文下为 GBK）解析，
    文件里的中文会变成乱码，导致脚本语法错误、程序直接启动失败。
    .vbs 同理，Windows Script Host 也按 ANSI 读取。

  用法：
    .\Check-BOM.ps1              只检查，报告问题（默认）
    .\Check-BOM.ps1 -Fix         检查并自动补上 BOM
    .\Check-BOM.ps1 -Path 目录   指定要检查的目录
#>
param(
    [switch]$Fix,
    [string]$Path
)

$ErrorActionPreference = 'Stop'

if (-not $Path) { $Path = $PSScriptRoot }
if (-not (Test-Path $Path)) {
    Write-Host "路径不存在: $Path" -ForegroundColor Red
    exit 2
}

$Utf8Bom = [byte[]](0xEF, 0xBB, 0xBF)

function Test-HasBom([byte[]]$bytes) {
    return ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)
}

$targets = @(Get-ChildItem -Path $Path -Recurse -File -Include '*.ps1', '*.vbs' -ErrorAction SilentlyContinue |
             Where-Object { $_.FullName -notmatch '\\_backup_' })

if ($targets.Count -eq 0) {
    Write-Host "没找到 .ps1 / .vbs 文件" -ForegroundColor Yellow
    exit 0
}

Write-Host ''
Write-Host "检查 $($targets.Count) 个文件（$Path）" -ForegroundColor Cyan
Write-Host ('-' * 62)

$bad = @()
$fixed = 0

foreach ($f in $targets) {
    # .vbs 由 Windows Script Host 读取，必须是系统 ANSI(GBK)，加 BOM 反而会出错
    if ($f.Extension -eq '.vbs') {
        Write-Host ("  [跳过] {0}  （VBS 应为 GBK，不加 BOM）" -f $f.Name) -ForegroundColor DarkGray
        continue
    }

    $bytes = [System.IO.File]::ReadAllBytes($f.FullName)
    $hasBom = Test-HasBom $bytes

    # 是否需要 BOM：文件里含非 ASCII 字符
    $text = $null
    if ($hasBom) {
        $text = [System.Text.Encoding]::UTF8.GetString($bytes, 3, $bytes.Length - 3)
    } else {
        # 先按 UTF-8 试解，若出现替换字符说明不是合法 UTF-8
        $text = [System.Text.Encoding]::UTF8.GetString($bytes)
    }
    $hasNonAscii = $false
    foreach ($ch in $text.ToCharArray()) {
        if ([int]$ch -gt 127) { $hasNonAscii = $true; break }
    }

    if (-not $hasNonAscii) {
        Write-Host ("  [跳过] {0}  （纯 ASCII，无需 BOM）" -f $f.Name) -ForegroundColor DarkGray
        continue
    }

    if ($hasBom) {
        # 再确认 BOM 后的内容是合法 UTF-8
        $decoded = [System.Text.Encoding]::UTF8.GetString($bytes, 3, $bytes.Length - 3)
        if ($decoded.Contains([char]0xFFFD)) {
            Write-Host ("  [警告] {0}  有 BOM 但内容不是合法 UTF-8" -f $f.Name) -ForegroundColor Yellow
            $bad += [pscustomobject]@{ File = $f.Name; Problem = '内容非 UTF-8'; Fixed = $false }
        } else {
            Write-Host ("  [正常] {0}" -f $f.Name) -ForegroundColor Green
        }
        continue
    }

    # 没有 BOM 且含中文 —— 危险
    $isValidUtf8 = -not $text.Contains([char]0xFFFD)
    $desc = if ($isValidUtf8) { '缺 UTF-8 BOM（PowerShell 会按 GBK 解析）' } else { '编码异常' }

    if ($Fix -and $isValidUtf8) {
        $new = New-Object byte[] ($bytes.Length + 3)
        [Array]::Copy($Utf8Bom, 0, $new, 0, 3)
        [Array]::Copy($bytes, 0, $new, 3, $bytes.Length)
        [System.IO.File]::WriteAllBytes($f.FullName, $new)
        $fixed++
        Write-Host ("  [已修复] {0}  ← 已补 BOM" -f $f.Name) -ForegroundColor Green
        $bad += [pscustomobject]@{ File = $f.Name; Problem = $desc; Fixed = $true }
    } else {
        Write-Host ("  [需修复] {0}  {1}" -f $f.Name, $desc) -ForegroundColor Red
        $bad += [pscustomobject]@{ File = $f.Name; Problem = $desc; Fixed = $false }
    }
}

Write-Host ('-' * 62)

# 语法检查
Write-Host ''
Write-Host '语法检查' -ForegroundColor Cyan
$syntaxBad = 0
foreach ($f in ($targets | Where-Object { $_.Extension -eq '.ps1' })) {
    $perr = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile($f.FullName, [ref]$null, [ref]$perr)
    if ($perr -and $perr.Count -gt 0) {
        $syntaxBad++
        Write-Host ("  [语法错误] {0}" -f $f.Name) -ForegroundColor Red
        $perr | Select-Object -First 3 | ForEach-Object {
            Write-Host ("      行 {0}: {1}" -f $_.Extent.StartLineNumber, $_.Message) -ForegroundColor DarkRed
        }
    } else {
        Write-Host ("  [通过] {0}" -f $f.Name) -ForegroundColor Green
    }
}

Write-Host ''
$badCount = @($bad).Count
if ($badCount -eq 0 -and $syntaxBad -eq 0) {
    Write-Host '全部正常' -ForegroundColor Green
    exit 0
}

if ($Fix -and $fixed -gt 0) {
    Write-Host ("已修复 {0} 个文件的 BOM" -f $fixed) -ForegroundColor Green
}
$remaining = @($bad | Where-Object { -not $_.Fixed }).Count
if ($remaining -gt 0) {
    Write-Host ("还有 {0} 个文件需要处理，运行 .\Check-BOM.ps1 -Fix 自动补 BOM" -f $remaining) -ForegroundColor Yellow
}
if ($syntaxBad -gt 0) {
    Write-Host ("有 {0} 个文件存在语法错误，需手动修复" -f $syntaxBad) -ForegroundColor Red
    exit 1
}
exit 0