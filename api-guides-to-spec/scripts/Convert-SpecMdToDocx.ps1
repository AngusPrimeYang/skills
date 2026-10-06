<#
.SYNOPSIS
  Convert a marker-based API Spec Markdown file to OOXML .docx (no Word COM).

.PARAMETER MdPath
  Path to Spec .md (UTF-16 LE BOM or UTF-8 with/without BOM; detected from BOM).

.PARAMETER OutDocx
  Output .docx path.
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)][string]$MdPath,
  [Parameter(Mandatory = $true)][string]$OutDocx
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem

$encXml = New-Object System.Text.UTF8Encoding $false
if (-not (Test-Path -LiteralPath $MdPath)) { throw "Md not found: $MdPath" }

function Get-MdEncoding([string]$path) {
  $fs = [System.IO.File]::OpenRead($path)
  try {
    $bom = New-Object byte[] 4
    $n = $fs.Read($bom, 0, 4)
    if ($n -ge 2 -and $bom[0] -eq 0xFF -and $bom[1] -eq 0xFE) { return [System.Text.Encoding]::Unicode }
    if ($n -ge 2 -and $bom[0] -eq 0xFE -and $bom[1] -eq 0xFF) { return [System.Text.Encoding]::BigEndianUnicode }
    if ($n -ge 3 -and $bom[0] -eq 0xEF -and $bom[1] -eq 0xBB -and $bom[2] -eq 0xBF) {
      return (New-Object System.Text.UTF8Encoding $true)
    }
  } finally { $fs.Close() }
  return (New-Object System.Text.UTF8Encoding $false)
}
$enc = Get-MdEncoding $MdPath

function XmlEsc([string]$s) {
  if ($null -eq $s) { return '' }
  return $s.Replace('&', '&amp;').Replace('<', '&lt;').Replace('>', '&gt;')
}
function StripMd([string]$s) {
  $t = $s
  $t = [regex]::Replace($t, '\*\*([^*]+)\*\*', '$1')
  $t = [regex]::Replace($t, '`([^`]+)`', '$1')
  $t = [regex]::Replace($t, '^\>\s*', '')
  return $t.Trim()
}
function WPara([hashtable]$opt) {
  $text = [string]$opt.text
  $style = $(if ($opt.style) { $opt.style } else { 'Normal' })
  $align = ''
  if ($opt.align -eq 'center') { $align = '<w:jc w:val="center"/>' }
  $sb = 0; $sa = 80
  if ($null -ne $opt.spaceBefore) { $sb = [int]$opt.spaceBefore }
  if ($null -ne $opt.spaceAfter) { $sa = [int]$opt.spaceAfter }
  $spacing = '<w:spacing w:before="' + $sb + '" w:after="' + $sa + '"/>'
  $shd = ''
  if ($opt.shading) { $shd = '<w:shd w:val="clear" w:fill="' + $opt.shading + '"/>' }
  $pPr = '<w:pPr><w:pStyle w:val="' + $style + '"/>' + $align + $spacing + $shd + '</w:pPr>'
  $east = 'Microsoft JhengHei'
  $ascii = $(if ($opt.font) { [string]$opt.font } else { $east })
  $rPr = '<w:rPr><w:rFonts w:ascii="' + $ascii + '" w:hAnsi="' + $ascii + '" w:eastAsia="' + $east + '"/>'
  if ($opt.size) { $rPr += '<w:sz w:val="' + $opt.size + '"/><w:szCs w:val="' + $opt.size + '"/>' }
  if ($opt.bold) { $rPr += '<w:b/>' }
  $rPr += '</w:rPr>'
  return '<w:p>' + $pPr + '<w:r>' + $rPr + '<w:t xml:space="preserve">' + (XmlEsc $text) + '</w:t></w:r></w:p>'
}
function WPPageBreak() { return '<w:p><w:r><w:br w:type="page"/></w:r></w:p>' }
function WCell([string]$text, [bool]$bold, [string]$shd, [string]$align) {
  $jc = ''
  if ($align -eq 'center') { $jc = '<w:jc w:val="center"/>' }
  $rPr = '<w:rPr><w:rFonts w:ascii="Microsoft JhengHei" w:eastAsia="Microsoft JhengHei"/><w:sz w:val="18"/>'
  if ($bold) { $rPr += '<w:b/>' }
  $rPr += '</w:rPr>'
  $tcPr = '<w:tcPr><w:tcW w:w="0" w:type="auto"/>'
  if ($shd) { $tcPr += '<w:shd w:val="clear" w:fill="' + $shd + '"/>' }
  $tcPr += '</w:tcPr>'
  return '<w:tc>' + $tcPr + '<w:p><w:pPr>' + $jc + '</w:pPr><w:r>' + $rPr + '<w:t xml:space="preserve">' + (XmlEsc $text) + '</w:t></w:r></w:p></w:tc>'
}
function WTable($rows) {
  if ($null -eq $rows -or $rows.Count -eq 0) { return '' }
  $cols = 0
  foreach ($r in $rows) { if ($r.Count -gt $cols) { $cols = $r.Count } }
  $sb = New-Object System.Text.StringBuilder
  [void]$sb.Append('<w:tbl><w:tblPr><w:tblW w:w="5000" w:type="pct"/><w:tblBorders>')
  foreach ($e in @('top', 'left', 'bottom', 'right', 'insideH', 'insideV')) {
    [void]$sb.Append('<w:' + $e + ' w:val="single" w:sz="4" w:space="0" w:color="666666"/>')
  }
  [void]$sb.Append('</w:tblBorders></w:tblPr><w:tblGrid>')
  for ($i = 0; $i -lt $cols; $i++) { [void]$sb.Append('<w:gridCol w:w="1800"/>') }
  [void]$sb.Append('</w:tblGrid>')
  for ($ri = 0; $ri -lt $rows.Count; $ri++) {
    [void]$sb.Append('<w:tr>')
    for ($ci = 0; $ci -lt $cols; $ci++) {
      $val = ''
      if ($ci -lt $rows[$ri].Count) { $val = [string]$rows[$ri][$ci] }
      $shd = ''; if ($ri -eq 0) { $shd = 'D9E2F3' }
      $al = 'left'; if ($ri -eq 0) { $al = 'center' }
      [void]$sb.Append((WCell $val ($ri -eq 0) $shd $al))
    }
    [void]$sb.Append('</w:tr>')
  }
  [void]$sb.Append('</w:tbl>')
  [void]$sb.Append((WPara @{ text = ''; style = 'Normal'; spaceBefore = 0; spaceAfter = 120 }))
  return $sb.ToString()
}
function WCodeBlock([string]$json) {
  $sb = New-Object System.Text.StringBuilder
  foreach ($line in ($json -split "`r?`n")) {
    [void]$sb.Append((WPara @{ text = $line; style = 'Normal'; size = 16; font = 'Consolas'; shading = 'F2F2F2'; spaceBefore = 0; spaceAfter = 0 }))
  }
  return $sb.ToString()
}

