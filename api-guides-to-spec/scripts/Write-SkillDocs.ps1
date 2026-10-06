# ASCII-only. Writes SKILL.md + reference.md (UTF-8 BOM, proper CJK).
$ErrorActionPreference = 'Stop'
$enc = New-Object System.Text.UTF8Encoding $true
function C([int[]]$c) { -join ($c | ForEach-Object { [char]$_ }) }

$here = $PSScriptRoot
$root = Split-Path -Parent $here

$hj = C 0x547C,0x53EB,0x6307,0x5357
$sm = C 0x8AAA,0x660E,0x6587,0x4EF6
$zs = C 0x6B63,0x5F0F
$zw = C 0x4E2D,0x6587
$fm = C 0x5C01,0x9762
$gb = C 0x6539,0x7248,0x6B77,0x7A0B
$zj = C 0x7AE0,0x7BC0
$fy = C 0x5206,0x9801
$mk = [string][char]0x25CE
$bg = C 0x8868,0x683C
$hc = C 0x56DE,0x50B3
$cs = C 0x53C3,0x6578
$tyhy = C 0x901A,0x7528,0x56DE,0x61C9,0x683C,0x5F0F
$hz = C 0x532F,0x6574
$dc = C 0x532F,0x51FA
$cx = C 0x91CD,0x65B0,0x7522,0x751F
$sy = C 0x4F55,0x6642,0x4F7F,0x7528
$sc = C 0x8F38,0x51FA
$by = C 0x4E0D,0x8981
$gy = C 0x6539,0x7528
$wt = C 0x554F,0x984C
$zf = C 0x505A,0x6CD5
$jd = C 0x9032,0x5EA6
$tj = C 0x63A8,0x85A6,0x547D,0x4EE4
$kq = C 0x53EF,0x9078
$mb = C 0x6A21,0x677F
$gui = C 0x898F,0x683C
$yang = C 0x6A23,0x672C
$jie = C 0x7D50,0x69CB
$wei = C 0x70BA
$ty = C 0x901A,0x7528
$bux = C 0x4E0D,0x9650
$td = C 0x7279,0x5B9A
$cj = C 0x5EE0,0x5546
$ck = C 0x53EF,0x53C3,0x8003
$lei = C 0x985E
$sc2 = C 0x624B,0x518A
$gua = C 0x639B,0x4F4F
$cun = C 0x5B58,0x6A94
$shiBai = C 0x5931,0x6557
$bian = C 0x8B8A,0x6210
$zhi = C 0x76F4,0x63A5
$xie = C 0x5BEB,0x5165
$fuzhu = C 0x8F14,0x52A9
$cong = C 0x5F9E
$du = C 0x8B80
$guan = C 0x7BA1,0x7DDA
$dang = C 0x7576
$chun = C 0x7D14,0x6587,0x5B57
$tie = C 0x8CBC,0x5165
$bushibg = C 0x4E0D,0x662F,0x8868,0x683C
$tiao = C 0x8DF3,0x904E
$que = C 0x7F3A,0x5C11
$jiexi = C 0x89E3,0x6790
$gongju = C 0x5DE5,0x5177
$xianshi = C 0x986F,0x793A
$luan = C 0x4E82,0x78BC
$wuBom = C 0x7121,0x20,0x42,0x4F,0x4D
$youBom = C 0x542B,0x20,0x42,0x4F,0x4D
$md = C 0x76EE,0x7684
$qk = C 0x5340,0x584A
$shi2 = C 0x5BE6,0x969B
$nr = C 0x5167,0x5BB9
$yu = C 0x8207
$buyong = C 0x4E0D,0x7528
$duo = C 0x591A,0x4EFD
$cheng = C 0x6210
$yi = C 0x4E00,0x4EFD
$xu = C 0x9700,0x8981
$huo = C 0x6216
$you = C 0x7531
$sheng = C 0x7522,0x751F
$zai = C 0x5728
$ding = C 0x5B9A,0x4F4D
$chou = C 0x62BD,0x53D6
$xiechu = C 0x5BEB,0x51FA
$zhuan = C 0x8F49,0x63DB
$yan = C 0x9A57,0x8B49
$chouyan = C 0x62BD,0x67E5
$dy1 = C 0x7B2C,0x4E00,0x9801
$dy2 = C 0x7B2C,0x4E8C,0x9801
$zw2 = C 0x6B63,0x6587
$bj = C 0x6A19,0x8A18
$hs = C 0x7070,0x5E95
$ben = C 0x672C,0x500B,0x5EAB
$wj = C 0x6A94,0x6848
$sm2 = C 0x8AAA,0x660E
$gs = C 0x516C,0x53F8
$xddw = C 0x4FEE,0x8A02,0x55AE,0x4F4D
$xdr = C 0x4FEE,0x8A02,0x4EBA,0x54E1
$moren = C 0x9810,0x8A2D
$kb = C 0x7559,0x7A7A
$bt = C 0x6A19,0x984C
$ruoyi = C 0x82E5,0x5DF2,0x6709
$yicun = C 0x5DF2,0x5B58,0x5728
$jinxu = C 0x50C5,0x9700
$zl = C 0x8CC7,0x6599,0x593E
$lp = [char]0xFF08
$rp = [char]0xFF09
$colon = [char]0xFF1A
$comma = [char]0xFF0C
$period = [char]0x3002
$dun = [char]0x3001
$arrow = [char]0x2192

