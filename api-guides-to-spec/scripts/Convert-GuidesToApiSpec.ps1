<#
.SYNOPSIS
  Aggregate call-guide Markdown files into a formal API Spec.md (UTF-8 BOM) + .docx.

.PARAMETER GuideDir
  Folder containing call guides (UTF-8 markdown).

.PARAMETER OutDir
  Output folder.

.PARAMETER OutBaseName
  Base file name without extension (default MeetingRoom_API_Spec).

.PARAMETER Locale
  Labels locale id. Loads labels/labels.<Locale>.json (default zh-TW).

.PARAMETER LabelsPath
  Optional explicit path to a labels JSON file (overrides Locale).

.PARAMETER GuidePattern
  Optional glob for guides; if empty, files ending with labels.guideFileSuffix are used.

.PARAMETER SystemName
  Optional cover line 1 override (else labels.cover.systemName).

.PARAMETER SystemSub
  Optional cover line 2 override (else labels.cover.systemSub).
#>
[CmdletBinding()]
param(
  [string]$GuideDir = 'MCP',
  [string]$OutDir = '',
  [string]$OutBaseName = 'MeetingRoom_API_Spec',
  [string]$Locale = 'zh-TW',
  [string]$LabelsPath = '',
  [string]$GuidePattern = '',
  [string]$SystemName = '',
  [string]$SystemSub = ''
)

$ErrorActionPreference = 'Stop'
$enc = New-Object System.Text.UTF8Encoding $false
$encMd = New-Object System.Text.UTF8Encoding $true

$repo = (Get-Location).Path
if (-not [System.IO.Path]::IsPathRooted($GuideDir)) { $GuideDir = Join-Path $repo $GuideDir }
if (-not $OutDir) { $OutDir = $GuideDir }
elseif (-not [System.IO.Path]::IsPathRooted($OutDir)) { $OutDir = Join-Path $repo $OutDir }
if (-not (Test-Path -LiteralPath $GuideDir)) { throw "GuideDir not found: $GuideDir" }

# Load labels.<Locale>.json (UTF-8 BOM OK)
$labelsRoot = Join-Path (Split-Path -Parent $PSScriptRoot) 'labels'
if (-not $LabelsPath) {
  $LabelsPath = Join-Path $labelsRoot ("labels." + $Locale + '.json')
}
elseif (-not [System.IO.Path]::IsPathRooted($LabelsPath)) {
  $LabelsPath = Join-Path $repo $LabelsPath
}
if (-not (Test-Path -LiteralPath $LabelsPath)) {
  throw "Labels file not found: $LabelsPath (add labels/labels.<Locale>.json)"
}
$L = Get-Content -LiteralPath $LabelsPath -Encoding UTF8 -Raw | ConvertFrom-Json
Write-Output ('locale=' + $L.locale + ' labels=' + $LabelsPath)

$P = $L.punct
$Cvr = $L.cover
$Rev = $L.revision
$G = $L.guide
$Ch = $L.chapters
$Api = $L.api
$Def = $L.defaults

$sysName = $(if ($SystemName) { $SystemName } else { [string]$Cvr.systemName })
$sysSub = $(if ($SystemSub) { $SystemSub } else { [string]$Cvr.systemSub })
$colon = [string]$P.colon
$lp = [string]$P.lp
$rp = [string]$P.rp
$slash = [string]$P.slash
$mark = [string]$P.mark
$period = [string]$P.period
$arrow = [string]$P.arrow
$guideWord = [string]$G.callGuideWord
$commonResp = [string]$G.commonResponse
$needParam = [string]$G.requiredParams

