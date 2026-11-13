' run_guard.vbs - 无窗口运行 MuMuGuard.ps1
' 由计划任务调用，避免每次执行时闪出黑色控制台窗口

Option Explicit

Dim fso, sh, dir, cmd
Set fso = CreateObject("Scripting.FileSystemObject")
Set sh  = CreateObject("WScript.Shell")

dir = fso.GetParentFolderName(WScript.ScriptFullName)
cmd = "powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File """ & dir & "\MuMuGuard.ps1"""

' 第二个参数 0 = 隐藏窗口，第三个参数 True = 等待执行结束
sh.Run cmd, 0, True
