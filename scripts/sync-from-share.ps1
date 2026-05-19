param(
  [string]$SourcePath = ("\\ARTI\Schelling\YEDEK L" + [char]0x0130 + "STELER"),
  [switch]$HiddenRun
)

$ErrorActionPreference = "Stop"
$scriptPath = $PSCommandPath
if (-not $HiddenRun -and -not $env:SIPARIS_SYNC_HIDDEN) {
  $env:SIPARIS_SYNC_HIDDEN = "1"
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
  return
}
$rootDir = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$dataDir = Join-Path $rootDir "data"
$logDir = Join-Path $rootDir "logs"
$statePath = Join-Path $dataDir "sync-state.json"
$databasePath = Join-Path $dataDir "database.txt"
$localDatabaseJsPath = Join-Path $rootDir "local-database.js"
$logPath = Join-Path $logDir "sync.log"
$cutoff = (Get-Date).AddMonths(-1)

if (-not ("System.IO.Compression.ZipFile" -as [type])) {
  Add-Type -AssemblyName System.IO.Compression.FileSystem
}

function Write-Log {
  param([string]$Message)
  $timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
  $line = "[$timestamp] $Message"
  Write-Host $line
  if (-not (Test-Path -LiteralPath $logDir)) {
    New-Item -ItemType Directory -Path $logDir -Force | Out-Null
  }
  Add-Content -LiteralPath $logPath -Value $line
}

function Clean-Text {
  param([object]$Value)
  if ($null -eq $Value) { return "" }
  $text = [string]$Value
  if ([string]::IsNullOrWhiteSpace($text)) { return "" }
  return ($text -replace "\s+", " ").Trim()
}

function Normalize-Text {
  param([object]$Value)
  $text = Clean-Text $Value
  if (-not $text) { return "" }
  $text = $text.ToLowerInvariant()
  $text = $text.Replace([char]0x00E7, 'c').Replace([char]0x011F, 'g').Replace([char]0x0131, 'i').Replace([char]0x00F6, 'o').Replace([char]0x015F, 's').Replace([char]0x00FC, 'u')
  $text = $text -replace "[^a-z0-9]+", " "
  return ($text -replace "\s+", " ").Trim()
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
  param([object]$Value, [datetime]$Fallback)
  $text = Clean-Text $Value
  if (-not $text) { return $Fallback.ToString("o") }
  if ($text -match '^\d+(\.\d+)?$') {
    try { return [datetime]::FromOADate([double]$text).ToString("o") } catch {}
  }
  if ($text -match '^(?<day>\d{1,2})[./-](?<month>\d{1,2})[./-](?<year>\d{4})$') {
    try { return [datetime]::new([int]$Matches.year, [int]$Matches.month, [int]$Matches.day).ToString("o") } catch {}
  }
  if ($text -match '^(?<year>\d{4})[./-](?<month>\d{1,2})[./-](?<day>\d{1,2})$') {
    try { return [datetime]::new([int]$Matches.year, [int]$Matches.month, [int]$Matches.day).ToString("o") } catch {}
  }
  try { return ([datetime]::Parse($text)).ToString("o") } catch { return $Fallback.ToString("o") }
}

function Parse-PvcMeters {
  param(
    [object]$PrimaryValue,
    [object]$FallbackValue
  )

  $text = Clean-Text $PrimaryValue
  if ($text -match '(?<meters>\d+(?:[.,]\d+)?)\s*M\b') {
    $meters = 0.0
    if ([double]::TryParse(($Matches.meters -replace ",", "."), [System.Globalization.NumberStyles]::Float, [System.Globalization.CultureInfo]::InvariantCulture, [ref]$meters)) {
      return $meters
    }
  }

  $fallback = Parse-Number $FallbackValue
  if ($null -ne $fallback) { return $fallback }
  return $null
}

