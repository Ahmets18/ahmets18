param(
  [string]$SiteUrl = "http://artiebatlama.com",
  [string]$XmlRpcUrl = "http://artiebatlama.com/xmlrpc.php",
  [string]$Username,
  [string]$Password,
  [int]$PageId = 479,
  [string]$LocalAppPath = (Join-Path (Get-Location) "deploy-kesimsorgu-live.html"),
  [string]$LocalDatabasePath = (Join-Path (Get-Location) "private\database.json")
)

$ErrorActionPreference = "Stop"

if (-not $Username) { throw "Username gerekli." }
if (-not $Password) { throw "Password gerekli." }
if (-not (Test-Path -LiteralPath $LocalAppPath)) { throw "App dosyasi bulunamadi: $LocalAppPath" }
if (-not (Test-Path -LiteralPath $LocalDatabasePath)) { throw "Veritabani dosyasi bulunamadi: $LocalDatabasePath" }

function Escape-XmlText {
  param([string]$Value)
  if ($null -eq $Value) { return "" }
  return [System.Security.SecurityElement]::Escape($Value)
}

function Invoke-XmlRpc {
  param([string]$MethodName, [string]$InnerXml)

  $body = @"
<?xml version="1.0" encoding="UTF-8"?>
<methodCall>
  <methodName>$MethodName</methodName>
  <params>
$InnerXml
  </params>
</methodCall>
"@

  $curl = Get-Command curl.exe -ErrorAction Stop
  $tempFile = Join-Path $env:TEMP ("kesim-xmlrpc-" + [guid]::NewGuid().ToString("N") + ".xml")
  [System.IO.File]::WriteAllText($tempFile, $body, (New-Object System.Text.UTF8Encoding($false)))
  try {
    $response = & $curl.Source `
      --silent `
      --show-error `
      --fail `
      -H "X-Forwarded-Proto: https" `
      -H "Content-Type: text/xml; charset=UTF-8" `
      --data-binary "@$tempFile" `
      $XmlRpcUrl

    if ($LASTEXITCODE -ne 0) {
      throw "XML-RPC istegi basarisiz oldu: $MethodName"
    }

    return [string]$response
  }
  finally {
    Remove-Item -LiteralPath $tempFile -Force -ErrorAction SilentlyContinue
  }
}

function New-XmlRpcStringParam {
  param([string]$Value)
  return "    <param><value><string>$(Escape-XmlText $Value)</string></value></param>`n"
}

function New-XmlRpcIntParam {
  param([int]$Value)
  return "    <param><value><int>$Value</int></value></param>`n"
}

function New-XmlRpcStructMember {
  param([string]$Name, [string]$Value, [string]$Type = "string")
  if ($Type -eq "base64") {
    return @"
      <member>
        <name>$Name</name>
        <value><base64>$Value</base64></value>
      </member>
"@
  }

  if ($Type -eq "boolean") {
    return @"
      <member>
        <name>$Name</name>
        <value><boolean>$Value</boolean></value>
      </member>
"@
  }

  return @"
      <member>
        <name>$Name</name>
        <value><string>$(Escape-XmlText $Value)</string></value>
      </member>
"@
}

function Invoke-WordPressUpload {
  param(
    [string]$LocalPath,
    [string]$RemoteName,
    [string]$MimeType
  )

  $bytes = [System.IO.File]::ReadAllBytes($LocalPath)
  $base64 = [Convert]::ToBase64String($bytes)

  $struct = @(
    (New-XmlRpcStructMember -Name "name" -Value $RemoteName),
    (New-XmlRpcStructMember -Name "type" -Value $MimeType),
    (New-XmlRpcStructMember -Name "bits" -Value $base64 -Type "base64"),
    (New-XmlRpcStructMember -Name "overwrite" -Value "0" -Type "boolean")
  ) -join ""

  $inner = @"
$((New-XmlRpcIntParam -Value 0).TrimEnd())
$((New-XmlRpcStringParam -Value $Username).TrimEnd())
$((New-XmlRpcStringParam -Value $Password).TrimEnd())
    <param>
      <value>
        <struct>
$struct
        </struct>
      </value>
    </param>
"@

  $xml = Invoke-XmlRpc -MethodName "wp.uploadFile" -InnerXml $inner
  if ($xml -notmatch '<name>url</name>\s*<value><string>(.*?)</string></value>') {
    throw "Dosya yukleme yaniti URL icermiyor: $RemoteName"
  }

  return [System.Net.WebUtility]::HtmlDecode($Matches[1])
}

function Invoke-WordPressEditPage {
  param(
    [int]$PostId,
    [string]$Title,
    [string]$Html
  )

  $inner = @"
$((New-XmlRpcIntParam -Value $PostId).TrimEnd())
$((New-XmlRpcStringParam -Value $Username).TrimEnd())
$((New-XmlRpcStringParam -Value $Password).TrimEnd())
    <param>
      <value>
        <struct>
$(New-XmlRpcStructMember -Name "post_type" -Value "page")
$(New-XmlRpcStructMember -Name "post_status" -Value "publish")
$(New-XmlRpcStructMember -Name "page_status" -Value "publish")
$(New-XmlRpcStructMember -Name "post_title" -Value $Title)
$(New-XmlRpcStructMember -Name "post_content" -Value $Html)
        </struct>
      </value>
    </param>
"@

  [void](Invoke-XmlRpc -MethodName "wp.editPage" -InnerXml $inner)
}

function Invoke-WordPressLogin {
  param(
    [string]$EditUrl
  )

  $curl = Get-Command curl.exe -ErrorAction Stop
  $loginUrl = "$SiteUrl/wp-login.php"
  $headers = & $curl.Source `
    --silent `
    --show-error `
    --fail `
    -L `
    -H "X-Forwarded-Proto: https" `
    -D - `
    -o NUL `
    --data-urlencode "log=$Username" `
    --data-urlencode "pwd=$Password" `
    --data-urlencode "wp-submit=Log In" `
    --data-urlencode "redirect_to=$EditUrl" `
    --data-urlencode "testcookie=1" `
    $loginUrl

  if ($LASTEXITCODE -ne 0) {
    throw "WordPress girişi başarısız oldu."
  }

  $cookies = @{}
  foreach ($line in $headers) {
    $text = [string]$line
    if ($text -match '^set-cookie:\s*([^=]+)=([^;]+);') {
      $name = $Matches[1].Trim()
      $value = $Matches[2].Trim()
      if ($name -and $value) {
        $cookies[$name] = $value
      }
    }
  }

  if (-not $cookies.Count) {
    throw "WordPress çerezleri alınamadı."
  }

  return ($cookies.GetEnumerator() | Sort-Object Name | ForEach-Object { "$($_.Name)=$($_.Value)" }) -join '; '
}

function Get-WordPressRestNonce {
  param(
    [string]$CookieHeader
  )

  $curl = Get-Command curl.exe -ErrorAction Stop
  $nonceUrl = "$SiteUrl/wp-admin/admin-ajax.php?action=rest-nonce"
  $nonce = & $curl.Source `
    --silent `
    --show-error `
    --fail `
    -H "Cookie: $CookieHeader" `
    -H "X-Forwarded-Proto: https" `
    $nonceUrl

  if ($LASTEXITCODE -ne 0) {
    throw "REST nonce alınamadı."
  }

  $value = ([string]$nonce).Trim()
  if (-not $value) {
    throw "REST nonce boş geldi."
  }

  return $value
}

function Invoke-WordPressRestPublish {
  param(
    [string]$CookieHeader,
    [int]$PostId,
    [string]$Title,
    [string]$Html
  )

  $nonce = Get-WordPressRestNonce -CookieHeader $CookieHeader
  $curl = Get-Command curl.exe -ErrorAction Stop
  $body = @{
    id = $PostId
    title = $Title
    content = $Html
    slug = "kesimsorgu"
    status = "publish"
  } | ConvertTo-Json -Depth 10 -Compress

  $bodyFile = Join-Path $env:TEMP ("kesim-rest-" + [guid]::NewGuid().ToString("N") + ".json")
  [System.IO.File]::WriteAllText($bodyFile, $body, (New-Object System.Text.UTF8Encoding($false)))
  try {
    $response = & $curl.Source `
      --silent `
      --show-error `
      --fail `
      -X POST `
      -H "Cookie: $CookieHeader" `
      -H "X-Forwarded-Proto: https" `
      -H "X-WP-Nonce: $nonce" `
      -H "Content-Type: application/json; charset=UTF-8" `
      --data-binary "@$bodyFile" `
      "$SiteUrl/wp-json/wp/v2/pages/$PostId"

    if ($LASTEXITCODE -ne 0) {
      throw "REST yayinlama istegi basarisiz oldu."
    }

    $responseText = [string]$response
    if ($responseText -notmatch '"status"\s*:\s*"publish"') {
      throw "REST yanitinda publish onayi yok."
    }

    return $responseText
  }
  finally {
    Remove-Item -LiteralPath $bodyFile -Force -ErrorAction SilentlyContinue
  }
}

$version = Get-Date -Format "yyyyMMddHHmmss"
$appRemoteName = "kesimsorgu-app-$version.html"
$dataRemoteName = "kesim-data-$version.json"
Write-Host "App yukleniyor: $appRemoteName"
$appUrl = Invoke-WordPressUpload -LocalPath $LocalAppPath -RemoteName $appRemoteName -MimeType "text/html"
Write-Host "Veri yukleniyor: $dataRemoteName"
$dataUrl = Invoke-WordPressUpload -LocalPath $LocalDatabasePath -RemoteName $dataRemoteName -MimeType "application/json"

$iframeHtml = @"
<style>
body.page-id-$PageId .entry-title,
body.page-id-$PageId .wp-block-post-title,
body.page-id-$PageId .page-title,
body.page-id-$PageId .post-title{
  display:none !important;
}
body.page-id-$PageId{
  overflow-x:hidden !important;
}
body.page-id-$PageId #page,
body.page-id-$PageId .site,
body.page-id-$PageId .elementor,
body.page-id-$PageId .entry-content{
  max-width:100vw !important;
  overflow-x:hidden !important;
}
body.page-id-$PageId .entry-content,
body.page-id-$PageId .wp-site-blocks,
body.page-id-$PageId .site-main{
  margin-top:0 !important;
  padding-top:0 !important;
}
body.page-id-$PageId .page-content{
  padding:0 !important;
}
body.page-id-$PageId footer#colophon .siparis-formu,
body.page-id-$PageId footer#colophon .elementor-element-429935b,
body.page-id-$PageId .entry-content form,
body.page-id-$PageId .page-content form,
body.page-id-$PageId footer#colophon form,
body.page-id-$PageId .site-footer form{
  display:none !important;
}
body.page-id-$PageId .kesimsorgu-frame-wrap{
  width:100vw;
  max-width:100vw;
  margin-left:calc(50% - 50vw);
  padding:70px 0 0;
  position:relative;
  z-index:2;
  background:linear-gradient(180deg,#f7f3ec 0%, #f0e8dc 100%);
  overflow-x:hidden;
}
body.page-id-$PageId .kesimsorgu-frame-wrap iframe{
  width:100vw !important;
  max-width:100vw !important;
}
</style>
<div class="kesimsorgu-frame-wrap">
  <iframe id="kesimsorguFrame" src="${appUrl}?data=${dataUrl}" title="Kesim Sorgulama" style="width:100%;height:1800px;min-height:1800px;border:0;display:block;background:#fff;" loading="lazy" scrolling="no"></iframe>
</div>
<script>
(function(){
  var frame = document.getElementById('kesimsorguFrame');
  if (!frame) return;

  var minHeight = 1800;
  var maxHeight = 6000;
  var timer = null;
  var polling = null;

  function applyHeight(value) {
    var next = parseInt(value, 10);
    if (!Number.isFinite(next) || next < minHeight) {
      next = minHeight;
    }
    if (next > maxHeight) {
      next = maxHeight;
    }
    frame.style.height = next + 'px';
    frame.style.minHeight = minHeight + 'px';
  }

  function readHeight() {
    try {
      var doc = frame.contentDocument || frame.contentWindow.document;
      if (!doc) return;
      var body = doc.body;
      var root = doc.documentElement;
      var measured = Math.max(
        body ? body.scrollHeight : 0,
        root ? root.scrollHeight : 0,
        body ? body.offsetHeight : 0,
        root ? root.offsetHeight : 0
      );
      if (measured) {
        applyHeight(measured);
      }
    } catch (error) {
      // Same-origin access may fail if the iframe moves; keep the fallback height.
    }
  }

  function schedule() {
    clearTimeout(timer);
    timer = setTimeout(readHeight, 60);
  }

  frame.addEventListener('load', function() {
    applyHeight(minHeight);
    schedule();
    setTimeout(schedule, 400);
    setTimeout(schedule, 1200);
  });

  window.addEventListener('resize', schedule);
  window.addEventListener('message', function(event) {
    var data = event && event.data;
    if (!data || data.type !== 'kesim:auto-height') return;
    applyHeight(data.height);
  });
  polling = setInterval(schedule, 1000);
  window.addEventListener('beforeunload', function() {
    if (polling) {
      clearInterval(polling);
    }
  });

  applyHeight(minHeight);
  schedule();
})();
</script>
"@

Write-Host "Sayfa guncelleniyor: $PageId"
Invoke-WordPressEditPage -PostId $PageId -Title "Kesim Sorgulama" -Html $iframeHtml

try {
  Write-Host "WordPress oturum açılıyor"
  $cookieHeader = Invoke-WordPressLogin -EditUrl "$SiteUrl/wp-admin/post.php?post=$PageId&action=edit"

  Write-Host "Sayfa REST ile yayina aliniyor"
  [void](Invoke-WordPressRestPublish -CookieHeader $cookieHeader -PostId $PageId -Title "Kesim Sorgulama" -Html $iframeHtml)
}
catch {
  throw
}

Write-Host "Yayinlandi"
Write-Host "APP=$appUrl"
Write-Host "DATA=$dataUrl"
Write-Host "PAGE=$SiteUrl/kesimsorgu/"
