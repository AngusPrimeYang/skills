---
name: olevba-analyze
description: >-
  Analyzes Office files for VBA macros and implanted dangerous content using
  oletools (olevba, oleid, mraptor, oleobj). Use when the user provides a
  .doc/.docm/.xls/.xlsm/.ppt/.pptm path, asks to run olevba, install oletools,
  check 巨集 / macros, or confirm "No macros found" vs 危險內容.
---

# olevba 巨集分析

User provides an Office file path. Install oletools if needed, run analysis, and report whether the result is **No macros found** or whether dangerous content was implanted.

Requires Shell `required_permissions: ["all"]` (files often live on `/mnt/d`).

## Input

- Required: file path (absolute preferred).
- If the path is missing a directory separator (folder concatenated with filename), resolve by basename search. Ignore Word lock files (`~$*`).
- If still not found, list the parent directory and stop.

## Run

```bash
bash /scripts/analyze.sh "<file-path>"
```

If `olevba` is missing, the script installs oletools via `pipx`. Do not use `python3 -m pip` (this environment has no `pip` module).

## Verdict

Read the script output and conclude **one** of:

| Condition | Verdict |
|-----------|---------|
| olevba reports no VBA / `No macros found` | **No macros found** -- 無巨集 |
| VBA present, bodies empty or form-control stubs only (`TextBox*_Change`, empty `Sub`/`Function`), oleid says no suspicious keywords, mraptor `Macro OK` with flags `A--` or `---` only, oleobj has no remote/embedded payloads | **有巨集，非危險內容** -- typical leftover ActiveX/form event skeleton |
| olevba `Suspicious` / `IOC`, or mraptor `W`/`X`, or Shell / CreateObject / URLDownload / WScript / PowerShell / write-file / download behavior, or oleobj remote objects | **可能被植入危險內容** -- quote the exact VBA / flags / keywords |

Empty `Private Sub TextBox1_Change()` / `End Sub` with AutoExec is **not** malware; Word auto-generates it when an ActiveX TextBox exists.

## Report to user

Use Traditional Chinese. Lead with the verdict.

```markdown
**結論：No macros found** 或 **有巨集，非危險內容** 或 **可能被植入危險內容**

- 路徑：（resolved path if different from input）
- 檔案類型：
- olevba：關鍵輸出（巨集程式或 No macros found）
- oleid / mraptor / oleobj：一行摘要
```

Do not dump full `oledir` unless it changes the verdict. Suggest cleanup (remove ActiveX control, or save as macro-free `.docx`) only when macros are harmless leftovers.
