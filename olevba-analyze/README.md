# olevba-analyze

## 用途

用 oletools 分析 Office 檔是否含 VBA 巨集，以及巨集是否為危險植入內容。

支援副檔名：`.doc` / `.docm` / `.xls` / `.xlsm` / `.ppt` / `.pptm` 等 OLE / 巨集格式。

## 在 Cursor 中使用

把檔案路徑貼給 agent 即可，例如：

```text
分析 /mnt/d/data/legal260827v1.doc
```

agent 會：

1. 必要時用 `pipx` 安裝 oletools（不要用 `python3 -m pip`）
2. 解析路徑（目錄漏寫 `/` 時改用檔名搜尋；忽略 Word 鎖定檔 `~$*`）
3. 執行 `olevba`、`oleid`、`mraptor`、`oleobj`
4. 給出三種結論之一

## 結論對照

| 結論 | 意義 |
|------|------|
| **No macros found** | 無巨集 |
| **有巨集，非危險內容** | 有 VBA，但多為空程序或 ActiveX 表單事件骨架（例如空的 `TextBox1_Change`），不是惡意植入 |
| **可能被植入危險內容** | 出現可疑關鍵字、mraptor `W`/`X`、下載／執行／寫檔行為，或遠端／嵌入惡意物件 |

## 手動執行

```bash
bash /scripts/analyze.sh "<檔案路徑>"
```

需要能讀取檔案的權限。環境需有 `pipx` 或已安裝 `olevba`。

## 檔案

| 檔案 | 說明 |
|------|------|
| `SKILL.md` | agent 指令（UTF-8） |
| `scripts/analyze.sh` | 安裝檢查、路徑解析、呼叫 oletools |
| `README.md` | 本說明 |

## 編碼

檔案應為 **UTF-8、LF、無 BOM**。
