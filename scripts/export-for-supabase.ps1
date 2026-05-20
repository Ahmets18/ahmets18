param(
  [string]$DatabasePath = (Join-Path (Resolve-Path (Join-Path $PSScriptRoot "..")).Path "data/database.txt"),
  [string]$OutputDir = (Join-Path (Resolve-Path (Join-Path $PSScriptRoot "..")).Path "exports")
)

$ErrorActionPreference = "Stop"
$rootDir = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path

function Write-HostLine {
  param([string]$Message)
  $timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
  Write-Host "[$timestamp] $Message"
}

function Read-Database {
  param([string]$Path)
  if (-not (Test-Path -LiteralPath $Path)) {
    throw "Database not found: $Path"
  }

  $raw = Get-Content -LiteralPath $Path -Raw
  if (-not $raw.Trim()) {
    throw "Database file is empty: $Path"
  }

  return $raw | ConvertFrom-Json
}

function Flatten-Value {
  param([object]$Value)
  if ($null -eq $Value) { return "" }
  if ($Value -is [string]) { return $Value }
  if ($Value -is [System.Collections.IDictionary]) {
    return ($Value.GetEnumerator() | ForEach-Object { "$($_.Key):$($_.Value)" }) -join "; "
  }
  if ($Value -is [System.Collections.IEnumerable]) {
    return (@($Value) | ForEach-Object { Flatten-Value $_ }) -join "; "
  }
  return [string]$Value
}

function Convert-ExportRecord {
  param([object]$Record)
  return [ordered]@{
    id = $Record.id
    customerName = $Record.customerName
    d5 = $Record.d5
    material = $Record.material
    color = $Record.color
    pvcMeters = $Record.pvcMeters
    quantity = $Record.quantity
    cutStatus = $Record.cutStatus
    notes = $Record.notes
    opt = $Record.opt
    plaka = $Record.plaka
    orderDate = $Record.orderDate
    sourceFile = $Record.sourceFile
    sheetName = $Record.sheetName
    sourceRow = $Record.sourceRow
    cellHighlights = Flatten-Value $Record.cellHighlights
    rangeNotes = Flatten-Value $Record.rangeNotes
  }
}

$database = Read-Database -Path $DatabasePath
$records = @($database.records)

if (-not (Test-Path -LiteralPath $OutputDir)) {
  New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null
}

$csvPath = Join-Path $OutputDir "orders.supabase.csv"
$jsonPath = Join-Path $OutputDir "orders.supabase.json"
$exportRows = $records | ForEach-Object { Convert-ExportRecord $_ }

$exportRows | ConvertTo-Csv -NoTypeInformation | Set-Content -LiteralPath $csvPath -Encoding utf8
$exportRows | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $jsonPath -Encoding utf8

Write-HostLine "Supabase export written: $csvPath"
Write-HostLine "Supabase export written: $jsonPath"