$body = New-Object System.Text.StringBuilder
function B([string]$x) { [void]$script:body.Append($x) }

$lines = [System.IO.File]::ReadAllLines($MdPath, $enc)
$i = 0
$mode = 'body'
$inTable = $false
$tableRows = $null
$inJson = $false
$jsonBuf = New-Object System.Text.StringBuilder

function Flush-Table {
  if ($script:inTable -and $script:tableRows -and $script:tableRows.Count -gt 0) {
    B (WTable $script:tableRows)
  }
  $script:tableRows = $null
  $script:inTable = $false
}

while ($i -lt $lines.Count) {
  $t = $lines[$i]

  if ($t -match '<!--\s*COVER_PAGE\s*-->') { $mode = 'cover'; $i++; continue }
  if ($t -match '<!--\s*REV_PAGE\s*-->') { $mode = 'rev'; $i++; continue }
  if ($t -match '<!--\s*PAGE_BREAK\s*-->') {
    Flush-Table
    B (WPPageBreak)
    if ($mode -eq 'cover') { $mode = 'rev' }
    elseif ($mode -eq 'rev') { $mode = 'body' }
    $i++; continue
  }

  if ($mode -eq 'cover') {
    if ($t -match '<!--\s*COVER_LOGO\s*-->(.*)$') {
      B (WPara @{ text = ''; style = 'Normal'; align = 'center'; spaceBefore = 800; spaceAfter = 200 })
      $logo = $Matches[1].Trim()
      if ($logo) { B (WPara @{ text = $logo; style = 'Normal'; align = 'center'; size = 20; spaceBefore = 200; spaceAfter = 600 }) }
      else { B (WPara @{ text = ''; style = 'Normal'; align = 'center'; spaceBefore = 400; spaceAfter = 600 }) }
      $i++; continue
    }
    if ($t -match '<!--\s*COVER_LINE1\s*-->(.*)$') {
      B (WPara @{ text = $Matches[1].Trim(); style = 'Normal'; align = 'center'; size = 72; bold = $true; spaceBefore = 400; spaceAfter = 120 }); $i++; continue
    }
    if ($t -match '<!--\s*COVER_LINE2\s*-->(.*)$') {
      B (WPara @{ text = $Matches[1].Trim(); style = 'Normal'; align = 'center'; size = 72; bold = $true; spaceBefore = 80; spaceAfter = 120 }); $i++; continue
    }
    if ($t -match '<!--\s*COVER_LINE3\s*-->(.*)$') {
      B (WPara @{ text = $Matches[1].Trim(); style = 'Normal'; align = 'center'; size = 72; bold = $true; spaceBefore = 80; spaceAfter = 400 }); $i++; continue
    }
    if ($t -match '<!--\s*COVER_COMPANY\s*-->(.*)$') {
      B (WPara @{ text = ''; style = 'Normal'; align = 'center'; spaceBefore = 1200; spaceAfter = 100 })
      B (WPara @{ text = $Matches[1].Trim(); style = 'Normal'; align = 'center'; size = 36; spaceBefore = 200; spaceAfter = 200 })
      $i++; continue
    }
    $i++; continue
  }

  if ($mode -eq 'rev') {
    if ($t -match '<!--\s*REV_COPY_H\s*-->(.*)$') {
      B (WPara @{ text = $Matches[1].Trim(); style = 'Normal'; align = 'center'; size = 24; bold = $true; spaceBefore = 200; spaceAfter = 200 }); $i++; continue
    }
    if ($t -match '<!--\s*REV_COPY_BODY\s*-->(.*)$') {
      B (WPara @{ text = $Matches[1].Trim(); style = 'Normal'; align = 'left'; size = 24; spaceBefore = 100; spaceAfter = 300 }); $i++; continue
    }
    if ($t -match '<!--\s*REV_H\s*-->(.*)$') {
      B (WPara @{ text = $Matches[1].Trim(); style = 'Normal'; align = 'center'; size = 48; bold = $true; spaceBefore = 300; spaceAfter = 240 }); $i++; continue
    }
  }

  if ($inJson) {
    if ($t.Trim().StartsWith('```')) {
      B (WCodeBlock ($jsonBuf.ToString().TrimEnd()))
      $jsonBuf = New-Object System.Text.StringBuilder
      $inJson = $false
      $i++; continue
    }
    [void]$jsonBuf.AppendLine($t)
    $i++; continue
  }
  if ($t.Trim().StartsWith('```')) {
    Flush-Table
    $inJson = $true
    $jsonBuf = New-Object System.Text.StringBuilder
    $i++; continue
  }

  if ($t.StartsWith('|')) {
    if (-not $inTable) { $tableRows = New-Object System.Collections.Generic.List[object]; $inTable = $true }
    if ($t -match '^\|[\s\-:|]+\|$') { $i++; continue }
    # protect \| inside cells
    $safe = $t -replace '\\\|', [char]0x29F8
    $cells = @()
    foreach ($p in $safe.Trim('|').Split('|')) {
      $cells += , ((StripMd $p.Trim()) -replace [char]0x29F8, '/')
    }
    $tableRows.Add($cells)
    $i++; continue
  }
  if ($inTable) { Flush-Table }

  if ([string]::IsNullOrWhiteSpace($t) -or $t -eq '---') { $i++; continue }
  if ($t.StartsWith('<!--')) { $i++; continue }
  if ($t.StartsWith('> ')) {
    B (WPara @{ text = (StripMd $t.Substring(2)); style = 'Normal'; size = 21 }); $i++; continue
  }
  if ($t.StartsWith('#### ')) { B (WPara @{ text = (StripMd $t.Substring(5)); style = 'Heading3'; size = 22; bold = $true; spaceBefore = 200; spaceAfter = 100 }); $i++; continue }
  if ($t.StartsWith('### ')) { B (WPara @{ text = (StripMd $t.Substring(4)); style = 'Heading2'; size = 26; bold = $true; spaceBefore = 280; spaceAfter = 120 }); $i++; continue }
  if ($t.StartsWith('## ')) { B (WPara @{ text = (StripMd $t.Substring(3)); style = 'Heading1'; size = 32; bold = $true; spaceBefore = 360; spaceAfter = 160 }); $i++; continue }
  if ($t.StartsWith('# ')) { B (WPara @{ text = (StripMd $t.Substring(2)); style = 'Title'; size = 44; bold = $true }); $i++; continue }

  B (WPara @{ text = (StripMd $t); style = 'Normal'; size = 21 })
  $i++
}
Flush-Table