function Parse-PvcMetersFromText {
  param([object]$Value)

  $text = Clean-Text $Value
  if (-not $text) { return $null }
  if ($text -match '^(?<meters>\d+(?:[.,]\d+)?)\s*M\b') {
    $meters = 0.0
    if ([double]::TryParse(($Matches.meters -replace ",", "."), [System.Globalization.NumberStyles]::Float, [System.Globalization.CultureInfo]::InvariantCulture, [ref]$meters)) {
      return $meters
    }
  }
  if ($text -match '\b(?<meters>\d+(?:[.,]\d+)?)\s*M\b') {
    $meters = 0.0
    if ([double]::TryParse(($Matches.meters -replace ",", "."), [System.Globalization.NumberStyles]::Float, [System.Globalization.CultureInfo]::InvariantCulture, [ref]$meters)) {
      return $meters
    }
  }
  return $null
}

function Split-PlakaValue {
  param([object]$Value)

  $text = Clean-Text $Value
  if (-not $text) {
    return [ordered]@{
      plateCount = $null
      detail = ""
    }
  }

  if ($text -match '^(?<count>\d+(?:[.,]\d+)?)\s*PLK\s*(?<detail>.+)$') {
    return [ordered]@{
      plateCount = Parse-Number $Matches.count
      detail = Clean-Text $Matches.detail
    }
  }

  return [ordered]@{
    plateCount = $null
    detail = $text
  }
}

function Build-CellHighlights {
  param(
    [string]$Opt,
    [string]$Material,
    [object]$PlateCount,
    [string]$PlakaDetail,
    [object]$PvcMeters,
    [datetime]$OrderDate
  )

  $items = New-Object System.Collections.Generic.List[object]
  if ($Opt) {
    [void]$items.Add([ordered]@{ cell = "D12"; label = "OPT"; value = $Opt })
  }
  if ($Material) {
    [void]$items.Add([ordered]@{ cell = "A15"; label = "MALZEME"; value = $Material })
  }
  if ($null -ne $PlateCount -and $PlateCount -ne "") {
    [void]$items.Add([ordered]@{ cell = "C46"; label = "PLAKA ADEDI"; value = [string]$PlateCount })
  }
  if ($PlakaDetail) {
    [void]$items.Add([ordered]@{ cell = "D15"; label = "PLAKA DETAY"; value = $PlakaDetail })
  }
  if ($null -ne $PvcMeters -and $PvcMeters -ne "") {
    [void]$items.Add([ordered]@{ cell = "I15"; label = "PVC METRAJ"; value = [string]$PvcMeters })
  }
  if ($OrderDate) {
    [void]$items.Add([ordered]@{ cell = "O9"; label = "TARIH"; value = $OrderDate.ToString("o") })
  }
  return $items.ToArray()
}

function Repair-ExistingRecord {
  param([object]$Record)

  if ($null -eq $Record) { return $Record }

  $opt = Clean-Text $Record.opt
  if (-not $opt) { $opt = Clean-Text $Record.color }

  $material = Clean-Text $Record.material
  $plaka = Clean-Text $Record.plaka
  $splitPlaka = Split-PlakaValue $plaka

  $plateCount = $Record.quantity
  if (($null -eq $plateCount -or $plateCount -eq "") -and $splitPlaka.plateCount) {
    $plateCount = $splitPlaka.plateCount
  }

  $plakaDetail = $splitPlaka.detail
  $pvcMeters = Parse-PvcMetersFromText $plakaDetail
  if ($null -eq $pvcMeters) {
    $pvcMeters = Parse-PvcMetersFromText $plaka
  }
  if ($null -eq $pvcMeters) {
    $pvcMeters = Parse-Number $Record.pvcMeters
  }

  if (-not $plaka -and $plateCount -ne $null -and $plakaDetail) {
    $plaka = "$plateCount PLK $plakaDetail"
  }

  $orderDateText = Clean-Text $Record.orderDate
  $orderDate = $null
  if ($orderDateText) {
    try { $orderDate = [datetime]::Parse($orderDateText) } catch { $orderDate = $null }
  }

  $existingHighlights = @($Record.cellHighlights)
  if (-not $existingHighlights.Count) {
    $Record.cellHighlights = Build-CellHighlights -Opt $opt -Material $material -PlateCount $plateCount -PlakaDetail $plakaDetail -PvcMeters $pvcMeters -OrderDate $orderDate
  }

  if ($opt) { $Record.opt = $opt }
  if ($plaka) { $Record.plaka = $plaka }
  if ($null -ne $plateCount) { $Record.quantity = $plateCount }
  if ($null -ne $pvcMeters) { $Record.pvcMeters = $pvcMeters }
  return $Record
}

