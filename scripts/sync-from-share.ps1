param(
  [string]$SourcePath = ("\\ARTI\Schelling\YEDEK L" + [char]0x0130 + "STELER")
)

$ErrorActionPreference = "Stop"
$rootDir = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$dataDir = Join-Path $rootDir "data"
$databasePath = Join-Path $dataDir "database.txt"
$cutoff = (Get-Date).AddDays(-30)

$keywords = @{
  customer = @("musteri", "customer", "cari", "firma", "isim", "ad", "soyad")
  material = @("malzeme", "urun", "product", "mdf", "sunta", "plaka")
  color = @("renk", "color", "desen", "ton")
  pvcMeters = @("pvc", "metraj", "mt", "metre", "uzunluk")
  quantity = @("adet", "qty", "miktar", "parca", "parca sayisi")
  cutStatus = @("kesildi", "kesim", "durum", "status", "state")
  notes = @("not", "aciklama", "ek not", "note", "detay")
  orderDate = @("tarih", "date", "siparis tarihi", "siparis", "created")
}

function Normalize-Text {
  param([object]$Value)
  if ($null -eq $Value) { return "" }
  $text = [string]$Value
  if ([string]::IsNullOrWhiteSpace($text)) { return "" }

  $text = $text.Trim().ToLowerInvariant()
  $text = $text.Replace([char]0x00E7, 'c').Replace([char]0x011F, 'g').Replace([char]0x0131, 'i').Replace([char]0x00F6, 'o').Replace([char]0x015F, 's').Replace([char]0x00FC, 'u')
  $text = $text -replace "[^a-z0-9]+", " "
  return ($text -replace "\s+", " ").Trim()
}

function Clean-Text {
  param([object]$Value)
  if ($null -eq $Value) { return "" }
  return ([string]$Value -replace "\s+", " ").Trim()
}

function Is-Blank {
  param([object]$Value)
  return $null -eq $Value -or [string]::IsNullOrWhiteSpace([string]$Value)
}

function Parse-Number {
  param([object]$Value)
  $text = Clean-Text $Value
  if (-not $text) { return $null }
  $normalized = $text -replace "[^\d,.\-]", ""
  $normalized = $normalized -replace "\.", ""
  $normalized = $normalized -replace ",", "."
  $result = 0.0
  if ([double]::TryParse($normalized, [System.Globalization.NumberStyles]::Float, [System.Globalization.CultureInfo]::InvariantCulture, [ref]$result)) {
    return $result
  }
  return $null
}

function Parse-Date {
  param([object]$Value)
  if ($null -eq $Value) { return "" }
  if ($Value -is [datetime]) { return $Value.ToString("o") }

  if ($Value -is [double] -or $Value -is [single] -or $Value -is [decimal] -or $Value -is [int] -or $Value -is [long]) {
    try { return [datetime]::FromOADate([double]$Value).ToString("o") } catch { return "" }
  }

  $text = Clean-Text $Value
  if (-not $text) { return "" }

  if ($text -match '^(?<day>\d{1,2})[./-](?<month>\d{1,2})[./-](?<year>\d{4})$') {
    try { return [datetime]::new([int]$Matches.year, [int]$Matches.month, [int]$Matches.day).ToString("o") } catch { return "" }
  }

  if ($text -match '^(?<year>\d{4})[./-](?<month>\d{1,2})[./-](?<day>\d{1,2})$') {
    try { return [datetime]::new([int]$Matches.year, [int]$Matches.month, [int]$Matches.day).ToString("o") } catch { return "" }
  }

  try { return ([datetime]::Parse($text)).ToString("o") } catch { return "" }
}

function Normalize-CutStatus {
  param([object]$Value)
  $text = Normalize-Text $Value
  if (-not $text) { return "Bilinmiyor" }
  if ($text.Contains("kesilmedi") -or $text.Contains("hayir") -or $text.Contains("bekle")) { return "Kesilmedi" }
  if ($text.Contains("kesildi") -or $text.Contains("tamam") -or $text.Contains("evet") -or $text.Contains("yapildi")) { return "Kesildi" }
  return Clean-Text $Value
}

function Create-Id {
  param([object[]]$Parts)
  $tokens = foreach ($part in $Parts) {
    $normalized = Normalize-Text $part
    if ($normalized) { $normalized }
  }
  $joined = ($tokens -join "-")
  if ($joined) { return $joined }
  return "record-$([DateTimeOffset]::Now.ToUnixTimeSeconds())"
}

