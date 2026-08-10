# 階段 0：確認／導入 Speckit 環境（前置）

**在進入階段 1 之前必須完成。** 沒有可用的 Speckit 環境就不得繼續後續階段。

## 0.1 確認專案根目錄

- 確認目前工作目錄為目標專案根目錄（含原始碼與之後會寫入的 `.specify/`）。
- 若不在專案內，先請使用者指定路徑，必要時先 `move_agent_to_root` 再繼續。

## 0.2 檢查是否已有 Speckit

檢查下列跡象（有愈多愈完整；至少需有 `.specify/`）：

| 檢查項 | 路徑／跡象 |
|--------|------------|
| Speckit 基礎結構 | `.specify/`（templates、scripts、memory 等） |
| Manifest | `.specify/integrations/speckit.manifest.json` |
| Constitution 檔 | `.specify/memory/constitution.md` |
| Agent 指令 | `/speckit.*` prompts／skills（依整合而定，如 `.cursor/`、`.github/prompts/`、`.kiro/prompts/`） |

判定：

- **已就緒**：存在 `.specify/`，且可執行 `/speckit.constitution`（或對應 skill）→ 告知使用者後進入階段 1。
- **部分存在**：有殘缺目錄或缺 CLI → 修復後再進入階段 1（勿直接覆寫使用者已改過的 constitution）。
- **未導入**：缺少 `.specify/` → 執行 0.3 協助導入。

## 0.3 協助導入（環境不存在時）

1. **確認 CLI**
   - 執行 `specify --version`（或 `specify version`）。
   - 若無 CLI：協助安裝 [Spec Kit](https://github.com/github/spec-kit)（需 [uv](https://docs.astral.sh/uv/)）：

     ```bash
     uv tool install specify-cli --from git+https://github.com/github/spec-kit.git
     ```

     若需鎖定版本，改用官方 release tag（例如 `@vX.Y.Z`）。

2. **詢問整合目標**（未指定時先問）
   - Cursor / Copilot / Claude / 其他
   - 本機既有慣例範例：`specify init . --ai copilot`
   - 新版參數也可能是 `--integration <agent>`；以目前 `specify init --help` 為準。

3. **在專案根目錄初始化**

   ```bash
   # 既有專案（目前目錄）
   specify init . --ai <agent>
   # 或（依 CLI 版本）
   specify init --here --integration <agent>
   ```

4. **驗證導入成功**
   - `.specify/` 已建立
   - constitution 模板或 `.specify/memory/constitution.md` 存在（可為模板，內容由階段 1 填寫）
   - Agent 可使用 `/speckit.constitution`、`/speckit.specify`、`/speckit.plan`、`/speckit.tasks`、`/speckit.implement` 等指令

5. **導入完成後**才進入階段 1。

## 0.4 注意

- 導入前先告知將寫入哪些目錄，取得使用者同意再執行。
- 勿用 `--force` 覆蓋既有 Speckit／constitution，除非使用者明確要求。
- Windows 環境優先使用專案內已提供的腳本類型（bash / ps）；初始化時若 CLI 詢問，依專案現況選擇。
