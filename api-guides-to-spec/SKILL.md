---
name: api-guides-to-spec
description: >-
  匯整 API 呼叫指南.md 為正式中文 API 規格說明文件
  （封面第一頁、改版歷程、章節分頁、◎ 區塊、實際 Word 表格、回傳JSON 樣本）。
  輸出 UTF-8 BOM .md 與 OOXML .docx（不用 Word COM）。
  何時使用：匯整呼叫指南、匯出 API 說明文件、guides to docx/md、
  重新產生 MeetingRoom_API_Spec，或由多份呼叫指南產生正式 API 規格說明文件。
---

# API 呼叫指南 → 正式 API 說明文件 (md + docx)

## 何時使用

- 匯整多份 `*呼叫指南.md`（可選 `RoleSetting.md`）成一份 API 說明文件
- 需要 **封面 + 改版歷程 + 章節分頁 + ◎ 區塊 + 實際 表格 + 回傳JSON**
- 輸出 **Markdown（UTF-8 BOM、中文內容）** 與 **Word（.docx）**

結構為通用規格 API 說明文件模板（不限特定廠商）。可參考：ESP類 API 手冊。

## 不要

| 做法 | 問題 | 改用 |
|----------|---------|-------------|
| Word COM | 掛住 / 存檔失敗 | OOXML zip `.docx` |
| 在 `.ps1` 直接寫入中文 | 變成 `?` | `[char]0xXXXX` / `C` 輔助、從呼叫指南讀 UTF-8 |
| MD 管線當純文字 貼入 Word | 不是表格 | 輸出 `<w:tbl>` |
| 跳過 `1.2 通用回應格式` | 缺少 回傳JSON | 解析 `**label**` + `json` |
| MD 無 BOM | 工具顯示亂碼 | UTF-8 含 BOM |

## 推薦命令

Windows PowerShell (`required_permissions: ["all"]`):

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File ".cursor/skills/api-guides-to-spec/scripts/Convert-GuidesToApiSpec.ps1" `
  -GuideDir "MCP" `
  -OutDir "MCP" `
  -OutBaseName "MeetingRoom_API_Spec"
```

`-Locale`（預設 `zh-TW`）載入 `labels/labels.<Locale>.json`。新增語系：複製 `labels.zh-TW.json` 為 `labels.<id>.json` 並翻譯。亦可 `-LabelsPath` / `-SystemName` / `-SystemSub`。

英文外框範例：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File ".cursor/skills/api-guides-to-spec/scripts/Convert-GuidesToApiSpec.ps1" `
  -GuideDir "MCP" -OutDir "MCP" -OutBaseName "MeetingRoom_API_Spec_en" -Locale "en"
```

若 Spec.md 已存在、僅需 docx：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File ".cursor/skills/api-guides-to-spec/scripts/Convert-SpecMdToDocx.ps1" `
  -MdPath "MCP/MeetingRoom_API_Spec.md" `
  -OutDocx "MCP/MeetingRoom_API_Spec.docx"
```

## 進度

```
Task Progress:
- [ ] 1. 定位 呼叫指南 資料夾 / `*呼叫指南.md`
- [ ] 2. 抽取 目的、Method/Path、參數、1.2 回傳樣本
- [ ] 3. 寫出 Spec.md（UTF-8 BOM、中文）封面+改版歷程+正文 標記
- [ ] 4. 轉換 .docx、驗證 表格 / pagebreak / JSON 灰底
- [ ] 5. 抽查：第一頁 封面、第二頁 改版歷程、1.5.x 回傳JSON
```

## Spec.md markers

See [reference.md](reference.md)。

## 輸出（本倉庫）

| 檔案 | 說明 |
|------|-------|
| `MCP/MeetingRoom_API_Spec.md` | UTF-8 **with BOM**（中文內容） |
| `MCP/MeetingRoom_API_Spec.docx` | OOXML |

公司 / logo / 修訂單位 / 修訂人員 預設 **留空**。