function Is-MeasurementLike {
  param([string]$Value)
  if ([string]::IsNullOrWhiteSpace($Value)) { return $false }
  $matchesNumber = $Value -match '^\d+(\.\d+)?$'
  $matchesSize = $Value -match '^\d+[xX]\d+$'
  $matchesPlate = $Value -match '^\d+M\s+\d+[xX]\d+$'
  $matchesMm = $Value -match '^\d+MM$'
  return ($matchesNumber -or $matchesSize -or $matchesPlate -or $matchesMm)
}

function Get-CustomerFromFilename {
  param([string]$FileName)
  $base = Clean-Text ([IO.Path]::GetFileNameWithoutExtension($FileName))
  $base = $base -replace '\b\d{4}[.-]\d{2}[.-]\d{2}\b', ''
  $base = $base -replace '\b\d{2}[.-]\d{2}[.-]\d{4}\b', ''
  $base = $base -replace '\b\d{8}\b', ''
  $base = $base -replace '[_\-]+', ' '
  $base = ($base -replace '\s+', ' ').Trim()
  if ($base) { return $base }
  return $FileName
}

function Get-SourceKey {
  param([string]$FileName)
  $base = Clean-Text ([IO.Path]::GetFileNameWithoutExtension($FileName))
  $compact = ($base -replace '[^A-Za-z0-9]+', '')
  if ($compact.Length -lt 4) {
    return $compact.ToUpperInvariant()
  }
  return $compact.Substring(0, 4).ToUpperInvariant()
}

function Load-State {
  if (-not (Test-Path -LiteralPath $statePath)) {
    return [ordered]@{
      processedKeys = @()
      lastRunAt = $null
    }
  }

  try {
    $state = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json
    $keys = @()
    if ($state.processedKeys) {
      $keys = @($state.processedKeys | ForEach-Object { [string]$_ })
    }
    return [ordered]@{
      processedKeys = $keys
      lastRunAt = $state.lastRunAt
    }
  }
  catch {
    return [ordered]@{
      processedKeys = @()
      lastRunAt = $null
    }
  }
}

function Save-State {
  param(
    [string[]]$ProcessedKeys,
    [string]$LastRunAt
  )

  if (-not (Test-Path -LiteralPath $dataDir)) {
    New-Item -ItemType Directory -Path $dataDir -Force | Out-Null
  }

  $state = [ordered]@{
    processedKeys = @($ProcessedKeys | Sort-Object -Unique)
    lastRunAt = $LastRunAt
  }
  $state | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $statePath -Encoding utf8
}

function Load-ExistingDatabase {
  param([string]$Path)

  if (-not (Test-Path -LiteralPath $Path)) {
    return $null
  }

  try {
    return Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
  }
  catch {
    Write-Log "Existing database could not be read. Starting from a fresh scan."
    return $null
  }
}

function Get-RecordKey {
  param([object]$Record)

  if ($null -eq $Record) { return $null }

  $sourceFile = Clean-Text $Record.sourceFile
  $sheetName = Clean-Text $Record.sheetName
  $sourceRow = Clean-Text $Record.sourceRow

  if ($sourceFile) {
    return (($sourceFile, $sheetName, $sourceRow) -join "|").ToLowerInvariant()
  }

  $id = Clean-Text $Record.id
  if ($id) {
    return ("id|" + $id.ToLowerInvariant())
  }

  return $null
}