$skill = @"
---
name: api-guides-to-spec
description: >-
  $($hz) API $($hj).md $($wei)$($zs)$($zw) API $($gui)$($sm)
  $($lp)$($fm)$($dy1)$($dun)$($gb)$($dun)$($zj)$($fy)$($dun)$($mk) $($qk)$($dun)$($shi2) Word $($bg)$($dun)$($hc)JSON $($yang)$($rp)$($period)
  $($sc) UTF-8 BOM .md $($yu) OOXML .docx$($lp)$($buyong) Word COM$($rp)$($period)
  $($sy)$($colon)$($hz)$($hj)$($dun)$($dc) API $($sm)$($dun)guides to docx/md$($dun)
  $($cx) MeetingRoom_API_Spec$($comma)$($huo)$($you)$($duo)$($hj)$($sheng)$($zs) API $($gui)$($sm)$($period)
---

# API $($hj) $($arrow) $($zs) API $($sm) (md + docx)

## $($sy)

- $($hz)$($duo) ``*$($hj).md``$($lp)$($kq) ``RoleSetting.md``$($rp)$($cheng)$($yi) API $($sm)
- $($xu) **$($fm) + $($gb) + $($zj)$($fy) + $($mk) $($qk) + $($shi2) $($bg) + $($hc)JSON**
- $($sc) **Markdown$($lp)UTF-8 BOM$($dun)$($zw)$($nr)$($rp)** $($yu) **Word$($lp).docx$($rp)**

$($jie)$($wei)$($ty)$($gui) API $($sm)$($mb)$($lp)$($bux)$($td)$($cj)$($rp)$($period)$($ck)$($colon)ESP$($lei) API $($sc2)$($period)

## $($by)

| $($zf) | $($wt) | $($gy) |
|----------|---------|-------------|
| Word COM | $($gua) / $($cun)$($shiBai) | OOXML zip ``.docx`` |
| $($zai) ``.ps1`` $($zhi)$($xie)$($zw) | $($bian) ``?`` | ``[char]0xXXXX`` / ``C`` $($fuzhu)$($semicolon=$null)$($dun)$($cong)$($hj)$($du) UTF-8 |
| MD $($guan)$($dang)$($chun) $($tie) Word | $($bushibg) | $($sc) ``<w:tbl>`` |
| $($tiao) ``1.2 $($tyhy)`` | $($que) $($hc)JSON | $($jiexi) ``**label**`` + ``json`` |
| MD $($wuBom) | $($gongju)$($xianshi)$($luan) | UTF-8 $($youBom) |

## $($tj)

Windows PowerShell (``required_permissions: ["all"]``):