$stylesXml = @'
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<w:styles xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
  <w:style w:type="paragraph" w:default="1" w:styleId="Normal">
    <w:name w:val="Normal"/><w:qFormat/>
    <w:rPr><w:rFonts w:ascii="Microsoft JhengHei" w:eastAsia="Microsoft JhengHei" w:hAnsi="Microsoft JhengHei"/><w:sz w:val="21"/><w:szCs w:val="21"/></w:rPr>
  </w:style>
  <w:style w:type="paragraph" w:styleId="Title">
    <w:name w:val="Title"/><w:basedOn w:val="Normal"/><w:qFormat/>
    <w:rPr><w:b/><w:sz w:val="44"/><w:szCs w:val="44"/></w:rPr>
  </w:style>
  <w:style w:type="paragraph" w:styleId="Heading1">
    <w:name w:val="heading 1"/><w:basedOn w:val="Normal"/><w:qFormat/>
    <w:pPr><w:outlineLvl w:val="0"/></w:pPr>
    <w:rPr><w:b/><w:sz w:val="32"/><w:szCs w:val="32"/><w:color w:val="1F4E79"/></w:rPr>
  </w:style>
  <w:style w:type="paragraph" w:styleId="Heading2">
    <w:name w:val="heading 2"/><w:basedOn w:val="Normal"/><w:qFormat/>
    <w:pPr><w:outlineLvl w:val="1"/></w:pPr>
    <w:rPr><w:b/><w:sz w:val="26"/><w:szCs w:val="26"/><w:color w:val="2E75B6"/></w:rPr>
  </w:style>
  <w:style w:type="paragraph" w:styleId="Heading3">
    <w:name w:val="heading 3"/><w:basedOn w:val="Normal"/><w:qFormat/>
    <w:pPr><w:outlineLvl w:val="2"/></w:pPr>
    <w:rPr><w:b/><w:sz w:val="22"/><w:szCs w:val="22"/><w:color w:val="5B9BD5"/></w:rPr>
  </w:style>
