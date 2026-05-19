param(
  [string]$DatabasePath = (Join-Path $PSScriptRoot "..\data\database.txt")
)

$ErrorActionPreference = "Stop"
$rootDir = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$localConfigPath = Join-Path $rootDir "secrets\supabase.local.json"

if (-not (Test-Path -LiteralPath $DatabasePath)) {
  throw "Database not found: $DatabasePath"
}

function Read-LocalConfig {
  param([string]$Path)
  if (-not (Test-Path -LiteralPath $Path)) {
    return $null
  }

  try {
    return Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
  }
  catch {
    throw "Could not read local Supabase config: $Path"
  }
}

$localConfig = Read-LocalConfig -Path $localConfigPath
$supabaseUrl = if ($env:SUPABASE_URL) { $env:SUPABASE_URL } elseif ($null -ne $localConfig -and $localConfig.url) { $localConfig.url } else { $null }
$supabaseServiceKey = if ($env:SUPABASE_SERVICE_KEY) { $env:SUPABASE_SERVICE_KEY } elseif ($null -ne $localConfig -and $localConfig.serviceKey) { $localConfig.serviceKey } else { $null }
$supabaseTable = if ($env:SUPABASE_TABLE) { $env:SUPABASE_TABLE } elseif ($null -ne $localConfig -and $localConfig.table) { $localConfig.table } else { "orders" }

if (-not $supabaseUrl -or -not $supabaseServiceKey) {
  throw "SUPABASE_URL and SUPABASE_SERVICE_KEY must be set, or secrets\supabase.local.json must exist."
}

Write-Host "Supabase target: $supabaseUrl"
Write-Host "Supabase table: $supabaseTable"

$database = Get-Content -LiteralPath $DatabasePath -Raw | ConvertFrom-Json
$rows = @($database.records)

if (-not $rows.Count) {
  Write-Host "No records to publish."
  return
}

function Convert-ToSupabaseRow {
  param([object]$Record)

  return [ordered]@{
    id = $Record.id
    customer_name = $Record.customerName
    material = $Record.material
    color = $Record.color
    pvc_meters = $Record.pvcMeters
    quantity = $Record.quantity
    cut_status = $Record.cutStatus
    notes = $Record.notes
    cell_highlights = @($Record.cellHighlights)
    range_notes = @($Record.rangeNotes)
    order_date = $Record.orderDate
    source_file = $Record.sourceFile
    sheet_name = $Record.sheetName
    source_row = $Record.sourceRow
    updated_at = (Get-Date).ToString("o")
  }
}

$payload = @($rows | ForEach-Object { Convert-ToSupabaseRow $_ }) | ConvertTo-Json -Depth 12
$endpoint = "$($supabaseUrl.TrimEnd('/'))/rest/v1/$supabaseTable"
try {
  $tempPayload = New-TemporaryFile
  $tempResponse = New-TemporaryFile
  [System.IO.File]::WriteAllText($tempPayload.FullName, $payload, [System.Text.UTF8Encoding]::new($false))

  $curlArgs = @(
    "-sS",
    "-o", $tempResponse,
    "-w", "%{http_code}",
    "-X", "POST",
    "-H", "apikey: $supabaseServiceKey",
    "-H", "Authorization: Bearer $supabaseServiceKey",
    "-H", "Content-Type: application/json",
    "-H", "Prefer: return=minimal",
    "--data-binary", "@$($tempPayload.FullName)",
    $endpoint
  )

  $httpCode = & curl.exe @curlArgs
  if ($LASTEXITCODE -ne 0) {
    throw "curl exit code $LASTEXITCODE"
  }
  if ($httpCode -notin @("200", "201", "204")) {
    $responseBody = ""
    if (Test-Path -LiteralPath $tempResponse) {
      $responseBody = Get-Content -LiteralPath $tempResponse -Raw
    }
    if ($responseBody) {
      throw "Supabase publish failed with HTTP $httpCode. Response: $responseBody"
    }
    throw "Supabase publish failed with HTTP $httpCode."
  }
}
catch {
  throw
}
finally {
  if (Test-Path -LiteralPath $tempPayload) {
    Remove-Item -LiteralPath $tempPayload -Force
  }
  if (Test-Path -LiteralPath $tempResponse) {
    Remove-Item -LiteralPath $tempResponse -Force
  }
}

Write-Host "Published $($rows.Count) rows to Supabase table '$supabaseTable'."
