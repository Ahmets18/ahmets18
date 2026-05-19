param(
  [string]$SourcePath = ("\\ARTI\Schelling\YEDEK L" + [char]0x0130 + "STELER")
)

$scriptPath = Join-Path $PSScriptRoot "sync-from-share.ps1"
Start-Process -FilePath "powershell.exe" -WindowStyle Hidden -ArgumentList @(
  "-NoProfile"
  "-ExecutionPolicy"
  "Bypass"
  "-File"
  $scriptPath
  "-SourcePath"
  $SourcePath
  "-HiddenRun"
) | Out-Null