function Extract-CustomerFromFilename {
  param([string]$FileName)
  $base = Clean-Text ([IO.Path]::GetFileNameWithoutExtension($FileName))
  $withoutDate = $base -replace '\b\d{4}[.-]\d{2}[.-]\d{2}\b', ''
  $withoutDate = $withoutDate -replace '\b\d{2}[.-]\d{2}[.-]\d{4}\b', ''
  $withoutDate = $withoutDate -replace '\b\d{8}\b', ''
  $withoutDate = $withoutDate -replace '[_\-]+', ' '
  $withoutDate = ($withoutDate -replace '\s+', ' ').Trim()
  if ($withoutDate) { return $withoutDate }
  return $base
}

function Get-CellText {
  param(
    [object]$Worksheet,
    [int]$Row,
    [int]$Col
  )
  try {
    $value = $Worksheet.Cells.Item($Row, $Col).Value2
    if ($null -eq $value) { return "" }
    if ($value -is [datetime]) { return $value.ToString("dd.MM.yyyy") }
    return Clean-Text $value
  } catch {
    return ""
  }
}

function Get-LabelForCell {
  param(
    [object]$Worksheet,
    [int]$Row,
    [int]$Col
  )
  for ($c = $Col - 1; $c -ge 1; $c--) {
    $label = Get-CellText $Worksheet $Row $c
    if ($label) { return $label }
  }
  for ($r = $Row - 1; $r -ge 1; $r--) {
    $label = Get-CellText $Worksheet $r $Col
    if ($label) { return $label }
  }
  return ""
}

function Is-MeasurementLike {
  param([string]$Value)
  if (-not $Value) { return $false }
  return $Value -match '^\d+(\.\d+)?$' -or
    $Value -match '^\d+[xX]\d+$' -or
    $Value -match '^\d+M\s+\d+[xX]\d+$' -or
    $Value -match '^\d+MM$'
}

function Build-CellHighlights {
  param([object]$Worksheet)
  $targets = @(
    @{ Cell = "D5"; Row = 5; Col = 4 },
    @{ Cell = "D9"; Row = 9; Col = 4 },
    @{ Cell = "D10"; Row = 10; Col = 4 },
    @{ Cell = "D11"; Row = 11; Col = 4 },
    @{ Cell = "D12"; Row = 12; Col = 4 },
    @{ Cell = "O9"; Row = 9; Col = 15 },
    @{ Cell = "A15"; Row = 15; Col = 1 },
    @{ Cell = "D15"; Row = 15; Col = 4 },
    @{ Cell = "I15"; Row = 15; Col = 9 },
    @{ Cell = "C46"; Row = 46; Col = 3 }
  )

  $result = @()
  foreach ($target in $targets) {
    $value = Get-CellText $Worksheet $target.Row $target.Col
    if (-not $value) { continue }
    $label = Get-LabelForCell $Worksheet $target.Row $target.Col
    $result += [ordered]@{
      cell = $target.Cell
      label = (Clean-Text $label)
      value = $value
    }
  }
  return $result
}

function Build-RangeNotes {
  param([object]$Worksheet)
  $result = @()
  for ($r = 2; $r -le 45; $r++) {
    for ($c = 1; $c -le 20; $c++) {
      $value = Get-CellText $Worksheet $r $c
      if (-not $value) { continue }
      if (Is-MeasurementLike $value) { continue }

      $result += [ordered]@{
        cell = ([char](64 + $c)) + $r
        label = (Clean-Text (Get-LabelForCell $Worksheet $r $c))
        value = $value
      }
    }
  }
  return $result
}

function Get-Cell {
  param(
    [object[]]$Row,
    [int]$Index
  )
  if ($Index -lt 0 -or $Index -ge $Row.Count) { return $null }
  return $Row[$Index]
}

function Matches-Any {
  param(
    [string]$Value,
    [string[]]$Tokens
  )
  foreach ($token in $Tokens) {
    if ($Value.Contains($token)) { return $true }
  }
  return $false
}

