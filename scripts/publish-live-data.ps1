param(
  [string]$RootDir = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path,
  [string]$DatabasePath = (Join-Path (Resolve-Path (Join-Path $PSScriptRoot "..")).Path "data\database.txt")
)

$ErrorActionPreference = "Stop"

if (-not (Test-Path -LiteralPath $DatabasePath)) {
  throw "Database not found: $DatabasePath"
}

$relativeDatabasePath = "data/database.txt"
$status = & git -C $RootDir status --porcelain -- $relativeDatabasePath
if ([string]::IsNullOrWhiteSpace(($status | Out-String))) {
  Write-Host "Live data publish skipped: no database changes."
  return
}

& git -C $RootDir add -- $relativeDatabasePath
if ($LASTEXITCODE -ne 0) {
  throw "git add failed for $relativeDatabasePath"
}

$database = Get-Content -LiteralPath $DatabasePath -Raw | ConvertFrom-Json
$timestamp = Get-Date -Date $database.generatedAt -Format "yyyy-MM-dd HH:mm"
$message = "Refresh live data $timestamp"

& git -C $RootDir commit --only -m $message -- $relativeDatabasePath
if ($LASTEXITCODE -ne 0) {
  throw "git commit failed for $relativeDatabasePath"
}

& git -C $RootDir push origin main
if ($LASTEXITCODE -ne 0) {
  throw "git push failed"
}

Write-Host "Live data published: $timestamp"
