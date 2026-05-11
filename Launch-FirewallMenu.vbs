Option Explicit

Dim scriptPath
Dim targetItem
Dim safeTargetItem
Dim wtPath
Dim wtArgs

scriptPath = "D:\Users\joty79\scripts\Firewall\FirewallMenu.ps1"
targetItem = ""

If WScript.Arguments.Count > 0 Then
    targetItem = WScript.Arguments(0)
End If

safeTargetItem = Replace(targetItem, """", """""")

wtPath = CreateObject("WScript.Shell").ExpandEnvironmentStrings("%LOCALAPPDATA%") & "\Microsoft\WindowsApps\wt.exe"

If Len(targetItem) > 0 Then
    wtArgs = "--title ""Firewall Manager"" pwsh.exe -NoProfile -ExecutionPolicy Bypass -File """ & scriptPath & """ -TargetItem """ & safeTargetItem & """"
Else
    wtArgs = "--title ""Firewall Manager"" pwsh.exe -NoProfile -ExecutionPolicy Bypass -File """ & scriptPath & """"
End If

If Len(wtPath) > 0 Then
    CreateObject("Shell.Application").ShellExecute wtPath, wtArgs, "", "runas", 1
Else
    CreateObject("Shell.Application").ShellExecute "pwsh.exe", "-NoProfile -ExecutionPolicy Bypass -File """ & scriptPath & """ -TargetItem """ & safeTargetItem & """", "", "runas", 1
End If