</w:styles>
'@

$documentXml = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"><w:body>' + $body.ToString() + '<w:sectPr><w:pgSz w:w="11906" w:h="16838"/><w:pgMar w:top="1134" w:right="1134" w:bottom="1134" w:left="1134"/></w:sectPr></w:body></w:document>'
$contentTypes = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/><Override PartName="/word/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml"/></Types>'
$rels = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/></Relationships>'
$docRels = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/></Relationships>'

$work = Join-Path $env:TEMP ('apispec_' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory $work | Out-Null
New-Item -ItemType Directory (Join-Path $work '_rels') | Out-Null
New-Item -ItemType Directory (Join-Path $work 'word') | Out-Null
New-Item -ItemType Directory (Join-Path $work 'word\_rels') | Out-Null
[System.IO.File]::WriteAllText((Join-Path $work '[Content_Types].xml'), $contentTypes, $encXml)
[System.IO.File]::WriteAllText((Join-Path $work '_rels\.rels'), $rels, $encXml)
[System.IO.File]::WriteAllText((Join-Path $work 'word\document.xml'), $documentXml, $encXml)
[System.IO.File]::WriteAllText((Join-Path $work 'word\styles.xml'), $stylesXml, $encXml)
[System.IO.File]::WriteAllText((Join-Path $work 'word\_rels\document.xml.rels'), $docRels, $encXml)

$zip = Join-Path $env:TEMP ('apispecz_' + [guid]::NewGuid().ToString('N') + '.zip')
[System.IO.Compression.ZipFile]::CreateFromDirectory($work, $zip)
$outDir = Split-Path -Parent $OutDocx
if ($outDir -and -not (Test-Path -LiteralPath $outDir)) { New-Item -ItemType Directory -Path $outDir | Out-Null }
if (Test-Path -LiteralPath $OutDocx) { Remove-Item -LiteralPath $OutDocx -Force }
[System.IO.File]::Copy($zip, $OutDocx, $true)
Remove-Item $work -Recurse -Force
Remove-Item $zip -Force

$z = [System.IO.Compression.ZipFile]::OpenRead($OutDocx)
$e = $z.Entries | Where-Object { ($_.FullName -replace '\\', '/') -eq 'word/document.xml' } | Select-Object -First 1
$sr = New-Object System.IO.StreamReader($e.Open(), $encXml)
$xml = $sr.ReadToEnd(); $sr.Close(); $z.Dispose()
Write-Output ('OK docx=' + (Get-Item -LiteralPath $OutDocx).Length)
Write-Output ('tables=' + ([regex]::Matches($xml, '<w:tbl>')).Count)
Write-Output ('pagebreaks=' + ([regex]::Matches($xml, 'w:type="page"')).Count)
Write-Output ('code_shading=' + ([regex]::Matches($xml, 'F2F2F2')).Count)