function Find-HeaderRow {
  param([object[][]]$Rows)

  $bestIndex = -1
  $bestScore = 0

  for ($i = 0; $i -lt [Math]::Min($Rows.Count, 20); $i++) {
    $row = $Rows[$i]
    if (-not $row) { continue }
    $normalized = @($row | ForEach-Object { Normalize-Text $_ })
    $score = 0
    foreach ($tokens in $keywords.Values) {
      $found = $false
      foreach ($cell in $normalized) {
        foreach ($token in $tokens) {
          if ($cell.Contains($token)) {
            $found = $true
            break
          }
        }
        if ($found) { break }
      }
      if ($found) { $score++ }
    }
    if ($score -gt $bestScore) {
      $bestScore = $score
      $bestIndex = $i
    }
  }

  if ($bestScore -ge 2) { return $bestIndex }
  return -1
}

function Build-ColumnMap {
  param([string[]]$Headers)

  $map = @{}
  for ($i = 0; $i -lt $Headers.Count; $i++) {
    $header = $Headers[$i]
    if (-not $header) { continue }
    if (-not $map.ContainsKey("customer") -and (Matches-Any $header $keywords.customer)) { $map.customer = $i }
    if (-not $map.ContainsKey("material") -and (Matches-Any $header $keywords.material)) { $map.material = $i }
    if (-not $map.ContainsKey("color") -and (Matches-Any $header $keywords.color)) { $map.color = $i }
    if (-not $map.ContainsKey("pvcMeters") -and (Matches-Any $header $keywords.pvcMeters)) { $map.pvcMeters = $i }
    if (-not $map.ContainsKey("quantity") -and (Matches-Any $header $keywords.quantity)) { $map.quantity = $i }
    if (-not $map.ContainsKey("cutStatus") -and (Matches-Any $header $keywords.cutStatus)) { $map.cutStatus = $i }
    if (-not $map.ContainsKey("notes") -and (Matches-Any $header $keywords.notes)) { $map.notes = $i }
    if (-not $map.ContainsKey("orderDate") -and (Matches-Any $header $keywords.orderDate)) { $map.orderDate = $i }
  }
  return $map
}

function Row-To-Record {
  param(
    [object[]]$Row,
    [hashtable]$ColumnMap,
    [hashtable]$Meta
  )

  $customerName = Clean-Text (Get-Cell $Row ($ColumnMap.customer))
  if (-not $customerName) { $customerName = $Meta.fileCustomer }
  $material = Clean-Text (Get-Cell $Row ($ColumnMap.material))
  $color = Clean-Text (Get-Cell $Row ($ColumnMap.color))
  $pvcMeters = Parse-Number (Get-Cell $Row ($ColumnMap.pvcMeters))
  $quantity = Parse-Number (Get-Cell $Row ($ColumnMap.quantity))
  $cutStatus = Normalize-CutStatus (Get-Cell $Row ($ColumnMap.cutStatus))
  $notes = Clean-Text (Get-Cell $Row ($ColumnMap.notes))
  $orderDate = Parse-Date (Get-Cell $Row ($ColumnMap.orderDate))
  if (-not $orderDate) { $orderDate = $Meta.fileDate.ToString("o") }

  $hasUsefulContent = $customerName -or $material -or $color -or $null -ne $pvcMeters -or $null -ne $quantity -or $cutStatus -ne "Bilinmiyor" -or $notes
  if (-not $hasUsefulContent) { return $null }

  return [ordered]@{
    id = (Create-Id @($Meta.fileName, $Meta.sheetName, $Meta.rowIndex, $customerName, $material, $color))
    customerName = if ($customerName) { $customerName } else { "Bilinmeyen Musteri" }
    material = if ($material) { $material } else { "-" }
    color = if ($color) { $color } else { "-" }
    pvcMeters = $pvcMeters
    quantity = $quantity
    cutStatus = $cutStatus
    notes = if ($notes) { $notes } else { "" }
    cellHighlights = $Meta.cellHighlights
    rangeNotes = $Meta.rangeNotes
    orderDate = $orderDate
    sourceFile = $Meta.fileName
    sheetName = $Meta.sheetName
    sourceRow = $Meta.rowIndex
  }
}

function Row-To-FallbackRecord {
  param(
    [object[]]$Row,
    [int]$Index,
    [hashtable]$Meta
  )

  if (-not $Row -or ($Row | Where-Object { -not (Is-Blank $_) }).Count -eq 0) { return $null }
  $text = (($Row | ForEach-Object { Clean-Text $_ }) | Where-Object { $_ }) -join " | "
  if (-not $text) { return $null }

  return [ordered]@{
    id = (Create-Id @($Meta.fileName, $Meta.sheetName, ($Index + 1), $text))
    customerName = if ($Meta.fileCustomer) { $Meta.fileCustomer } else { "Bilinmeyen Musteri" }
    material = $text
    color = "-"
    pvcMeters = $null
    quantity = $null
    cutStatus = "Bilinmiyor"
    notes = ""
    cellHighlights = $Meta.cellHighlights
    rangeNotes = $Meta.rangeNotes
    orderDate = $Meta.fileDate.ToString("o")
    sourceFile = $Meta.fileName
    sheetName = $Meta.sheetName
    sourceRow = ($Index + 1)
  }
}

