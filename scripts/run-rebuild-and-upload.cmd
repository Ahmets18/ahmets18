@echo off
setlocal

set "ROOT=%~dp0.."
set "PS1=%ROOT%\scripts\sync-from-share.ps1"

if not exist "%PS1%" (
  echo Missing script: %PS1%
  exit /b 1
)

powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "%PS1%"
exit /b %errorlevel%
