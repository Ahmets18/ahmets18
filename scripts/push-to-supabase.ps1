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
$tempPayload = $null
$tempScript = $null
try {
  $tempPayload = New-TemporaryFile
  [System.IO.File]::WriteAllText($tempPayload.FullName, $payload, [System.Text.UTF8Encoding]::new($false))
  $tempScript = Join-Path $env:TEMP ("supabase-push-" + ([Guid]::NewGuid().ToString("N")) + ".cjs")

  $env:SUPABASE_PAYLOAD_FILE = $tempPayload.FullName
  $env:SUPABASE_ENDPOINT = $endpoint
  $env:SUPABASE_SERVICE_KEY = $supabaseServiceKey

  $nodeScript = @'
const fs = require("node:fs");

const payloadPath = process.env.SUPABASE_PAYLOAD_FILE;
const endpoint = process.env.SUPABASE_ENDPOINT;
const serviceKey = process.env.SUPABASE_SERVICE_KEY;

(async () => {
  try {
    const payload = fs.readFileSync(payloadPath, "utf8");
    const response = await fetch(endpoint, {
      method: "POST",
      headers: {
        apikey: serviceKey,
        Authorization: `Bearer ${serviceKey}`,
        "Content-Type": "application/json",
        Prefer: "resolution=merge-duplicates,return=minimal"
      },
      body: payload
    });
    const body = await response.text();
    process.stdout.write(JSON.stringify({ status: response.status, body }));
    if (!response.ok) {
      process.exitCode = 1;
    }
  }
  catch (error) {
    process.stdout.write(JSON.stringify({ status: 0, body: String(error && error.stack ? error.stack : error) }));
    process.exitCode = 1;
  }
})();
'@

  Set-Content -LiteralPath $tempScript -Value $nodeScript -Encoding utf8
  $nodeResult = & node $tempScript
  $nodeExitCode = $LASTEXITCODE
  $nodeOutput = ($nodeResult | Out-String).Trim()
  $response = $null
  if ($nodeOutput) {
    try {
      $response = $nodeOutput | ConvertFrom-Json
    }
    catch {
      $response = $null
    }
  }

  if ($nodeExitCode -ne 0 -and $null -eq $response) {
    throw "node exit code $nodeExitCode. Raw output: $nodeOutput"
  }

  if ($nodeExitCode -ne 0) {
    if ($response.body) {
      throw "Supabase publish failed with HTTP $($response.status). Response: $($response.body)"
    }
    throw "node exit code $nodeExitCode"
  }

  if ($response.status -notin @(200, 201, 204)) {
    if ($response.body) {
      throw "Supabase publish failed with HTTP $($response.status). Response: $($response.body)"
    }
    throw "Supabase publish failed with HTTP $($response.status)."
  }
}
catch {
  throw
}
finally {
  if ($null -ne $tempPayload -and (Test-Path -LiteralPath $tempPayload)) {
    Remove-Item -LiteralPath $tempPayload -Force
  }
  if ($null -ne $tempScript -and (Test-Path -LiteralPath $tempScript)) {
    Remove-Item -LiteralPath $tempScript -Force
  }
  Remove-Item Env:\SUPABASE_PAYLOAD_FILE -ErrorAction SilentlyContinue
  Remove-Item Env:\SUPABASE_ENDPOINT -ErrorAction SilentlyContinue
  Remove-Item Env:\SUPABASE_SERVICE_KEY -ErrorAction SilentlyContinue
}

Write-Host "Published $($rows.Count) rows to Supabase table '$supabaseTable'."