function Get-WorksheetRows {
  param($Worksheet)
  $used = $Worksheet.UsedRange
  if (-not $used) { return @() }

  $rowCount = $used.Rows.Count
  $colCount = $used.Columns.Count
  $rows = New-Object System.Collections.Generic.List[object[]]

  for ($r = 1; $r -le $rowCount; $r++) {
    $row = New-Object object[] $colCount
    for ($c = 1; $c -le $colCount; $c++) {
      $row[$c - 1] = $used.Cells.Item($r, $c).Value2
    }
    [void]$rows.Add($row)
  }

  return ,$rows.ToArray()
}

if (-not (Test-Path -LiteralPath $SourcePath)) {
  throw "Source folder not found: $SourcePath"
}

$excel = $null
$workbook = $null
$records = New-Object System.Collections.Generic.List[object]
$scannedFiles = Get-ChildItem -LiteralPath $SourcePath -Recurse -File | Where-Object {
  $_.Extension -eq ".xlsm" -and $_.LastWriteTime -ge $cutoff
}

try {
  $excel = New-Object -ComObject Excel.Application
  $excel.Visible = $false
  $excel.DisplayAlerts = $false

  foreach ($file in $scannedFiles) {
    $fileCustomer = Extract-CustomerFromFilename $file.Name
    $workbook = $excel.Workbooks.Open($file.FullName, 0, $true)

    foreach ($sheet in $workbook.Worksheets) {
      $cellHighlights = Build-CellHighlights $sheet
      $rangeNotes = Build-RangeNotes $sheet
      $rows = @(Get-WorksheetRows $sheet)
      if ($rows.Count -eq 0) { continue }

      $headerRowIndex = Find-HeaderRow $rows
      if ($headerRowIndex -lt 0) {
        for ($i = 0; $i -lt $rows.Count; $i++) {
          $record = Row-To-FallbackRecord $rows[$i] $i @{
            fileName = $file.Name
          fileCustomer = $fileCustomer
          fileDate = $file.LastWriteTime
          sheetName = $sheet.Name
          cellHighlights = $cellHighlights
          rangeNotes = $rangeNotes
        }
        if ($record) { [void]$records.Add($record) }
      }
        continue
      }

      $headers = @($rows[$headerRowIndex] | ForEach-Object { Normalize-Text $_ })
      $columnMap = Build-ColumnMap $headers

      for ($rowIndex = $headerRowIndex + 1; $rowIndex -lt $rows.Count; $rowIndex++) {
        $row = $rows[$rowIndex]
        if (-not $row -or ($row | Where-Object { -not (Is-Blank $_) }).Count -eq 0) { continue }

        $record = Row-To-Record $row $columnMap @{
          fileName = $file.Name
          fileCustomer = $fileCustomer
          fileDate = $file.LastWriteTime
          sheetName = $sheet.Name
          rowIndex = ($rowIndex + 1)
        }
        if ($record) { [void]$records.Add($record) }
      }
    }

    $workbook.Close($false)
  }
}
finally {
  if ($workbook) { [void][Runtime.InteropServices.Marshal]::ReleaseComObject($workbook) }
  if ($excel) {
    $excel.Quit()
    [void][Runtime.InteropServices.Marshal]::ReleaseComObject($excel)
  }
}

$records = @(
  $records | Sort-Object -Property @{ Expression = "orderDate"; Descending = $true }, @{ Expression = "customerName"; Descending = $false }
)

$database = [ordered]@{
  generatedAt = (Get-Date).ToString("o")
  cutoffDate = $cutoff.ToString("o")
  totalRecords = $records.Count
  totalFiles = $scannedFiles.Count
  records = $records
}

if (-not (Test-Path -LiteralPath $dataDir)) {
  New-Item -ItemType Directory -Path $dataDir -Force | Out-Null
}

$database | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $databasePath -Encoding utf8
Write-Host "database.txt updated: $databasePath"
Write-Host "Last 30 days: $($scannedFiles.Count) files, $($records.Count) records."
