---
name: mcp-api-from-scratch
description: >-
  Confirms or installs Speckit, then builds AI-facing APIs via Speckit and turns
  call guides into a Node.js MCP server (stdio, optional SSE). Use when starting
  MCP from zero, checking Speckit setup, Speckit API setup, writing API call
  guides, or generating MCP from existing system APIs.
disable-model-invocation: true
---

# 從 0 開始 MCP（Speckit → API → 呼叫指南 → MCP）

語言一律使用**繁體中文**。依序執行下列階段；未完成前一階段不得跳過。

## 進度清單

```
Task Progress:
- [ ] 0. 確認／導入 Speckit 環境（前置，必做）
- [ ] 1. Constitution（技術棧與通用格式）
- [ ] 2. 架構長期記憶（rules）
- [ ] 3. API 開發規範（Speckit + rules）
- [ ] 4. 新增 API
- [ ] 5. API 呼叫指南（md）
- [ ] 6. MCP 伺服器（Node.js stdio）
- [ ] 7. 編譯 dist
- [ ] 8. 依 Base URL 以 MCP 驗證（必要時才啟動本地站台）
```

---

## 階段 0：確認／導入 Speckit 環境（前置）

**進入階段 1 前必須完成。** 檢查專案是否已有 Speckit；沒有則協助導入。細節見 [speckit-setup.md](speckit-setup.md)。

---

## 階段 1：Constitution

分析全系統技術棧、後端呼叫與回傳通用格式，儲存為 Speckit constitution。

輸出：寫入 Speckit 的 constitution 細節。

---

## 階段 2：架構長期記憶

分析系統架構，包含：

- 專案結構
- 資料庫架構
- 控制器設計
- 共用工具類別
- 開發慣例

輸出：寫為 rules，必要時取用。

---

## 階段 3：API 開發規範

建立並儲存為長期記憶（Speckit 各階段細節 + rules）。

### 硬性約束（不可違反）

1. **所有新建程式碼皆須獨立儲存於新檔案，不可汙染既有內容。**
2. **使用者驗證、紀錄查詢，都須使用既有函式。**
3. **資料庫規格也不可變更**；僅另外建立 API 接口，並使用原邏輯組建。
4. **ViewModel 如果有找到既有可用的則沿用。**
5. **如果發現共通架構程式有誤或效率不佳，不可直接修改，應詢問是否調整。**

### 理想運作

- Speckit：完整細節
- Rule：精簡，並指向 constitution 的核心規範

---

## 階段 4：新增 API

依使用者需求新增 API。提示範本：

> 新增 API，提供……功能，可指定……作為參數，輸出……

**範例：**

新增 API，查詢指定時段 + 指定會議室，是否有人借用，從幾點借到幾點、誰借的、聯絡分機、什麼會議名稱。查詢前會先確認查詢者是否有查詢該會議室借用紀錄的資格。

實作時嚴格遵守階段 3 約束。

---

## 階段 5：API 呼叫指南

為 API 建立使用說明（呼叫指南）：

- 每個功能各自獨立一份 md
- 放到使用者指定路徑（若未指定則先詢問）

### 每份指南必含章節

| 章節 | 內容 |
|------|------|
| 基本資訊 | Base URL、通用回應格式 |
| 端點說明 | Method、path、前置依賴 |
| 必要參數 | 參數名、類型、說明；關鍵參數會產生不同模式時，說明各模式使用參數 |
| 回應欄位 | 欄位、說明 |
| 限制規則 | 如 All-or-Nothing、執行上限 |
| 使用流程 | 步驟說明 |
| 注意事項 | 易錯點與限制 |

必須先詢問使用者 Base URL；未提供時才採用預設 `http://localhost:5000`。

---

## 階段 6：撰寫 MCP 伺服器

分析所有呼叫指南 md，以 **Node.js** 撰寫 MCP 伺服器：

- 傳輸：**stdio** 模式
- 保留日後改用 **SSE** 的擴充空間
- 原始碼放在與呼叫指南**同一資料夾**

必須先詢問使用者 port（SSE 或其他 HTTP 用途預留）；未提供時才採用預設 `8895`。

---

## 階段 7：編譯產出

完成後編譯為多檔 tsc 輸出：

- `dist/*.mjs`
- 含 dependencies 的 `dist/package.json`

方便後續提供給其他模型利用。

---

## 階段 8：驗證

先向使用者索取驗證參數（不可臆造）。**先依 Base URL 分流**：非本地直接跑 MCP；僅本地或遠端 MCP 失敗時，才啟動本地站台並改以本地 Base URL 重測。

細節（分流判定、執行順序、本地備援注意）見 [mcp-verify.md](mcp-verify.md)。進入本階段時再讀取該檔。

---

## 決策與詢問時機

| 情況 | 行為 |
|------|------|
| 專案無 Speckit／缺 CLI／整合不明 | 依 [speckit-setup.md](speckit-setup.md) 處理；未完成不得進階段 1 |
| Base URL（階段 5）、port（階段 6） | 先詢問；未提供才用預設（`http://localhost:5000` / `8895`） |
| 階段 8 驗證 | 摘要見上；完整步驟讀 [mcp-verify.md](mcp-verify.md)。非本地先 MCP；僅本地或失敗才開本地站台 |
| 缺少輸出路徑、API 需求細節、驗證參數 | 先詢問使用者 |
| 共通架構有誤或效率不佳 | 詢問是否調整，不可直接改 |
| 既有函式 / ViewModel 可用 | 必須沿用 |
| 需改 DB schema | 拒絕；改以既有邏輯組新 API |
