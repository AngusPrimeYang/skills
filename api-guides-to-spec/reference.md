# 正式 API 說明文件結構（通用）

匯整多份呼叫指南成一份說明文件的通用模板。
ESP 類手冊僅供參考、不要把廠商名寫入技能或腳本身分。

## 第一頁 封面

置中、大字 (~36pt)：

1. Logo 區 — **留空**（後續再插）
2. 系統/產品名
3. 副標題
4. API應用說明文件
5. 腳註：留空公司 + ``謹製``

然後分頁。

## 第二頁 版權聲明 + 改版歷程

1. ``版權聲明``（置中）
2. 版權內容（公司留空）
3. ``改版歷程``（置中、大字）
4. 表格欄位：

| 版次 | 發行日期 | 修訂說明 | 修訂單位 | 修訂人員 |
|------|----------|----------|----------|----------|
| 0.1 | yyyy年MM月dd日 | 初版發行 | (留空) | (留空) |

然後分頁進入正文。

## 正文大綱

```
1. 整合API說明
  1.1 技術支援
  1.2 API組成概念
  1.3 基本參數說明
  1.4 特殊通用API參數說明
  1.5 整合API說明
    1.5.x （每個呼叫指南一節）
  1.6 API回傳代碼一覽表
2. 整合介面開發注意事項（可選 RoleSetting）
附錄：來源檔
```

在每個 ``##`` 章節之前插入 ``<!-- PAGE_BREAK -->``。

## 每個 API 節（1.5.x）

| 區塊 | 呼叫指南來源 |
|-------|----------------------|
| 目的 | H1 下首段 |
| ◎ METHOD / URI / Content-Type / Controller / Action / 授權 | Endpoint 表格 |
| ◎ 參數 + 表格 | ``必要參數`` 下首張表格 |
| ◎ 回傳JSON | ``1.2 通用回應格式``： intro + ``**label**`` + ``json`` |
| ◎ 回傳欄位 | 該節內欄位表格（若有） |
| ◎ 授權失敗 | 提及 401/403 的段落 |
| ◎ 詳細說明 | 呼叫指南檔名 |

## Spec.md 轉換器標記

| Marker | 作用 |
|--------|------|
| ``<!-- COVER_PAGE -->`` | 封面模式 |
| ``<!-- COVER_LOGO -->`` | 留空 logo |
| ``<!-- COVER_LINE1/2/3 -->text`` | 封面標題 |
| ``<!-- COVER_COMPANY -->...`` | 留空公司 + 謹製 |
| ``<!-- REV_PAGE -->`` | 改版歷程頁 |
| ``<!-- REV_COPY_H/BODY -->`` / ``<!-- REV_H -->`` | 版權聲明/改版歷程標題 |
| ``<!-- PAGE_BREAK -->`` | Word 分頁 |
| `` ```json `` fences | 灰色等寬段落 |
| Markdown 表格 | ``<w:tbl>`` |

## 編碼

```powershell
function C([int[]]$codes) { -join ($codes | ForEach-Object { [char]$_ }) }
# 呼叫指南：UTF-8。 Spec.md：UTF-8 BOM。
$utf8Bom = New-Object System.Text.UTF8Encoding $true
[System.IO.File]::WriteAllText($path, $text, $utf8Bom)
```

全形標點用 codepoints（``0xFF1A`` / ``0xFF08`` / ``0xFF09`` / ``0x25CE``）。
呼叫指南內容從指南檔以 UTF-8 讀取、勿在 ``.ps1`` 直接寫入漢字。

## Labels（多語系）

固定外框文案在 `labels/labels.<Locale>.json`（UTF-8 BOM）。
`.ps1` 不再內嵌漢字；`-Locale zh-TW|en|...` 或 `-LabelsPath` 指定檔案。
`guide.commonResponse` / `guide.requiredParams` / `guideFileSuffix` 須與來源呼叫指南標題一致（用來擷取章節），即使 Spec 外框是英文也可維持中文。
新增語系：複製 `labels.zh-TW.json` → `labels.<id>.json` 後翻譯 `cover` / `revision` / `chapters` / `api` / `punct`。
