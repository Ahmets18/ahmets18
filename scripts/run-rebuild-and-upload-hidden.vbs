Set shell = CreateObject("WScript.Shell")
Set fso = CreateObject("Scripting.FileSystemObject")

scriptDir = fso.GetParentFolderName(WScript.ScriptFullName)
command = "cmd.exe /c """ & scriptDir & "\run-rebuild-and-upload.cmd"""

shell.Run command, 0, False