function Get-ZipText {
  param([object]$Zip, [string]$EntryName)
  $entry = $Zip.GetEntry($EntryName)
  if (-not $entry) { return "" }
  $stream = $entry.Open()
  try {
    $reader = New-Object System.IO.StreamReader($stream)
    try { return $reader.ReadToEnd() } finally { $reader.Dispose() }
  }
  finally {
    $stream.Dispose()
  }
}

function Get-SharedStrings {
  param([object]$Zip)
  $xmlText = Get-ZipText $Zip "xl/sharedStrings.xml"
  if (-not $xmlText) { return @() }
  $xml = New-Object xml
  $xml.LoadXml($xmlText)
  $ns = New-Object System.Xml.XmlNamespaceManager($xml.NameTable)
  $ns.AddNamespace("x", "http://schemas.openxmlformats.org/spreadsheetml/2006/main")
  $values = New-Object System.Collections.Generic.List[string]
  foreach ($si in $xml.SelectNodes("//x:si", $ns)) {
    $parts = @()
    foreach ($t in $si.SelectNodes(".//x:t", $ns)) {
      $parts += $t.InnerText
    }
    [void]$values.Add(($parts -join ""))
  }
  return $values.ToArray()
}

function Get-WorkbookFirstSheetTarget {
  param([object]$Zip)
  $workbookXmlText = Get-ZipText $Zip "xl/workbook.xml"
  if (-not $workbookXmlText) { return $null }
  $relsXmlText = Get-ZipText $Zip "xl/_rels/workbook.xml.rels"

  $rels = @{}
  if ($relsXmlText) {
    $relsXml = New-Object xml
    $relsXml.LoadXml($relsXmlText)
    foreach ($rel in $relsXml.DocumentElement.ChildNodes) {
      $id = [string]$rel.GetAttribute("Id")
      $target = [string]$rel.GetAttribute("Target")
      if ($id -and $target) { $rels[$id] = $target }
    }
  }

  $workbookXml = New-Object xml
  $workbookXml.LoadXml($workbookXmlText)
  $ns = New-Object System.Xml.XmlNamespaceManager($workbookXml.NameTable)
  $ns.AddNamespace("x", "http://schemas.openxmlformats.org/spreadsheetml/2006/main")
  $ns.AddNamespace("r", "http://schemas.openxmlformats.org/officeDocument/2006/relationships")

  $sheetNodes = $workbookXml.SelectNodes("//x:sheets/x:sheet", $ns)
  if (-not $sheetNodes -or $sheetNodes.Count -eq 0) { return $null }

  $preferredNode = $null
  $sheetNames = New-Object System.Collections.Generic.List[string]
  foreach ($sheetNode in $sheetNodes) {
    $sheetName = Clean-Text ([string]$sheetNode.GetAttribute("name"))
    [void]$sheetNames.Add($sheetName)
    $sheetKey = (Normalize-Text $sheetName) -replace "\s+", ""
    if ($sheetKey -eq "hesap1") {
      $preferredNode = $sheetNode
      break
    }
  }
  if (-not $preferredNode) {
    $preferredNode = $sheetNodes.Item(0)
  }

  $sheetName = [string]$preferredNode.GetAttribute("name")
  $rid = [string]$preferredNode.GetAttribute("id", "http://schemas.openxmlformats.org/officeDocument/2006/relationships")
  if (-not $rid -or -not $rels.ContainsKey($rid)) { return $null }

  $target = [string]$rels[$rid]
  $target = $target.TrimStart("/")
  if (-not $target.StartsWith("xl/")) {
    $target = "xl/$target"
  }

  return [ordered]@{
    sheetName = $sheetName
    target = $target
    allSheetNames = $sheetNames.ToArray()
  }
}

