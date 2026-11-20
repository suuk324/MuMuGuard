#Requires -Version 5.1
<#
smoke-test.ps1
启动刚编译好的 exe，检查：
1. 自检模式（MMG_UITEST=1）：把界面上所有安全按钮都点一遍，逐项 PASS/FAIL
2. 正常启动：窗口能出现，界面文字渲染出来
用法：.\build\smoke-test.ps1 -ExePath <路径>
#>
param(
    [Parameter(Mandatory = $true)][string]$ExePath,
    [int]$WaitSeconds = 150
)

$ErrorActionPreference = 'Stop'
if (-not (Test-Path $ExePath)) { throw "exe 不存在: $ExePath" }

$smokeDir = Join-Path $env:TEMP ('mmg_smoke_' + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Path $smokeDir -Force | Out-Null
$target = Join-Path $smokeDir 'MuMuGuard.exe'
Copy-Item $ExePath $target -Force

# 关掉正在运行的实例（单实例互斥）
Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -ErrorAction SilentlyContinue |
    Where-Object { $_.CommandLine -and $_.CommandLine -match 'MuMuGuardApp\.ps1' } |
    ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
Get-Process | Where-Object { $_.ProcessName -like 'MuMuGuard*' } | Stop-Process -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 3

$logCandidates = @(
    (Join-Path $smokeDir 'logs\uitest.log'),
    (Join-Path $env:LOCALAPPDATA 'MuMuGuard\logs\uitest.log'),
    (Join-Path $env:APPDATA 'MuMuGuard\logs\uitest.log')
)
foreach ($p in $logCandidates) { Remove-Item $p -Force -ErrorAction SilentlyContinue }

# ---------- 1. 自检模式 ----------
$env:MMG_UITEST = '1'
$proc = $null
for ($i = 1; $i -le 5; $i++) {
    try { $proc = Start-Process -FilePath $target -PassThru -ErrorAction Stop; break }
    catch { if ($i -ge 5) { throw }; Start-Sleep -Seconds 3 }
}
[void]$proc.WaitForExit($WaitSeconds * 1000)
$env:MMG_UITEST = ''
Start-Sleep -Seconds 1
if (-not $proc.HasExited) {
    try { $proc.Kill() } catch { }
    throw '自检模式没有在超时内结束'
}

$log = $null
foreach ($p in $logCandidates) { if (Test-Path $p) { $log = $p; break } }
if (-not $log) { throw '自检没有生成 uitest.log（界面可能没起来）' }

$lines = Get-Content $log -Encoding UTF8
$pass = @($lines | Where-Object { $_ -match '^PASS' }).Count
$fail = @($lines | Where-Object { $_ -match '^FAIL|^MISS' })
if ($fail.Count -gt 0) {
    throw ('自检有 {0} 项失败：{1}' -f $fail.Count, ($fail -join ' / '))
}
if ($pass -lt 12) { throw ("自检只跑了 {0} 项，太少（界面元素可能缺失）" -f $pass) }

# ---------- 2. 正常启动 ----------
$proc2 = $null
for ($i = 1; $i -le 5; $i++) {
    try { $proc2 = Start-Process -FilePath $target -PassThru -ErrorAction Stop; break }
    catch { if ($i -ge 5) { throw }; Start-Sleep -Seconds 3 }
}
Start-Sleep -Seconds 18

Add-Type -AssemblyName System.Drawing
Add-Type @"
using System;using System.Runtime.InteropServices;
public class SmokeShot {
  [DllImport("user32.dll")] public static extern bool PrintWindow(IntPtr h, IntPtr hdc, uint f);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
  public struct RECT { public int L,T,R,B; }
}
"@
try { [void][SmokeShot]::SetProcessDPIAware() } catch { }

$proc2.Refresh()
$h = $proc2.MainWindowHandle
if ($h -eq [IntPtr]::Zero) { try { $proc2.Kill() } catch { }; throw "正常启动后没有主窗口" }
$rect = New-Object SmokeShot+RECT
[void][SmokeShot]::GetWindowRect($h, [ref]$rect)
$w = $rect.R - $rect.L
$ht = $rect.B - $rect.T
if ($w -lt 800 -or $ht -lt 500) { try { $proc2.Kill() } catch { }; throw ("主窗口尺寸异常: {0}x{1}" -f $w, $ht) }

$bmp = New-Object System.Drawing.Bitmap $w, $ht
$g = [System.Drawing.Graphics]::FromImage($bmp)
$hdc = $g.GetHdc()
[void][SmokeShot]::PrintWindow($h, $hdc, 2)
$g.ReleaseHdc($hdc); $g.Dispose()
try { $bmp.Save((Join-Path $PSScriptRoot "..\docs\screenshots\exe-smoke.png"), [System.Drawing.Imaging.ImageFormat]::Png) } catch { }

$colors = @{}
for ($x = 0; $x -lt $w; $x += 40) {
    for ($y = 0; $y -lt $ht; $y += 40) {
        $c = $bmp.GetPixel($x, $y).ToArgb()
        if (-not $colors.ContainsKey($c)) { $colors[$c] = $true }
    }
}
$bmp.Dispose()
if ($colors.Count -lt 12) { try { $proc2.Kill() } catch { }; throw ("界面疑似空白：抽样只有 {0} 种颜色" -f $colors.Count) }

try { $proc2.CloseMainWindow() | Out-Null } catch { }
Start-Sleep -Seconds 2
Get-Process | Where-Object { $_.ProcessName -like "MuMuGuard*" } | Stop-Process -Force -ErrorAction SilentlyContinue

Remove-Item $smokeDir -Recurse -Force -ErrorAction SilentlyContinue
Write-Host ("  OK  自检 {0} 项全过，窗口 {1}x{2}，画面颜色 {3} 种" -f $pass, $w, $ht, $colors.Count)
