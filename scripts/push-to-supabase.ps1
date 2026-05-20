param(
  [string]$DatabasePath = (Join-Path $PSScriptRoot "..\data\database.txt"),
  [string]$SecretsPath = (Join-Path $PSScriptRoot "..\secrets\supabase.local.json")
)

$ErrorActionPreference = "Stop"

if (-not (Test-Path -LiteralPath $DatabasePath)) {
  throw "Database not found: $DatabasePath"
}

if (-not (Test-Path -LiteralPath $SecretsPath)) {
  throw "Supabase secrets not found: $SecretsPath"
}

function Read-JsonFile {
  param([string]$Path)
  return Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
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

$config = Read-JsonFile -Path $SecretsPath
$supabaseUrl = ([string]$config.url).Trim()
$supabaseServiceKey = ([string]$config.serviceKey).Trim()
$supabaseTable = if ([string]::IsNullOrWhiteSpace([string]$config.table)) { "orders" } else { ([string]$config.table).Trim() }

if ([string]::IsNullOrWhiteSpace($supabaseUrl) -or [string]::IsNullOrWhiteSpace($supabaseServiceKey)) {
  throw "Supabase url and service key are required."
}

$database = Read-JsonFile -Path $DatabasePath
$rows = @($database.records)

if (-not $rows.Count) {
  Write-Host "No records to publish."
  return
}

$baseEndpoint = "$($supabaseUrl.TrimEnd('/'))/rest/v1/$supabaseTable"
$batchSize = 100
$published = 0
$cleanupResponse = $null

try {
  $cleanupResponse = New-TemporaryFile
  $cleanupEndpoint = "$($supabaseUrl.TrimEnd('/'))/rest/v1/${supabaseTable}?id=neq.__no_such_id__"
  $cleanupArgs = @(
    "--globoff",
    "-s",
    "-o", $cleanupResponse.FullName,
    "-w", "%{http_code}",
    "-X", "DELETE",
    $cleanupEndpoint,
    "-H", ("apikey: " + $supabaseServiceKey),
    "-H", ("Authorization: Bearer " + $supabaseServiceKey),
    "-H", "Prefer: return=minimal",
    "-H", "Accept: application/json"
  )
  $deleteCode = & curl.exe @cleanupArgs

  if ($LASTEXITCODE -ne 0) {
    $responseBody = Get-Content -LiteralPath $cleanupResponse.FullName -Raw -ErrorAction SilentlyContinue
    throw "Supabase cleanup failed. curl exit code $LASTEXITCODE. Response: $responseBody"
  }

  if ($deleteCode -notin @("200", "204")) {
    $responseBody = Get-Content -LiteralPath $cleanupResponse.FullName -Raw -ErrorAction SilentlyContinue
    if ($responseBody) {
      throw "Supabase cleanup failed with HTTP $deleteCode. Response: $responseBody"
    }
    throw "Supabase cleanup failed with HTTP $deleteCode."
  }

  Write-Host "Supabase table cleared."

  for ($offset = 0; $offset -lt $rows.Count; $offset += $batchSize) {
    $batch = $rows | Select-Object -Skip $offset -First $batchSize
    if (-not $batch.Count) {
      continue
    }

    $payload = @($batch | ForEach-Object { Convert-ToSupabaseRow $_ }) | ConvertTo-Json -Depth 12
    $payloadFile = New-TemporaryFile
    $responseFile = New-TemporaryFile
    try {
      [System.IO.File]::WriteAllText($payloadFile.FullName, $payload, [System.Text.UTF8Encoding]::new($false))
      $postArgs = @(
        "--globoff",
        "-s",
        "-o", $responseFile.FullName,
        "-w", "%{http_code}",
        "-X", "POST",
        $baseEndpoint,
        "-H", ("apikey: " + $supabaseServiceKey),
        "-H", ("Authorization: Bearer " + $supabaseServiceKey),
        "-H", "Prefer: return=minimal",
        "-H", "Accept: application/json",
        "-H", "Content-Type: application/json",
        "--data-binary", "@$($payloadFile.FullName)"
      )
      $httpCode = & curl.exe @postArgs

      if ($LASTEXITCODE -ne 0) {
        $responseBody = Get-Content -LiteralPath $responseFile.FullName -Raw -ErrorAction SilentlyContinue
        throw "curl exit code $LASTEXITCODE. Response: $responseBody"
      }

      if ($httpCode -notin @("200", "201", "204")) {
        $responseBody = Get-Content -LiteralPath $responseFile.FullName -Raw -ErrorAction SilentlyContinue
        if ($responseBody) {
          throw "Supabase publish failed with HTTP $httpCode. Response: $responseBody"
        }
        throw "Supabase publish failed with HTTP $httpCode."
      }
    }
    finally {
      if (Test-Path -LiteralPath $payloadFile.FullName) {
        Remove-Item -LiteralPath $payloadFile.FullName -Force
      }
      if (Test-Path -LiteralPath $responseFile.FullName) {
        Remove-Item -LiteralPath $responseFile.FullName -Force
      }
    }

    $published += $batch.Count
    Write-Host "Published rows $($offset + 1)-$($offset + $batch.Count)"
  }

  Write-Host "Supabase upload complete. $published rows published."
}
finally {
  if ($cleanupResponse -and (Test-Path -LiteralPath $cleanupResponse.FullName)) {
    Remove-Item -LiteralPath $cleanupResponse.FullName -Force
  }
}