function Get-CellMapFromSheetText {
  param(
    [string]$SheetText,
    [string[]]$SharedStrings
  )
  $xml = New-Object xml
  $xml.LoadXml($SheetText)
  $ns = New-Object System.Xml.XmlNamespaceManager($xml.NameTable)
  $ns.AddNamespace("x", "http://schemas.openxmlformats.org/spreadsheetml/2006/main")

  $map = @{}
  foreach ($cell in $xml.SelectNodes("//x:sheetData/x:row/x:c", $ns)) {
    $ref = [string]$cell.GetAttribute("r")
    if (-not $ref) { continue }
    $type = [string]$cell.GetAttribute("t")
    $value = ""

    if ($type -eq "s") {
      $v = $cell.SelectSingleNode("x:v", $ns)
      if ($v) {
        $idx = 0
        try { $idx = [int]([string]$v.InnerText) } catch { $idx = 0 }
        if ($idx -ge 0 -and $idx -lt $SharedStrings.Count) {
          $value = $SharedStrings[$idx]
        }
      }
    }
    elseif ($type -eq "inlineStr") {
      $tNode = $cell.SelectSingleNode("x:is/x:t", $ns)
      if ($tNode) { $value = [string]$tNode.InnerText }
    }
    else {
      $v = $cell.SelectSingleNode("x:v", $ns)
      if ($v) { $value = [string]$v.InnerText }
    }

    $map[$ref] = Clean-Text $value
  }

  return $map
}

function Get-CellValue {
  param([hashtable]$Map, [string]$Ref)
  if ($Map.ContainsKey($Ref)) { return $Map[$Ref] }
  return ""
}

function Build-Highlights {
  param([hashtable]$Map)
  $targets = @("D5","D9","D10","D11","D12","O9","A15","D15","I15","C46")
  $items = New-Object System.Collections.Generic.List[object]
  foreach ($ref in $targets) {
    $value = Get-CellValue $Map $ref
    if (-not $value) { continue }
    [void]$items.Add([ordered]@{
      cell = $ref
      label = $ref
      value = $value
    })
  }
  return $items.ToArray()
}

function Build-RangeNotes {
  param([hashtable]$Map)
  $items = New-Object System.Collections.Generic.List[object]
  for ($r = 20; $r -le 45; $r++) {
    for ($c = 1; $c -le 20; $c++) {
      $ref = ([char](64 + $c)) + $r
      $value = Get-CellValue $Map $ref
      if (-not $value) { continue }
      if (Is-MeasurementLike $value) { continue }
      [void]$items.Add([ordered]@{
        cell = $ref
        label = $ref
        value = $value
      })
    }
  }
  return $items.ToArray()
}

function Build-Record {
  param(
    [string]$FileName,
    [datetime]$FileDate,
    [hashtable]$Map,
    [string]$SheetName
  )
  $customerName = Get-CustomerFromFilename $FileName
  $opt = Get-CellValue $Map "D12"
  $material = Get-CellValue $Map "A15"
  $c46 = Get-CellValue $Map "C46"
  $d15 = Get-CellValue $Map "D15"
  $i15 = Get-CellValue $Map "I15"
  $pvcMeters = Parse-PvcMeters $d15 $i15
  $orderDate = Parse-Date (Get-CellValue $Map "O9") $FileDate

  $plaka = ""
  if ($c46 -and $d15) {
    $plaka = "$c46 PLK $d15"
  } elseif ($d15) {
    $plaka = $d15
  } elseif ($c46) {
    $plaka = $c46
  } else {
    $plaka = "-"
  }

  $finalMaterial = $material
  if (-not $finalMaterial) { $finalMaterial = "-" }
  $finalColor = ""
  if ($opt) { $finalColor = $opt }
  $finalOpt = ""
  if ($opt) { $finalOpt = $opt }
  $finalQuantity = $null
  if ($c46) { $finalQuantity = Parse-Number $c46 }
  $notesText = "-"
  $highlights = Build-Highlights $Map
  $rangeNotes = Build-RangeNotes $Map

  $record = [ordered]@{
    id = ([Guid]::NewGuid().ToString("N"))
    customerName = $customerName
    material = $finalMaterial
    color = $finalColor
    pvcMeters = $pvcMeters
    quantity = $finalQuantity
    cutStatus = "Bilinmiyor"
    notes = $notesText
    cellHighlights = $highlights
    rangeNotes = $rangeNotes
    orderDate = $orderDate
    sourceFile = $FileName
    sheetName = $SheetName
    sourceRow = 1
    opt = $finalOpt
    plaka = $plaka
  }
  return $record
}

