#Requires -Version 5.1
<#
  smoke-test.ps1
  启动刚编译好的 exe，检查界面能否正常构建（防止漏打包模块导致空白界面）
  用法：.\build\smoke-test.ps1 -ExePath <路径> [-MinElements 8]
#>
param(
    [Parameter(Mandatory = $true)][string]$ExePath,
    [int]$MinElements = 8,
    [int]$WaitSeconds = 28
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path $ExePath)) { throw "exe 不存在: $ExePath" }

$smokeDir = Join-Path $env:TEMP ('mmg_smoke_' + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Path $smokeDir -Force | Out-Null
$target = Join-Path $smokeDir 'MuMuGuard.exe'
Copy-Item $ExePath $target -Force

# 关掉正在运行的实例（单实例互斥）
Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -ErrorAction SilentlyContinue |
    Where-Object { $_.CommandLine -match 'MuMuGuardApp\.ps1' -and $_.CommandLine -notmatch 'Get-CimInstance' } |
    ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
Get-Process | Where-Object { $_.ProcessName -like 'MuMuGuard*' } | Stop-Process -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 3

Start-Process -FilePath $target | Out-Null
Start-Sleep -Seconds $WaitSeconds

Add-Type -AssemblyName UIAutomationClient
Add-Type -AssemblyName UIAutomationTypes
$uiCount = 0
try {
    $rootEl = [System.Windows.Automation.AutomationElement]::RootElement
    $cond = New-Object System.Windows.Automation.PropertyCondition(
        [System.Windows.Automation.AutomationElement]::NameProperty, 'MuMuGuard')
    $w = $rootEl.FindFirst([System.Windows.Automation.TreeScope]::Children, $cond)
    if ($w) {
        foreach ($x in $w.FindAll([System.Windows.Automation.TreeScope]::Descendants,
                [System.Windows.Automation.Condition]::TrueCondition)) {
            if ($x.Current.Name) { $uiCount++ }
        }
    }
} catch { }

Get-Process | Where-Object { $_.ProcessName -like 'MuMuGuard*' } | Stop-Process -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 2
Remove-Item $smokeDir -Recurse -Force -ErrorAction SilentlyContinue

if ($uiCount -lt $MinElements) {
    throw ("exe 冒烟测试失败：界面元素只有 {0} 个（应 ≥ {1}），可能漏打包模块" -f $uiCount, $MinElements)
}

Write-Host ("  OK  界面元素 {0} 个" -f $uiCount)