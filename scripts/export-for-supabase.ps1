param(
  [string]$DatabasePath = (Join-Path $PSScriptRoot "..\data\database.txt"),
  [string]$OutputCsvPath = (Join-Path $PSScriptRoot "..\exports\orders.supabase.csv"),
  [string]$OutputJsonPath = (Join-Path $PSScriptRoot "..\exports\orders.supabase.json")
)

$ErrorActionPreference = "Stop"

function Ensure-Directory {
  param([string]$Path)
  $dir = Split-Path -Parent $Path
  if (-not (Test-Path -LiteralPath $dir)) {
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
  }
}

function Clean-Text {
  param([object]$Value)
  if ($null -eq $Value) { return "" }
  $text = [string]$Value
  if ([string]::IsNullOrWhiteSpace($text)) { return "" }
  return ($text -replace "\s+", " ").Trim()
}

function Normalize-List {
  param([object]$Items)
  if ($null -eq $Items) { return @() }
  if ($Items -is [string]) { return @($Items) }
  if ($Items -is [System.Collections.IEnumerable]) { return @($Items) }
  return @($Items)
}

function Convert-ToJsonText {
  param([object]$Value)
  if ($null -eq $Value) { return "[]" }
  return ($Value | ConvertTo-Json -Depth 10 -Compress)
}

function Format-DateValue {
  param([object]$Value)
  $text = Clean-Text $Value
  if (-not $text) { return $null }
  try {
    return ([datetime]::Parse($text)).ToString("o")
  }
  catch {
    return $text
  }
}

if (-not (Test-Path -LiteralPath $DatabasePath)) {
  throw "Database not found: $DatabasePath"
}

$database = Get-Content -LiteralPath $DatabasePath -Raw | ConvertFrom-Json
$records = @($database.records)
if (-not $records.Count) {
  Write-Host "No records found in database file."
  return
}

$rows = foreach ($record in $records) {
  [pscustomobject]@{
    id = Clean-Text $record.id
    customer_name = Clean-Text $record.customerName
    material = Clean-Text $record.material
    color = Clean-Text $record.color
    pvc_meters = $record.pvcMeters
    quantity = $record.quantity
    cut_status = Clean-Text $record.cutStatus
    notes = Clean-Text $record.notes
    cell_highlights = Convert-ToJsonText (Normalize-List $record.cellHighlights)
    range_notes = Convert-ToJsonText (Normalize-List $record.rangeNotes)
    order_date = Format-DateValue $record.orderDate
    source_file = Clean-Text $record.sourceFile
    sheet_name = Clean-Text $record.sheetName
    source_row = $record.sourceRow
    updated_at = Format-DateValue $record.updatedAt
  }
}

Ensure-Directory -Path $OutputCsvPath
Ensure-Directory -Path $OutputJsonPath

$rows | Export-Csv -LiteralPath $OutputCsvPath -NoTypeInformation -Encoding utf8
$rows | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $OutputJsonPath -Encoding utf8

Write-Host "Exported $($rows.Count) rows to:"
Write-Host " - $OutputCsvPath"
Write-Host " - $OutputJsonPath"