$startTime = Get-Date
Write-Log "Start: last 1 month scan from $SourcePath"
$existingDatabase = Load-ExistingDatabase -Path $databasePath
$mergedRecords = New-Object System.Collections.Generic.List[object]
$recordIndexByKey = @{}
$existingRecordCount = 0
$updatedRecords = 0
$addedRecords = 0

if ($existingDatabase -and $existingDatabase.records) {
  $existingRecords = @($existingDatabase.records)
  $existingRecordCount = $existingRecords.Count
  foreach ($existingRecord in $existingRecords) {
    $existingRecord = Repair-ExistingRecord $existingRecord
    $existingKey = Get-RecordKey $existingRecord
    if (-not $existingKey) {
      $existingKey = "id|" + ([Guid]::NewGuid().ToString("N"))
    }

    if ($recordIndexByKey.ContainsKey($existingKey)) {
      $mergedRecords[$recordIndexByKey[$existingKey]] = $existingRecord
      continue
    }

    $recordIndexByKey[$existingKey] = $mergedRecords.Count
    [void]$mergedRecords.Add($existingRecord)
  }
  Write-Log "Existing database loaded: $existingRecordCount records."
}
else {
  Write-Log "No existing database found. Starting from scratch."
}

$seenSourceKeys = New-Object 'System.Collections.Generic.HashSet[string]'
$skippedDuplicates = 0
$processedFiles = 0

try {
  if (-not (Test-Path -LiteralPath $SourcePath)) {
    Write-Log "Source folder not found: $SourcePath. Continuing with the existing database only."
  }
  else {
    $files = Get-ChildItem -LiteralPath $SourcePath -Recurse -File | Where-Object {
      $_.Extension -eq ".xlsm" -and $_.LastWriteTime -ge $cutoff
    } | Sort-Object LastWriteTime -Descending
    Write-Log "Files found: $($files.Count)"

    foreach ($file in $files) {
      $sourceKey = Get-SourceKey $file.Name
      if ($sourceKey -and $seenSourceKeys.Contains($sourceKey)) {
        $skippedDuplicates++
        Write-Log "Skipping duplicate source key: $sourceKey ($($file.FullName))"
        continue
      }
      if ($sourceKey) {
        [void]$seenSourceKeys.Add($sourceKey)
      }

      $processedFiles++
      Write-Log "Reading file: $($file.FullName)"
      try {
        $zip = [System.IO.Compression.ZipFile]::OpenRead($file.FullName)
        try {
          Write-Log "Stage: shared strings"
          $sharedStrings = Get-SharedStrings $zip
          Write-Log "Stage: workbook"
          $firstSheet = Get-WorkbookFirstSheetTarget $zip
          if (-not $firstSheet) {
            Write-Log "Failed file: $($file.FullName)"
            Write-Log "Error: workbook sheet bulunamadi"
            continue
          }
          if ($firstSheet.allSheetNames) {
            Write-Log ("Sheets: {0}" -f (($firstSheet.allSheetNames) -join " | "))
          }
          Write-Log ("Sheet selected: {0}" -f $firstSheet.sheetName)

          Write-Log "Stage: sheet xml"
          $sheetText = Get-ZipText $zip $firstSheet.target
          if (-not $sheetText) {
            Write-Log "Failed file: $($file.FullName)"
            Write-Log "Error: sheet xml okunamadi"
            continue
          }

          Write-Log "Stage: cell map"
          $map = Get-CellMapFromSheetText -SheetText $sheetText -SharedStrings $sharedStrings
          Write-Log "Stage: record"
          $record = Build-Record -FileName $file.Name -FileDate $file.LastWriteTime -Map $map -SheetName $firstSheet.sheetName
          $recordKey = Get-RecordKey $record
          if ($recordKey -and $recordIndexByKey.ContainsKey($recordKey)) {
            $existingRecord = $mergedRecords[$recordIndexByKey[$recordKey]]
            if ($existingRecord -and $existingRecord.id) {
              $record.id = $existingRecord.id
            }
            $mergedRecords[$recordIndexByKey[$recordKey]] = $record
            $updatedRecords++
            Write-Log "File done: $($file.FullName) (updated existing record)"
          }
          else {
            if (-not $recordKey) {
              $recordKey = "fallback|" + ([Guid]::NewGuid().ToString("N"))
            }
            $recordIndexByKey[$recordKey] = $mergedRecords.Count
            [void]$mergedRecords.Add($record)
            $addedRecords++
            Write-Log "File done: $($file.FullName) (new record)"
          }
        }
        finally {
          $zip.Dispose()
        }
      }
      catch {
        Write-Log "Failed file: $($file.FullName)"
        Write-Log ("Error: {0}" -f $_.Exception.Message)
      }
    }
  }
}
catch {
  Write-Log "Source scan could not be completed. Continuing with the existing database only."
  Write-Log ("Source scan error: {0}" -f $_.Exception.Message)
}

