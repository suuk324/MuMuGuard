#Requires -Version 5.1
<#
  smoke-test.ps1
  启动刚编译好的 exe，检查两件事：
    1. 界面能否正常构建（防止漏打包模块导致空白界面）
    2. 点「手机访问」能否真的弹出窗口（1.6.0 就是这里静默失败）
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

$proc = Start-Process -FilePath $target -PassThru
$exePid = $proc.Id
Start-Sleep -Seconds $WaitSeconds

Add-Type -AssemblyName UIAutomationClient
Add-Type -AssemblyName UIAutomationTypes

# 读取该进进程所有可见窗口的标题（对话框是属主窗口，UIA 不一定列在根节点下）
if (-not ('SmokeWin' -as [type])) {
Add-Type -TypeDefinition @"
using System;
using System.Text;
using System.Collections.Generic;
using System.Runtime.InteropServices;
public class SmokeWin {
    [DllImport("user32.dll")] public static extern bool EnumWindows(EP cb, IntPtr p);
    public delegate bool EP(IntPtr h, IntPtr p);
    [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
    [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
    [DllImport("user32.dll")] public static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
    [DllImport("user32.dll")] public static extern IntPtr SendMessage(IntPtr h, uint msg, IntPtr w, IntPtr l);
    public static List<string> Titles(uint pid) {
        var list = new List<string>();
        EnumWindows((h, p) => {
            uint q; GetWindowThreadProcessId(h, out q);
            if (q == pid && IsWindowVisible(h)) {
                var sb = new StringBuilder(256);
                GetWindowText(h, sb, 256);
                if (sb.Length > 0) list.Add(sb.ToString());
            }
            return true;
        }, IntPtr.Zero);
        return list;
    }
    public static void CloseByTitle(uint pid, string title) {
        EnumWindows((h, p) => {
            uint q; GetWindowThreadProcessId(h, out q);
            if (q == pid && IsWindowVisible(h)) {
                var sb = new StringBuilder(256);
                GetWindowText(h, sb, 256);
                if (sb.ToString() == title) SendMessage(h, 0x0010, IntPtr.Zero, IntPtr.Zero);
            }
            return true;
        }, IntPtr.Zero);
    }
}
"@
}

$uiCount = 0
$mainWin = $null
try {
    $rootEl = [System.Windows.Automation.AutomationElement]::RootElement
    $cond = New-Object System.Windows.Automation.PropertyCondition(
        [System.Windows.Automation.AutomationElement]::NameProperty, 'MuMuGuard')
    $mainWin = $rootEl.FindFirst([System.Windows.Automation.TreeScope]::Children, $cond)
    if ($mainWin) {
        foreach ($x in $mainWin.FindAll([System.Windows.Automation.TreeScope]::Descendants,
                [System.Windows.Automation.Condition]::TrueCondition)) {
            if ($x.Current.Name) { $uiCount++ }
        }
    }
} catch { }

$result = @{ Ok = $false; Why = ''; Elements = $uiCount; Dialog = $false }

if ($uiCount -lt $MinElements) {
    $result.Why = ("界面元素只有 {0} 个（应 ≥ {1}），可能漏打包模块" -f $uiCount, $MinElements)
} else {
    # 切到详情页，再点「手机访问」
    $btnType = [System.Windows.Automation.ControlType]::Button
    $btnCond = New-Object System.Windows.Automation.PropertyCondition(
        [System.Windows.Automation.AutomationElement]::ControlTypeProperty, $btnType)
    try {
        $btns = $mainWin.FindAll([System.Windows.Automation.TreeScope]::Descendants, $btnCond)
        foreach ($b in $btns) {
            if ($b.Current.Name -eq '详情') {
                $b.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern).Invoke()
                break
            }
        }
        Start-Sleep -Seconds 2

        $target2 = $null
        $btns = $mainWin.FindAll([System.Windows.Automation.TreeScope]::Descendants, $btnCond)
        foreach ($b in $btns) {
            if ($b.Current.Name -eq '手机访问') { $target2 = $b; break }
        }

        if (-not $target2) {
            $result.Why = '界面上找不到「手机访问」按钮'
        } else {
            # 对话框是模态的，Invoke 会一直阻塞；放到独立线程里点，主线程继续检查
            $ps = [powershell]::Create()
            [void]$ps.AddScript({
                param($el)
                $el.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern).Invoke()
            }).AddArgument($target2)
            $handle = $ps.BeginInvoke()

            $found = $false
            for ($i = 0; $i -lt 16; $i++) {
                Start-Sleep -Milliseconds 500
                $titles = @()
                try { $titles = [SmokeWin]::Titles([uint32]$exePid) } catch { }
                if ($titles -contains '手机访问') { $found = $true; break }
            }
            $result.Dialog = $found

            # 收尾：关掉对话框，停掉阻塞的线程
            try { [SmokeWin]::CloseByTitle([uint32]$exePid, '手机访问') } catch { }
            Start-Sleep -Milliseconds 600
            try { [void]$ps.Stop() } catch { }
            try { $ps.Dispose() } catch { }

            if (-not $found) {
                $result.Why = '点了「手机访问」但没有弹出窗口'
                $diag = Join-Path $smokeDir 'logs\diag.log'
                if (Test-Path $diag) {
                    $tail = Get-Content $diag -ErrorAction SilentlyContinue |
                            Where-Object { $_ -match '手机访问' } | Select-Object -Last 2
                    if ($tail) { $result.Why += ('；日志: ' + ($tail -join ' / ')) }
                }
            } else {
                $result.Ok = $true
            }
        }
    } catch {
        $result.Why = ('点击「手机访问」时出错: ' + $_.Exception.Message)
    }
}

Get-Process | Where-Object { $_.ProcessName -like 'MuMuGuard*' } | Stop-Process -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 2
Remove-Item $smokeDir -Recurse -Force -ErrorAction SilentlyContinue

if (-not $result.Ok) {
    throw ('exe 冒烟测试失败：' + $result.Why)
}

Write-Host ("  OK  界面元素 {0} 个，手机访问窗口正常弹出" -f $result.Elements)