function StripMd([string]$s) {
  if ($null -eq $s) { return '' }
  $t = $s
  $t = [regex]::Replace($t, '\*\*([^*]+)\*\*', '$1')
  $t = [regex]::Replace($t, '`([^`]+)`', '$1')
  $t = [regex]::Replace($t, '^\>\s*', '')
  return $t.Trim()
}
function FirstPara([string]$md) {
  $buf = New-Object System.Text.StringBuilder
  $started = $false
  foreach ($line in ($md -split "`r?`n")) {
    if ($line -match '^#\s') { continue }
    if ($line -match '^---\s*$') { break }
    if ([string]::IsNullOrWhiteSpace($line)) { if ($started) { break } else { continue } }
    $started = $true
    [void]$buf.AppendLine((StripMd $line))
  }
  return $buf.ToString().Trim()
}
function ExtractField([string]$md, [string]$label) {
  $pat1 = '\| ' + [regex]::Escape($label) + ' \| ``([^``]+)``'
  if ($md -match $pat1) { return $Matches[1] }
  $pat2 = '\| ' + [regex]::Escape($label) + ' \| ([^|]+)\|'
  if ($md -match $pat2) { return (StripMd $Matches[1]) }
  return ''
}
function ExtractSection([string]$md, [string]$contains) {
  $capturing = $false
  $buf = New-Object System.Text.StringBuilder
  foreach ($line in ($md -split "`r?`n")) {
    if ((-not $capturing) -and $line -match '^##\s+' -and $line.Contains($contains)) { $capturing = $true; continue }
    if ($capturing -and $line -match '^##\s+') { break }
    if ($capturing) { [void]$buf.AppendLine($line) }
  }
  return $buf.ToString()
}
function ExtractH3Block([string]$md, [string]$contains) {
  $capturing = $false
  $buf = New-Object System.Text.StringBuilder
  foreach ($line in ($md -split "`r?`n")) {
    if ((-not $capturing) -and $line -match '^###\s+' -and $line.Contains($contains)) { $capturing = $true; continue }
    if ($capturing -and $line -match '^#{1,3}\s+') { break }
    if ($capturing -and $line -match '^---\s*$') { break }
    if ($capturing) { [void]$buf.AppendLine($line) }
  }
  return $buf.ToString()
}
function ParseFirstMdTable([string]$block) {
  $rows = New-Object System.Collections.Generic.List[object]
  $inTable = $false
  foreach ($line in ($block -split "`r?`n")) {
    $t = $line.Trim()
    if ($t.StartsWith('|')) {
      $inTable = $true
      if ($t -match '^\|[\s\-:|]+\|$') { continue }
      $safe = $t -replace '\\\|', [char]0x29F8
      $cells = @()
      foreach ($p in $safe.Trim('|').Split('|')) {
        $cells += , ((StripMd $p.Trim()) -replace [char]0x29F8, '/')
      }
      $rows.Add($cells)
    }
    elseif ($inTable) { break }
  }
  return $rows
}
function ParseResponseBlocks([string]$respSection) {
  $items = New-Object System.Collections.Generic.List[object]
  $lines = $respSection -split "`r?`n"
  $i = 0
  while ($i -lt $lines.Count) {
    if ($lines[$i] -match '^\*\*(.+?)\*\*\s*$') {
      $label = $Matches[1]
      $j = $i + 1
      while ($j -lt $lines.Count -and [string]::IsNullOrWhiteSpace($lines[$j])) { $j++ }
      if ($j -lt $lines.Count -and $lines[$j].Trim().StartsWith('```')) {
        $j++
        $json = New-Object System.Text.StringBuilder
        while ($j -lt $lines.Count -and -not $lines[$j].Trim().StartsWith('```')) {
          [void]$json.AppendLine($lines[$j]); $j++
        }
        $items.Add([pscustomobject]@{ Label = $label; Json = $json.ToString().TrimEnd() })
        $i = $j + 1; continue
      }
    }
    $i++
  }
  return $items
}
function ResponseIntro([string]$respSection) {
  foreach ($line in ($respSection -split "`r?`n")) {
    if ([string]::IsNullOrWhiteSpace($line)) { continue }
    if ($line -match '^\*\*' -or $line.StartsWith('|') -or $line.StartsWith('```')) { break }
    return (StripMd $line)
  }
  return ''
}
function AuthNote([string]$respSection) {
  foreach ($line in ($respSection -split "`r?`n")) {
    if ($line -match '401') { return (StripMd $line) }
  }
  return ''
}
function Format-IssueDate {
  $y = Get-Date -Format 'yyyy'
  $m = Get-Date -Format 'MM'
  $d = Get-Date -Format 'dd'
  $ys = [string]$Rev.yearSuffix
  $ms = [string]$Rev.monthSuffix
  $ds = [string]$Rev.daySuffix
  if ($ys -eq '-' -and $ms -eq '-') {
    return ($y + '-' + $m + '-' + $d)
  }
  return ($y + $ys + $m + $ms + $d + $ds)
}