``````powershell
powershell -NoProfile -ExecutionPolicy Bypass -File ".cursor/skills/api-guides-to-spec/scripts/Convert-GuidesToApiSpec.ps1" ``
  -GuideDir "MCP" ``
  -OutDir "MCP" ``
  -OutBaseName "MeetingRoom_API_Spec"
``````

Optional: ``-SystemNameChars`` / ``-SystemSubChars``$($lp)$($fm)$($bt) Unicode codepoints$($rp)$($period)

$($ruoyi) Spec.md $($yicun)$($dun)$($jinxu) docx$($colon)

``````powershell
powershell -NoProfile -ExecutionPolicy Bypass -File ".cursor/skills/api-guides-to-spec/scripts/Convert-SpecMdToDocx.ps1" ``
  -MdPath "MCP/MeetingRoom_API_Spec.md" ``
  -OutDocx "MCP/MeetingRoom_API_Spec.docx"
``````

## $($jd)

``````
Task Progress:
- [ ] 1. $($ding) $($hj) $($zl) / ``*$($hj).md``
- [ ] 2. $($chou) $($md)$($dun)Method/Path$($dun)$($cs)$($dun)1.2 $($hc)$($yang)
- [ ] 3. $($xiechu) Spec.md$($lp)UTF-8 BOM$($dun)$($zw)$($rp)$($fm)+$($gb)+$($zw2) $($bj)
- [ ] 4. $($zhuan) .docx$($dun)$($yan) $($bg) / pagebreak / JSON $($hs)
- [ ] 5. $($chouyan)$($colon)$($dy1) $($fm)$($dun)$($dy2) $($gb)$($dun)1.5.x $($hc)JSON
``````

## Spec.md markers

See [reference.md](reference.md)$($period)

## $($sc)$($lp)$($ben)$($rp)

| $($wj) | $($sm2) |
|------|-------|
| ``MCP/MeetingRoom_API_Spec.md`` | UTF-8 **with BOM**$($lp)$($zw)$($nr)$($rp) |
| ``MCP/MeetingRoom_API_Spec.docx`` | OOXML |

$($gs) / logo / $($xddw) / $($xdr) $($moren) **$($kb)**$($period)
"@

# Fix accidental 4-backtick fences -> normal ``` 
$skill = $skill -replace '``````', '```'

# --- reference.md ---
$bq = C 0x7248,0x6B0A,0x8072,0x660E
$jz = C 0x8B39,0x88FD
$bc = C 0x7248,0x6B21
$fxrq = C 0x767C,0x884C,0x65E5,0x671F
$xdsm = C 0x4FEE,0x8A02,0x8AAA,0x660E
$cbfx = C 0x521D,0x7248,0x767C,0x884C
$jz2 = C 0x7F6E,0x4E2D
$dz = C 0x5927,0x5B57
$logo = 'Logo' + (C 0x5340)
$hxcr = C 0x5F8C,0x7E8C,0x518D,0x63D2
$hx = C 0x7136,0x5F8C
$dg = C 0x5927,0x7DB1
$zheng = C 0x6574,0x5408
$js = C 0x6280,0x8853,0x652F,0x63F4
$zc = C 0x7D44,0x6210,0x6982,0x5FF5
$jb = C 0x57FA,0x672C,0x53C3,0x6578,0x8AAA,0x660E
$ts = C 0x7279,0x6B8A,0x901A,0x7528
$yl = C 0x4E00,0x89BD,0x8868
$zy = C 0x6CE8,0x610F,0x4E8B,0x9805
$fl = C 0x9644,0x9304
$lyd = C 0x4F86,0x6E90,0x6A94
$cr = C 0x63D2,0x5165
$qian = C 0x4E4B,0x524D
$mg = C 0x6BCF,0x500B
$md2 = C 0x76EE,0x7684
$sq = C 0x6388,0x6B0A
$hl = C 0x6B04,0x4F4D
$xx = C 0x8A73,0x7D30,0x8AAA,0x660E
$bycs = C 0x5FC5,0x8981,0x53C3,0x6578
$ly = C 0x4F86,0x6E90
$dy = C 0x5C0D,0x61C9
$zy2 = C 0x4F5C,0x7528
$ms = C 0x6A21,0x5F0F
$hs2 = C 0x7070,0x8272
$dk = C 0x7B49,0x5BEC
$qx = C 0x5168,0x5F62
$bd = C 0x6A19,0x9EDE
$cz = C 0x5F9E,0x6307,0x5357,0x6A94,0x8B80,0x53D6
$wz = C 0x52FF,0x5728
$ps1 = '.ps1'
$hz2 = C 0x6F22,0x5B57
$nian = [char]0x5E74
$yue = [char]0x6708
$ri = [char]0x65E5
$apiYing = 'API' + (C 0x61C9,0x7528) + $sm
$xt = C 0x7CFB,0x7D71,0x2F,0x7522,0x54C1,0x540D
$fb = C 0x526F,0x6A19,0x984C
$jie3 = C 0x4ECB,0x9762,0x958B,0x767C
$dui = C 0x5C0D
$yingwen = C 0x61C9
$buqian = C 0x4E0D,0x8981,0x628A
$changshangming = C 0x5EE0,0x5546,0x540D
$xieru = C 0x5BEB,0x5165
$jineng = C 0x6280,0x80FD
$huo2 = C 0x6216
$jiao = C 0x8173,0x672C
$shenfen = C 0x8EAB,0x5206

