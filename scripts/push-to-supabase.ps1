param(
  [string]$DatabasePath = (Join-Path $PSScriptRoot "..\data\database.txt")
)

$ErrorActionPreference = "Stop"

if (-not (Test-Path -LiteralPath $DatabasePath)) {
  throw "Database not found: $DatabasePath"
}

$supabaseUrl = $env:SUPABASE_URL
$supabaseServiceKey = $env:SUPABASE_SERVICE_KEY
$supabaseTable = if ($env:SUPABASE_TABLE) { $env:SUPABASE_TABLE } else { "orders" }

if (-not $supabaseUrl -or -not $supabaseServiceKey) {
  throw "SUPABASE_URL and SUPABASE_SERVICE_KEY must be set."
}

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
$endpoint = "$($supabaseUrl.TrimEnd('/'))/rest/v1/$supabaseTable?on_conflict=id"

Invoke-RestMethod -Method Post -Uri $endpoint -Headers @{
  apikey = $supabaseServiceKey
  Authorization = "Bearer $supabaseServiceKey"
  "Content-Type" = "application/json"
  Prefer = "resolution=merge-duplicates,return=minimal"
} -Body $payload | Out-Null

Write-Host "Published $($rows.Count) rows to Supabase table '$supabaseTable'."
