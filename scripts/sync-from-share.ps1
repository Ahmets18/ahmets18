param(
  [string]$SourcePath = ("\\ARTI\Schelling\YEDEK L" + [char]0x0130 + "STELER")
)

$ErrorActionPreference = "Stop"
$rootDir = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$dataDir = Join-Path $rootDir "data"
$logDir = Join-Path $rootDir "logs"
$scriptsDir = Join-Path $rootDir "scripts"
$exportsDir = Join-Path $rootDir "exports"
$secretsPath = Join-Path $rootDir "secrets/supabase.local.json"
$databasePath = Join-Path $dataDir "database.txt"
$syncStatePath = Join-Path $dataDir "sync-state.json"
$localDatabaseJsPath = Join-Path $rootDir "local-database.js"
$exportScriptPath = Join-Path $scriptsDir "export-for-supabase.ps1"
$pushScriptPath = Join-Path $scriptsDir "push-to-supabase.ps1"
$publishScriptPath = Join-Path $scriptsDir "publish-live-data.ps1"
$logPath = Join-Path $logDir "sync.log"
$cutoff = (Get-Date).AddMonths(-1)
$fileTimeoutSeconds = 20
$cutDataRoot = "\\Schelling01\d\Schelling\SchellingData\NCData"
$script:CutStatusIndex = $null

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

function Is-MeasurementLike {
  param([string]$Value)
  if ([string]::IsNullOrWhiteSpace($Value)) { return $false }
  $matchesNumber = $Value -match '^\d+(\.\d+)?$'
  $matchesSize = $Value -match '^\d+[xX]\d+$'
  $matchesPlate = $Value -match '^\d+M\s+\d+[xX]\d+$'
  $matchesMm = $Value -match '^\d+MM$'
  return ($matchesNumber -or $matchesSize -or $matchesPlate -or $matchesMm)
}

