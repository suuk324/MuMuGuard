' MuMuGuard 看护面板启动器
' 以无控制台窗口的方式启动 PowerShell 面板

Option Explicit

Dim fso, shell, dir, cmd
Set fso = CreateObject("Scripting.FileSystemObject")
Set shell = CreateObject("WScript.Shell")

dir = fso.GetParentFolderName(WScript.ScriptFullName)
cmd = "powershell.exe -STA -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File """ & dir & "\MuMuGuardApp.ps1"""

shell.Run cmd, 0, False