$guideSuffix = [string]$L.guideFileSuffix
$guides = @()
if ($GuidePattern) {
  $guides = @(Get-ChildItem -LiteralPath $GuideDir -File -Filter $GuidePattern |
    Where-Object { $_.Name -notlike '*Spec*' } | Sort-Object Name)
}
if ($guides.Count -eq 0) {
  $guides = @(Get-ChildItem -LiteralPath $GuideDir -File |
    Where-Object { $_.Name.EndsWith($guideSuffix) -and $_.Name -notlike '*Spec*' } |
    Sort-Object Name)
}
if ($guides.Count -eq 0) { throw "No guides found in $GuideDir (expect *$guideSuffix)" }
Write-Output ('guides=' + $guides.Count)

$md = New-Object System.Text.StringBuilder
function M([string]$s) { [void]$script:md.AppendLine($s) }
function MBlank() { [void]$script:md.AppendLine('') }
function MTable($rows) {
  if ($null -eq $rows -or $rows.Count -eq 0) { return }
  M ('| ' + ($rows[0] -join ' | ') + ' |')
  M ('| ' + (($rows[0] | ForEach-Object { '---' }) -join ' | ') + ' |')
  for ($r = 1; $r -lt $rows.Count; $r++) { M ('| ' + ($rows[$r] -join ' | ') + ' |') }
}
function MPage() { MBlank; M '<!-- PAGE_BREAK -->'; MBlank }

# Cover
M '<!-- COVER_PAGE -->'
MBlank
M '<!-- COVER_LOGO -->'
MBlank
M ('<!-- COVER_LINE1 -->' + $sysName)
M ('<!-- COVER_LINE2 -->' + $sysSub)
M ('<!-- COVER_LINE3 -->' + [string]$Cvr.apiDocTitle)
MBlank
MBlank
M ('<!-- COVER_COMPANY -->' + [string]$Cvr.madeBy)
MPage

# Revision
M '<!-- REV_PAGE -->'
MBlank
M ('<!-- REV_COPY_H -->' + [string]$Rev.copyrightHeading)
MBlank
M ('<!-- REV_COPY_BODY -->' + [string]$Rev.copyrightBody)
MBlank
M ('<!-- REV_H -->' + [string]$Rev.revisionHeading)
MBlank
MTable @(
  @([string]$Rev.colVersion, [string]$Rev.colDate, [string]$Rev.colDesc, [string]$Rev.colUnit, [string]$Rev.colWho),
  @('0.1', (Format-IssueDate), [string]$Rev.firstIssue, '', '')
)
MPage

# Chapter 1
M ('## 1. ' + [string]$Ch.ch1Title)
MBlank
M (([string]$Ch.ch1Intro).Replace('{guideWord}', $guideWord))
MBlank
M ('### 1.1. ' + [string]$Ch.s11Title)
MBlank
MTable @(
  @([string]$Ch.colItem, [string]$Ch.colContent),
  @('Base URL', [string]$Def.baseUrl),
  @([string]$Ch.auth, [string]$Def.authPolicy)
)
MBlank
M ('### 1.2. ' + [string]$Ch.s12Title)
MBlank
M '```'
M '{BaseURL}/api/{Controller}/{action}'
M '```'
MBlank
M ('### 1.3. ' + [string]$Ch.s13Title)
MBlank
MTable @(
  @([string]$Ch.colParamName, [string]$Ch.colDesc),
  @('UserId', 'userdata_code'),
  @('MeetingRoomUid', 'meetingroomdata_uid'),
  @('BookingUid', [string]$Ch.bookingUidDesc)
)
MBlank
M ('### 1.4. ' + [string]$Ch.s14Title)
MBlank
M ('- action_result = ok' + $slash + 'error')
M ('- IP ' + [string]$Ch.whitelist + ' ' + $arrow + ' HTTP 401' + $slash + '403')
MBlank
M ('### 1.5. ' + [string]$Ch.s15Title)
MBlank