$ref = @"
# $($zs) API $($sm) $($jie)$($lp)$($ty)$($rp)

$($hz) $($duo) $($hj) $($cheng) $($yi) $($sm) $($de=C 0x7684)$($de)$($ty)$($mb)$($period)
ESP $($lei) $($sc2) $($jin=$null)$($jin=C 0x50C5)$($jin)$($wei)$($ck)$($dun)$($buqian)$($changshangming)$($xieru)$($jineng)$($huo2)$($jiao)$($shenfen)$($period)

## $($dy1) $($fm)

$($jz2)$($dun)$($dz)$(' (~36pt)')$($colon)

1. $($logo) $($dash=$null)$($dash=' - ')$($dash)**$($kb)**$($lp)$($hxcr)$($rp)
2. $($xt)
3. $($fb)
4. $($apiYing)
5. $($jz3=C 0x8173,0x8A3B)$($jz3)$($colon)$($kb) $($gs) + ``$($jz)``

$($hx) $($fy)$($period)

## $($dy2) $($bq) + $($gb)

1. ``$($bq)``$($lp)$($jz2)$($rp)
2. $($bq)$($nr)$($lp)$($gs) $($kb)$($rp)
3. ``$($gb)``$($lp)$($jz2)$($dun)$($dz)$($rp)
4. $($bg)$($cs)$($colon)

| $($bc) | $($fxrq) | $($xdsm) | $($xddw) | $($xdr) |
|------|----------|----------|----------|----------|
| 0.1 | yyyy$($nian)MM$($yue)dd$($ri) | $($cbfx) | ($($kb)) | ($($kb)) |

$($hx) $($fy) $($jin=$null)$($jin=C 0x9032)$($jin)$($zw2)$($period)

## $($zw2) $($dg)

``````
1. $($zheng)API$($sm2)
  1.1 $($js)
  1.2 API$($zc)
  1.3 $($jb)
  1.4 $($ts)API$($cs)$($sm2)
  1.5 $($zheng)API$($sm2)
    1.5.x $($lp)$($mg) $($hj) $($yi)$($jie2=C 0x7BC0)$($jie2)$($rp)
  1.6 API$($hc)$($dai=C 0x4EE3,0x78BC)$($dai)$($yl)
2. $($zheng)$($jie3)$($zy)$($lp)$($kq) RoleSetting$($rp)
$($fl) $($colon) $($lyd)
``````

$($zai) $($mg) ``##`` $($zj) $($qian) $($cr) ``<!-- PAGE_BREAK -->``$($period)

## $($mg)-API $($jie2=C 0x7BC0)$($jie2) (1.5.x)