function Is-MeaningfulNoteValue {
  param([object]$Value)
  $text = Clean-Text $Value
  if (-not $text) { return $false }
  if ($text -eq "-") { return $false }
  if (Is-MeasurementLike $text) { return $false }
  if ($text -match '^[xX]$') { return $false }
  if ($text -match '^\d+\*?$') { return $false }
  $letters = ($text -replace '[^A-Za-zÇĞİÖŞÜçğıöşü]', '')
  return ($letters.Length -ge 2)
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

function Get-SourceKeyFromName {
  param([string]$Name)
  $baseName = Clean-Text ([IO.Path]::GetFileNameWithoutExtension($Name))
  if ($baseName -match '(?i)\b([A-Z]\d{3})\b') {
    return $Matches[1].ToUpperInvariant()
  }
  if ($baseName -match '(?i)([A-Z]\d{3})') {
    return $Matches[1].ToUpperInvariant()
  }
  return $baseName.ToUpperInvariant()
}

function Get-CutStatusIndex {
  if ($script:CutStatusIndex) {
    return $script:CutStatusIndex
  }

  $byCode = @{}
  $rootAvailable = $false

  try {
    $rootAvailable = Test-Path -LiteralPath $cutDataRoot
    if ($rootAvailable) {
      foreach ($folder in Get-ChildItem -LiteralPath $cutDataRoot -Directory -Filter "*.l" -ErrorAction Stop) {
        $code = Get-SourceKeyFromName $folder.Name
        if (-not $code) { continue }

        $doneFile = Join-Path $folder.FullName "0000.ipz"
        $isDone = Test-Path -LiteralPath $doneFile
        if (-not $byCode.ContainsKey($code) -or $isDone) {
          $byCode[$code] = $isDone
        }
      }
    }
  }
  catch {
    $rootAvailable = $false
  }

  $script:CutStatusIndex = [ordered]@{
    rootAvailable = $rootAvailable
    byCode = $byCode
  }

  return $script:CutStatusIndex
}

function Get-CutStatusByCode {
  param([string]$JobCode)
  $jobCode = Clean-Text $JobCode
  if (-not $jobCode) {
    return "Bilinmiyor"
  }

  $sourceKey = Get-SourceKeyFromName $jobCode
  $index = Get-CutStatusIndex
  if (-not $index.rootAvailable) {
    return "Bilinmiyor"
  }

  if ($sourceKey -and $index.byCode.ContainsKey($sourceKey)) {
    if ($index.byCode[$sourceKey]) {
      return "Kesildi"
    }
    return "Kesilmedi"
  }

  $cutFilePath = Join-Path $cutDataRoot "$jobCode.l\0000.ipz"
  try {
    if (Test-Path -LiteralPath $cutFilePath) {
      return "Kesildi"
    }
    return "Kesilmedi"
  }
  catch {
    return "Bilinmiyor"
  }
}

function Get-CutStatus {
  param([hashtable]$Map)
  return Get-CutStatusByCode (Get-CellValue $Map "D5")
}

function Get-RecordJobCode {
  param([object]$Record)

  if ($null -eq $Record) { return "" }

  foreach ($propertyName in @("jobCode", "d5")) {
    if ($Record -is [System.Collections.IDictionary] -and $Record.Contains($propertyName)) {
      $value = Clean-Text $Record[$propertyName]
      if ($value) { return $value }
    }

    $property = $Record.PSObject.Properties[$propertyName]
    if ($property) {
      $value = Clean-Text $property.Value
      if ($value) { return $value }
    }
  }

  return Get-SourceKeyFromName ([string]$Record.sourceFile)
}

function Set-RecordProperty {
  param(
    [object]$Record,
    [string]$Name,
    [object]$Value
  )

  if ($null -eq $Record) { return }

  if ($Record -is [System.Collections.IDictionary]) {
    $Record[$Name] = $Value
    return
  }

  $property = $Record.PSObject.Properties[$Name]
  if ($property) {
    $property.Value = $Value
  } else {
    Add-Member -InputObject $Record -NotePropertyName $Name -NotePropertyValue $Value -Force
  }
}

function Update-RecordCutStatuses {
  param([object[]]$Records)

  $checked = 0
  $changed = 0
  $unknown = 0

  foreach ($record in @($Records)) {
    if ($null -eq $record) { continue }

    $jobCode = Get-RecordJobCode $record
    if (-not $jobCode) {
      $unknown++
      Set-RecordProperty -Record $record -Name "cutStatus" -Value "Bilinmiyor"
      continue
    }

    $oldStatus = ""
    if ($record -is [System.Collections.IDictionary] -and $record.Contains("cutStatus")) {
      $oldStatus = Clean-Text $record["cutStatus"]
    } else {
      $oldStatusProperty = $record.PSObject.Properties["cutStatus"]
      if ($oldStatusProperty) {
        $oldStatus = Clean-Text $oldStatusProperty.Value
      }
    }
    $newStatus = Get-CutStatusByCode $jobCode
    if ($newStatus -eq "Bilinmiyor") { $unknown++ }
    if ($oldStatus -ne $newStatus) { $changed++ }

    Set-RecordProperty -Record $record -Name "jobCode" -Value $jobCode
    Set-RecordProperty -Record $record -Name "d5" -Value $jobCode
    Set-RecordProperty -Record $record -Name "cutStatus" -Value $newStatus
    $checked++
  }

  return [ordered]@{
    checked = $checked
    changed = $changed
    unknown = $unknown
  }
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
      if (-not (Is-MeaningfulNoteValue $value)) { continue }
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
  $pvcMeters = Parse-Number (Get-CellValue $Map "C53")
  $orderDate = Parse-Date (Get-CellValue $Map "O9") $FileDate
  $jobCode = Clean-Text (Get-CellValue $Map "D5")

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
  $highlights = @()
  $rangeNotes = Build-RangeNotes $Map
  $cutStatus = "Bilinmiyor"

  $record = [ordered]@{
    id = ([Guid]::NewGuid().ToString("N"))
    customerName = $customerName
    jobCode = $jobCode
    d5 = $jobCode
    material = $finalMaterial
    color = $finalColor
    pvcMeters = $pvcMeters
    quantity = $finalQuantity
    cutStatus = $cutStatus
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

function Get-WorkerScriptText {
  param([string[]]$FunctionNames)

  $definitionText = New-Object System.Collections.Generic.List[string]
  foreach ($name in $FunctionNames) {
    $command = Get-Command -Name $name -CommandType Function
    [void]$definitionText.Add(("function {0} {{`n{1}`n}}" -f $name, $command.Definition))
  }

  $scriptHeader = @'
param(
  [string]$FilePath
)

if (-not ("System.IO.Compression.ZipFile" -as [type])) {
  Add-Type -AssemblyName System.IO.Compression.FileSystem
}
'@

  $scriptBody = @'
if (-not (Test-Path -LiteralPath $FilePath)) {
  throw "File not found: $FilePath"
}

$zip = [System.IO.Compression.ZipFile]::OpenRead($FilePath)
try {
  $sharedStrings = Get-SharedStrings $zip
  $firstSheet = Get-WorkbookFirstSheetTarget $zip
  if (-not $firstSheet) {
    throw "workbook sheet bulunamadi"
  }

  $sheetText = Get-ZipText $zip $firstSheet.target
  if (-not $sheetText) {
    throw "sheet xml okunamadi"
  }

  $map = Get-CellMapFromSheetText -SheetText $sheetText -SharedStrings $sharedStrings
  $file = Get-Item -LiteralPath $FilePath
  return Build-Record -FileName $file.Name -FileDate $file.LastWriteTime -Map $map -SheetName $firstSheet.sheetName
}
finally {
  $zip.Dispose()
}
'@

  return ($scriptHeader + "`n`n" + ($definitionText -join "`n`n") + "`n`n" + $scriptBody)
}

$workerScriptText = Get-WorkerScriptText -FunctionNames @(
  "Clean-Text",
  "Normalize-Text",
  "Parse-Number",
  "Parse-Date",
  "Is-MeasurementLike",
  "Is-MeaningfulNoteValue",
  "Get-CustomerFromFilename",
  "Get-ZipText",
  "Get-SharedStrings",
  "Get-WorkbookFirstSheetTarget",
  "Get-CellMapFromSheetText",
  "Get-CellValue",
  "Get-SourceKeyFromName",
  "Get-CutStatusByCode",
  "Get-CutStatus",
  "Build-Highlights",
  "Build-RangeNotes",
  "Build-Record"
)

function Invoke-FileRecordWithTimeout {
  param(
    [string]$FilePath,
    [int]$TimeoutSeconds = 20
  )

  $ps = [System.Management.Automation.PowerShell]::Create()
  try {
    [void]$ps.AddScript($workerScriptText).AddArgument($FilePath)
    $asyncResult = $ps.BeginInvoke()

    if (-not $asyncResult.AsyncWaitHandle.WaitOne([TimeSpan]::FromSeconds($TimeoutSeconds))) {
      try { $ps.Stop() } catch {}
      return [ordered]@{
        timedOut = $true
        success = $false
        record = $null
        error = "Processing exceeded $TimeoutSeconds seconds."
      }
    }

    $result = $ps.EndInvoke($asyncResult)
    if ($ps.Streams.Error.Count -gt 0) {
      $message = ($ps.Streams.Error | Select-Object -First 1).Exception.Message
      return [ordered]@{
        timedOut = $false
        success = $false
        record = $null
        error = $message
      }
    }

    $record = $null
    if ($null -ne $result -and $result.Count -gt 0) {
      $record = $result[0]
    }

    return [ordered]@{
      timedOut = $false
      success = $true
      record = $record
      error = $null
    }
  }
  catch {
    return [ordered]@{
      timedOut = $false
      success = $false
      record = $null
      error = $_.Exception.Message
    }
  }
  finally {
    $ps.Dispose()
  }
}

if (-not (Test-Path -LiteralPath $SourcePath)) {
  throw "Source folder not found: $SourcePath"
}

$startTime = Get-Date
Write-Log "Start: last 1 month scan from $SourcePath"

$files = Get-ChildItem -LiteralPath $SourcePath -Recurse -File | Where-Object {
  $_.Extension -eq ".xlsm" -and $_.LastWriteTime -ge $cutoff
}
Write-Log "Files found: $($files.Count)"

$records = New-Object System.Collections.Generic.List[object]
$processedKeys = @{}
$existingRecordCount = 0

if (Test-Path -LiteralPath $databasePath) {
  try {
    $existingDatabase = Get-Content -LiteralPath $databasePath -Raw | ConvertFrom-Json
    foreach ($record in @($existingDatabase.records)) {
      if ($null -eq $record) { continue }
      $sourceKey = Get-SourceKeyFromName ([string]$record.sourceFile)
      if (-not $sourceKey -or $processedKeys.ContainsKey($sourceKey)) { continue }

      [void]$records.Add($record)
      $processedKeys[$sourceKey] = $true
      $existingRecordCount++
    }
    Write-Log "Existing database loaded: $existingRecordCount records."
  }
  catch {
    Write-Log ("Existing database could not be read, starting fresh: {0}" -f $_.Exception.Message)
  }
}

$processed = 0
$skippedCached = 0
$newRecords = 0
$failedFiles = 0
$timedOutFiles = 0
foreach ($file in $files) {
  $sourceKey = Get-SourceKeyFromName $file.Name
  if ($sourceKey -and $processedKeys.ContainsKey($sourceKey)) {
    $skippedCached++
    Write-Log "Skipping cached source key: $sourceKey ($($file.FullName))"
    continue
  }

  Write-Log "Reading file: $($file.FullName)"
  $fileResult = Invoke-FileRecordWithTimeout -FilePath $file.FullName -TimeoutSeconds $fileTimeoutSeconds
  if ($fileResult.timedOut) {
    $timedOutFiles++
    Write-Log "Skipped file after $fileTimeoutSeconds seconds: $($file.FullName)"
    continue
  }

  if (-not $fileResult.success) {
    $failedFiles++
    Write-Log "Failed file: $($file.FullName)"
    Write-Log ("Error: {0}" -f $fileResult.error)
    continue
  }

  [void]$records.Add($fileResult.record)
  if ($sourceKey) {
    $processedKeys[$sourceKey] = $true
  }
  $processed++
  $newRecords++
  Write-Log "File done: $($file.FullName) (new record)"
}

$cutStatusRefresh = Update-RecordCutStatuses -Records $records.ToArray()
Write-Log "Cut status refreshed: $($cutStatusRefresh.checked) records checked, $($cutStatusRefresh.changed) changed, $($cutStatusRefresh.unknown) unknown."

$database = [ordered]@{
  generatedAt = (Get-Date).ToString("o")
  cutoffDate = $cutoff.ToString("o")
  totalRecords = $records.Count
  totalFiles = $files.Count
  records = $records
}

if (-not (Test-Path -LiteralPath $dataDir)) {
  New-Item -ItemType Directory -Path $dataDir -Force | Out-Null
}

$databaseJson = $database | ConvertTo-Json -Depth 10
$databaseJson | Set-Content -LiteralPath $databasePath -Encoding utf8
$databaseEncoded = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($databaseJson))
("window.LOCAL_DATABASE_TEXT = atob('" + $databaseEncoded + "');") | Set-Content -LiteralPath $localDatabaseJsPath -Encoding utf8
$syncState = [ordered]@{
  processedKeys = @($processedKeys.Keys | Sort-Object)
  lastRunAt = $database.generatedAt
  totalRecords = $records.Count
  totalFilesSeen = $files.Count
}
$syncState | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $syncStatePath -Encoding utf8
Write-Log "database.txt updated: $databasePath"
Write-Log "local-database.js updated: $localDatabaseJsPath"
Write-Log "sync-state.json updated: $syncStatePath"
Write-Log "Last 1 month: $($files.Count) files, $processed processed, $skippedCached cached skipped, $newRecords new records, $timedOutFiles timed out, $failedFiles failed, $($records.Count) total records."

try {
  if (Test-Path -LiteralPath $exportScriptPath) {
    Write-Log "Preparing Supabase export..."
    & $exportScriptPath -DatabasePath $databasePath -OutputDir $exportsDir
    Write-Log "Supabase export ready."
  } else {
    Write-Log "Supabase export skipped: script not found at $exportScriptPath"
  }
}
catch {
  Write-Log ("Supabase export failed: {0}" -f $_.Exception.Message)
}

$uploadSucceeded = $false
try {
  if (Test-Path -LiteralPath $pushScriptPath) {
    Write-Log "Preparing Supabase upload..."
    & $pushScriptPath -DatabasePath $databasePath -SecretsPath $secretsPath
    Write-Log "Supabase upload finished."
    $uploadSucceeded = $true
  } else {
    Write-Log "Supabase upload skipped: script not found at $pushScriptPath"
  }
}
catch {
  Write-Log ("Supabase upload failed: {0}" -f $_.Exception.Message)
}

try {
  if ($uploadSucceeded -and (Test-Path -LiteralPath $publishScriptPath)) {
    Write-Log "Preparing live data publish..."
    & $publishScriptPath -RootDir $rootDir -DatabasePath $databasePath
    Write-Log "Live data publish finished."
  } elseif (-not $uploadSucceeded) {
    Write-Log "Live data publish skipped: Supabase upload did not finish."
  } else {
    Write-Log "Live data publish skipped: script not found at $publishScriptPath"
  }
}
catch {
  Write-Log ("Live data publish failed: {0}" -f $_.Exception.Message)
}

Write-Log ("Done in {0:n1} sec" -f ((Get-Date) - $startTime).TotalSeconds)