$database = [ordered]@{
  generatedAt = (Get-Date).ToString("o")
  cutoffDate = $cutoff.ToString("o")
  totalRecords = $mergedRecords.Count
  totalFiles = $processedFiles
  skippedDuplicates = $skippedDuplicates
  existingRecords = $existingRecordCount
  addedRecords = $addedRecords
  updatedRecords = $updatedRecords
  records = $mergedRecords
}

if (-not (Test-Path -LiteralPath $dataDir)) {
  New-Item -ItemType Directory -Path $dataDir -Force | Out-Null
}

$databaseJson = $database | ConvertTo-Json -Depth 10
$databaseJson | Set-Content -LiteralPath $databasePath -Encoding utf8
$databaseJsLiteral = $databaseJson | ConvertTo-Json -Compress
("window.LOCAL_DATABASE_TEXT = " + $databaseJsLiteral + ";") | Set-Content -LiteralPath $localDatabaseJsPath -Encoding utf8
Write-Log "database.txt updated: $databasePath"
Write-Log "local-database.js updated: $localDatabaseJsPath"
Save-State -ProcessedKeys @($seenSourceKeys) -LastRunAt (Get-Date).ToString("o")
Write-Log "sync-state.json updated: $statePath"
Write-Log "Last 1 month: $($files.Count) files, $processedFiles processed, $skippedDuplicates duplicates skipped, $addedRecords new records, $updatedRecords updated records, $($mergedRecords.Count) total records."
Write-Log ("Done in {0:n1} sec" -f ((Get-Date) - $startTime).TotalSeconds)

Write-Log "Preparing Supabase export..."
try {
  & (Join-Path $PSScriptRoot "export-for-supabase.ps1") -DatabasePath $databasePath
  Write-Log "Supabase export completed."
}
catch {
  Write-Log ("Supabase export failed: {0}" -f $_.Exception.Message)
}

Write-Log "Preparing Supabase upload..."
try {
  & (Join-Path $PSScriptRoot "push-to-supabase.ps1") -DatabasePath $databasePath
  Write-Log "Supabase upload completed."
}
catch {
  Write-Log ("Supabase upload failed: {0}" -f $_.Exception.Message)
}

Start-Sleep -Seconds 3
