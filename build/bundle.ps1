#Requires -Version 5.1
<#
  bundle.ps1
  把 lib\*.ps1 内联进主脚本，生成单文件 _build\MuMuGuard.bundle.ps1（供 PS2EXE 编译）
#>
param(
    [string]$OutDir
)

$ErrorActionPreference = 'Stop'

$root = Split-Path $PSScriptRoot -Parent
if (-not $OutDir) { $OutDir = Join-Path $root '_build' }
if (-not (Test-Path $OutDir)) { New-Item -ItemType Directory -Path $OutDir -Force | Out-Null }

$mainPath = Join-Path $root 'MuMuGuardApp.ps1'
if (-not (Test-Path $mainPath)) { throw "找不到主脚本: $mainPath" }

$main = [System.IO.File]::ReadAllText($mainPath, [System.Text.Encoding]::UTF8)

# ---- 用纯文本查找定位模块加载段（不用正则，避免意外） ----
$startMark = '# ---------------- 加载模块 ----------------'
$startIdx = $main.IndexOf($startMark)
if ($startIdx -lt 0) { throw '主脚本里找不到「加载模块」标记' }

# 从这个标记开始，找到第一个以 } 开头的行（模块加载循环的结束）
$endIdx = -1
$searchFrom = $startIdx
while ($true) {
    $nl = $main.IndexOf("`n", $searchFrom)
    if ($nl -lt 0) { break }
    $lineEnd = $main.IndexOf("`n", $nl + 1)
    if ($lineEnd -lt 0) { throw '找不到模块加载段的结束位置' }
    $lineText = $main.Substring($nl + 1, $lineEnd - $nl - 1).Trim()
    if ($lineText -eq '}') { $endIdx = $lineEnd; break }
    $searchFrom = $nl + 1
}
if ($endIdx -lt 0) { throw '找不到模块加载段的结束位置' }

$head = $main.Substring(0, $startIdx)
$tail = $main.Substring($endIdx)

# ---- 依次拼入各模块 ----
$order = @('90-pure', '00-common', '15-theme', '05-instances', '10-data', '20-actions', '30-ui', '40-tray', '50-update')
$parts = New-Object System.Collections.Generic.List[string]
$parts.Add('# ---------------- 模块（已内联）----------------')
foreach ($name in $order) {
    $p = Join-Path $root ('lib\' + $name + '.ps1')
    if (-not (Test-Path $p)) { throw "缺少模块: $p" }
    $body = [System.IO.File]::ReadAllText($p, [System.Text.Encoding]::UTF8)
    $body = [regex]::Replace($body, '(?m)^#Requires.*\r?\n', '')
    $parts.Add('# ===== ' + $name + ' =====')
    $parts.Add($body)
}

$merged = $head + ($parts -join "`r`n") + $tail

# ---- 编译版根目录回退 ----
$rootFix = @'
$Root = $PSScriptRoot
$__self = $null
try { $__self = [System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName } catch { }
if ($__self -and $__self -match '\.exe$' -and (Test-Path $__self)) {
    $Root = Split-Path $__self -Parent
} elseif (-not $Root -or -not (Test-Path $Root)) {
    $Root = (Get-Location).Path
}
'@
$rootLine = '$Root     = $PSScriptRoot'
if ($merged.Contains($rootLine)) {
    $merged = $merged.Replace($rootLine, $rootFix.TrimEnd())
} else {
    $merged = $rootFix + "`r`n" + $merged
}

# ---- 内嵌辅助脚本（exe 模式释放到 %LOCALAPPDATA%\MuMuGuard）----
$embedLines = New-Object System.Collections.Generic.List[string]
$embedLines.Add('')
$embedLines.Add('# ---------------- 内嵌辅助脚本（编译版用）----------------')
$embedLines.Add('$script:EmbeddedHelpers = @{}')
foreach ($h in @('Waker.ps1', 'Restart-Instance.ps1', 'Update-Helper.ps1')) {
    $hp = Join-Path $root $h
    if (-not (Test-Path $hp)) { throw "缺少辅助脚本: $hp" }
    $txt = [System.IO.File]::ReadAllText($hp, [System.Text.Encoding]::UTF8)
    $b64 = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($txt))
    $embedLines.Add(("`$script:EmbeddedHelpers['{0}'] = [System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('{1}'))" -f $h, $b64))
}

$anchor = "`$ErrorActionPreference = 'Continue'"
$ai = $merged.IndexOf($anchor)
if ($ai -ge 0) {
    $cut = $ai + $anchor.Length
    $merged = $merged.Substring(0, $cut) + "`r`n" + ($embedLines -join "`r`n") + $merged.Substring($cut)
} else {
    $merged = ($embedLines -join "`r`n") + "`r`n" + $merged
}

# ---- 写出（安全软件可能短暂锁定，带重试）----
$outFile = Join-Path $OutDir 'MuMuGuard.bundle.ps1'
$written = $false
for ($i = 0; $i -lt 10; $i++) {
    try {
        if (Test-Path $outFile) { Remove-Item $outFile -Force -ErrorAction Stop }
        [System.IO.File]::WriteAllText($outFile, $merged, (New-Object System.Text.UTF8Encoding $true))
        $written = $true
        break
    } catch {
        Start-Sleep -Milliseconds 400
    }
}
if (-not $written) { throw "写入失败（文件被占用）: $outFile" }

# ---- 自检：行数必须与预期一致 ----
$expectLines = ($main -split "`r?`n").Count
$actualLines = (Get-Content $outFile -ErrorAction SilentlyContinue).Count
if ($actualLines -gt 12000) {
    throw ("合并结果异常：{0} 行（预期约 {1} 行），可能重复拼接" -f $actualLines, $expectLines)
}

$perr = $null
[void][System.Management.Automation.Language.Parser]::ParseFile($outFile, [ref]$null, [ref]$perr)
if ($perr -and $perr.Count -gt 0) {
    throw ("合并后语法错误：行 {0} {1}" -f $perr[0].Extent.StartLineNumber, $perr[0].Message)
}

Write-Host "已生成: $outFile"
Write-Host ("行数: {0}" -f $actualLines)
return $outFile