| $($qk) | $($hj) $($ly) |
|-------|----------------------|
| $($md2) | H1 $($xia=C 0x4E0B)$($xia) $($shou=C 0x9996)$($shou) $($duan=C 0x6BB5)$($duan) |
| $($mk) METHOD / URI / Content-Type / Controller / Action / $($sq) | Endpoint $($bg) |
| $($mk) $($cs) + $($bg) | ``$($bycs)`` $($xia) $($shou) $($zhang=C 0x5F35)$($zhang) $($bg) |
| $($mk) $($hc)JSON | ``1.2 $($tyhy)``$($colon) intro + ``**label**`` + ``json`` |
| $($mk) $($hc)$($hl) | $($gai=C 0x8A72)$($gai) $($jie2) $($nei=C 0x5167)$($nei) $($zi=C 0x6B04)$($zi)$($bg)$($lp)$($ruo=C 0x82E5,0x6709)$($ruo)$($rp) |
| $($mk) $($sq)$($shiBai) | $($ti=C 0x63D0)$($ti) 401/403 $($de2=C 0x7684)$($de2) $($duan) |
| $($mk) $($xx) | $($hj) $($wjming=C 0x6A94,0x540D)$($wjming) |

## Spec.md $($zhuan)$($qi=C 0x5668)$($qi) $($bj)

| Marker | $($zy2) |
|--------|------|
| ``<!-- COVER_PAGE -->`` | $($fm) $($ms) |
| ``<!-- COVER_LOGO -->`` | $($kb) logo |
| ``<!-- COVER_LINE1/2/3 -->text`` | $($fm) $($bt) |
| ``<!-- COVER_COMPANY -->...`` | $($kb) $($gs) + $($jz) |
| ``<!-- REV_PAGE -->`` | $($gb) $($ye=C 0x9801)$($ye) |
| ``<!-- REV_COPY_H/BODY -->`` / ``<!-- REV_H -->`` | $($bq) / $($gb) $($bt) |
| ``<!-- PAGE_BREAK -->`` | Word $($fy) |
| ````json`` fences | $($hs2) $($dk) $($duan) |
| Markdown $($bg) | ``<w:tbl>`` |

## $($bm=C 0x7DE8,0x78BC)$($bm)

``````powershell
function C([int[]]`$codes) { -join (`$codes | ForEach-Object { [char]`$_ }) }
# $($hj)$($colon)UTF-8$($period) Spec.md$($colon)UTF-8 BOM$($period)
`$utf8Bom = New-Object System.Text.UTF8Encoding `$true
[System.IO.File]::WriteAllText(`$path, `$text, `$utf8Bom)
``````

$($qx)$($bd)$($colon)codepoints ``0xFF1A`` / ``0xFF08`` / ``0xFF09`` / ``0x25CE``$($period)
$($hj)$($nr) $($cz) UTF-8 $($dun)$($wz) $($ps1) $($zhi)$($xie)$($hz2)$($period)
"@

$ref = $ref -replace '``````', '```'
# fix escaped `$ in encoding sample - we wanted literal $
$ref = $ref.Replace('`$', '$')

[System.IO.File]::WriteAllText((Join-Path $root 'SKILL.md'), $skill.TrimStart() + "`r`n", $enc)
[System.IO.File]::WriteAllText((Join-Path $root 'reference.md'), $ref.TrimStart() + "`r`n", $enc)

$t1 = [System.IO.File]::ReadAllText((Join-Path $root 'SKILL.md'), $enc)
$t2 = [System.IO.File]::ReadAllText((Join-Path $root 'reference.md'), $enc)
$b1 = [System.IO.File]::ReadAllBytes((Join-Path $root 'SKILL.md'))[0..2]
Write-Output ('SKILL bom=' + ($b1 -join ',') + ' cjk=' + ([regex]::Matches($t1, '[\u4e00-\u9fff]')).Count + ' has_hj=' + $t1.Contains($hj))
Write-Output ('reference cjk=' + ([regex]::Matches($t2, '[\u4e00-\u9fff]')).Count + ' has_fm=' + $t2.Contains($fm))
Write-Output 'ok'
