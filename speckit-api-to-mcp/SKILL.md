---
name: speckit-api-to-mcp
description: >-
  Confirms or installs Speckit, audits existing constitution/rules, adds
  AI-facing APIs under hard constraints, then builds call guides and a Node.js
  MCP server (stdio, optional SSE). Use when running Speckit-to-API-to-MCP
  pipeline, checking Speckit setup, writing API call guides, or generating MCP
  from system APIs.
disable-model-invocation: true
---

# Speckit → API → 呼叫指南 → MCP

語言一律使用**繁體中文**。依序執行下列階段；未完成前一階段不得跳過。

## 進度清單

```
Task Progress:
- [ ] 0. 確認／導入 Speckit 環境（前置，必做）
- [ ] 1. Constitution（確認／補齊，勿無故覆寫）
- [ ] 2. 架構長期記憶 rules（確認／補齊，勿冗餘）
- [ ] 3. API 開發規範（執行約束＋確認／補齊長期記憶）
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

## 階段 1～3：基礎產物（先審計）

階段 1～3 **必須先審計既有 constitution／rules**，已涵蓋則跳過寫入，避免換專案或重跑時冗餘。

摘要：先讀 → 已涵蓋則完成 → 部分則只補缺口（大改先問）→ 沒有才新建。禁止無故整份覆寫。

完整判定表與階段 3 執行約束見 [foundation-audit.md](foundation-audit.md)。**進入階段 1 時讀取該檔**，並依序完成 1→2→3。

| 階段 | 目標（審計後） |
|------|----------------|
| 1. Constitution | 技術棧與後端呼叫／回傳通用格式在 Speckit constitution 就緒 |
| 2. 架構 rules | 專案結構、DB、控制器、共用工具、慣例等精簡 rules 就緒 |
| 3. API 規範 | 本 skill 五條執行約束生效；長期記憶僅在缺漏時補齊（Speckit 詳、Rule 精並指向 constitution） |

---

## 階段 4：新增 API

依使用者需求新增 API。提示範本：

> 新增 API，提供……功能，可指定……作為參數，輸出……

**範例：**

新增 API，查詢指定時段 + 指定會議室，是否有人借用，從幾點借到幾點、誰借的、聯絡分機、什麼會議名稱。查詢前會先確認查詢者是否有查詢該會議室借用紀錄的資格。

實作時嚴格遵守階段 3 約束（見 [foundation-audit.md](foundation-audit.md)）。

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

必須先詢問使用者 Base URL；未提供時才依**專案設定**推斷本地 URL（`launchSettings.json`／啟動 skill 等，勿假設固定 port）。

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
| 階段 1～3 既有 constitution／rules | 依 [foundation-audit.md](foundation-audit.md)：已涵蓋則跳過；部分則只補；禁止無故覆寫／冗餘 |
| 階段 3 約束與專案性質不合 | 先詢問是否調整約束，再進階段 4 |
| Base URL（階段 5）、port（階段 6） | 先詢問；Base URL 未提供時依專案設定推斷本地 URL；SSE port 未提供才用 `8895` |
| 階段 8 驗證 | 摘要見上；完整步驟讀 [mcp-verify.md](mcp-verify.md)。非本地先 MCP；僅本地或失敗才開本地站台 |
| 缺少輸出路徑、API 需求細節、驗證參數 | 先詢問使用者 |
| 共通架構有誤或效率不佳 | 詢問是否調整，不可直接改 |
| 既有函式 / ViewModel 可用 | 必須沿用 |
| 需改 DB schema | 拒絕；改以既有邏輯組新 API |