$n = 0
foreach ($g in $guides) {
  $n++
  $raw = [System.IO.File]::ReadAllText($g.FullName, $enc)
  $titleLine = ($raw -split "`r?`n" | Where-Object { $_ -match '^#\s+' } | Select-Object -First 1)
  $apiTitle = if ($titleLine) { (StripMd ($titleLine -replace '^#\s+', '')) } else { $g.BaseName }
  $purpose = FirstPara $raw
  $method = ExtractField $raw 'Method'
  $path = ExtractField $raw 'Path'
  $ctype = ExtractField $raw 'Content-Type'
  $ctrl = ExtractField $raw 'Controller'
  $action = ExtractField $raw 'Action'
  $mode = if ($method -eq 'GET') { 'Query' } else { 'Body' }
  $paramRows = ParseFirstMdTable (ExtractSection $raw $needParam)
  $respSec = ExtractH3Block $raw $commonResp
  if ([string]::IsNullOrWhiteSpace($respSec)) { $respSec = ExtractH3Block $raw '1.2' }
  $respIntro = ResponseIntro $respSec
  $respBlocks = ParseResponseBlocks $respSec
  $respFields = ParseFirstMdTable $respSec
  $auth = AuthNote $respSec

  M ('#### 1.5.' + $n + '. ' + $apiTitle)
  MBlank
  M ([string]$Api.purpose + $colon + $purpose)
  MBlank
  M ([string]$Api.description + $colon + [string]$Api.seeGuide + $guideWord + $period)
  MBlank
  M ($mark + ' HTTP METHOD' + $colon + '`' + $method + '`')
  M ($mark + ' API URI' + $colon + '`' + $path + '`')
  if ($ctype) { M ($mark + ' Content-Type' + $colon + '`' + $ctype + '`') }
  if ($ctrl) { M ($mark + ' Controller' + $colon + '`' + $ctrl + '`') }
  if ($action) { M ($mark + ' Action' + $colon + '`' + $action + '`') }
  M ($mark + ' ' + [string]$Api.auth + $colon + '`' + [string]$Def.authPolicy + '`')
  MBlank
  M ($mark + ' ' + [string]$Api.params + $colon + $lp + $mode + $rp)
  MBlank
  if ($paramRows.Count -gt 0) { MTable $paramRows; MBlank }

  M ($mark + ' ' + [string]$Api.responseJson)
  MBlank
  if ($respIntro) { M $respIntro; MBlank }
  foreach ($b in $respBlocks) {
    M ('**' + $b.Label + '**')
    MBlank
    M '```json'
    M $b.Json
    M '```'
    MBlank
  }
  if ($respFields.Count -gt 0) {
    M ($mark + ' ' + [string]$Api.responseFields + $colon)
    MBlank
    MTable $respFields
    MBlank
  }
  if ($auth) {
    M ($mark + ' ' + [string]$Api.authFail + $colon + $auth)
    MBlank
  }
  M ($mark + ' ' + [string]$Api.details + $colon + '`' + $g.Name + '`')
  MBlank
}

M ('### 1.6. ' + [string]$Ch.s16Title)
MBlank
MTable @(
  @([string]$Ch.colCode, [string]$Ch.colMeaning),
  @('action_result = ok', [string]$Ch.bizOk),
  @('action_result = error', [string]$Ch.bizFail),
  @('HTTP 401' + $slash + '403', [string]$Ch.ipNotInWhitelist)
)
MPage

$role = Get-ChildItem -LiteralPath $GuideDir -File | Where-Object { $_.Name -eq 'RoleSetting.md' } | Select-Object -First 1
M ('## 2. ' + [string]$Ch.ch2Title)
MBlank
if ($role) {
  M '### 2.1. RoleSetting'
  MBlank
  foreach ($line in [System.IO.File]::ReadAllLines($role.FullName, $enc)) {
    if (-not [string]::IsNullOrWhiteSpace($line)) { M ('- ' + (StripMd $line)) }
  }
  MBlank
}
MPage

M ('## ' + [string]$Ch.appendixTitle + $colon + [string]$Ch.sourceFiles)
MBlank
$srcRows = New-Object System.Collections.Generic.List[object]
$srcRows.Add(@([string]$Ch.colSection, [string]$Ch.colFileName))
$k = 0
foreach ($g in $guides) {
  $k++
  $srcRows.Add(@('1.5.' + $k, $g.Name))
}
MTable $srcRows

$mdPath = Join-Path $OutDir ($OutBaseName + '.md')
if (-not (Test-Path -LiteralPath $OutDir)) { New-Item -ItemType Directory -Path $OutDir | Out-Null }
[System.IO.File]::WriteAllText($mdPath, $md.ToString(), $encMd)
Write-Output ('md=' + $mdPath + ' bytes=' + (Get-Item -LiteralPath $mdPath).Length + ' encoding=UTF8-BOM')
Write-Output ('json_blocks=' + ([regex]::Matches($md.ToString(), '```json')).Count)

$docxScript = Join-Path $PSScriptRoot 'Convert-SpecMdToDocx.ps1'
$outDocx = Join-Path $OutDir ($OutBaseName + '.docx')
& $docxScript -MdPath $mdPath -OutDocx $outDocx
Write-Output 'done'
