#Requires -Version 5.1
<#
  Check-Syntax.ps1
  解析所有 .ps1 脚本，检查语法错误。供 CI 调用（避免在 YAML 里写内联中文脚本，
  因为没有 BOM 的临时文件会被 PS 5.1 按 GBK 解析）。
#>
$ErrorActionPreference = 'Continue'
$dir = Split-Path $PSScriptRoot -Parent

$files = @(Join-Path $dir 'MuMuGuardApp.ps1')
$files += @(Get-ChildItem (Join-Path $dir 'lib') -Filter '*.ps1' -ErrorAction SilentlyContinue | ForEach-Object { $_.FullName })
$files += @(Get-ChildItem (Join-Path $dir 'build') -Filter '*.ps1' -ErrorAction SilentlyContinue | ForEach-Object { $_.FullName })
$files += @(Get-ChildItem (Join-Path $dir 'tests') -Filter '*.ps1' -ErrorAction SilentlyContinue | ForEach-Object { $_.FullName })
$files += @(Join-Path $dir 'Check-BOM.ps1')
$files += @((Join-Path $dir 'Waker.ps1'), (Join-Path $dir 'Restart-Instance.ps1'), (Join-Path $dir 'Update-Helper.ps1'))

$bad = 0
foreach ($f in $files) {
    if (-not (Test-Path $f)) { continue }
    $err = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile($f, [ref]$null, [ref]$err)
    if ($err -and $err.Count -gt 0) {
        Write-Host ("SYNTAX ERROR  {0}:{1}  {2}" -f (Split-Path $f -Leaf), $err[0].Extent.StartLineNumber, $err[0].Message)
        $bad++
    }
}

if ($bad -gt 0) {
    Write-Host ("语法检查失败: {0} 个文件有问题" -f $bad)
    exit 1
}
Write-Host ("语法检查通过（{0} 个文件）" -f @($files | Where-Object { Test-Path $_ }).Count)
exit 0
