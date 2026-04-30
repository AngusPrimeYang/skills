---
inclusion: always
---

# Python 虛擬環境規則

執行 Python 相關指令時，必須優先使用專案目錄中的 `.venv` 虛擬環境。

## 規則

- 執行任何 Python 或 pip 指令前，先用 `cwd` 切到目標專案目錄
- 進入專案目錄後，先執行 `source .venv/bin/activate` 啟用虛擬環境
- 啟用 venv 後再執行後續指令（pytest、python、uv pip install 等）
- 不要使用系統全域的 Python 執行專案程式碼
- 每次執行 bash 指令時都要確保 cwd 指向正確的專案目錄

## 執行流程

1. 設定 `cwd` 為目標專案目錄（例如 `et35-iot-stack`）
2. 直接使用 `.venv/bin/` 下的執行檔，不需要 source activate

## 範例

```bash
# 正確 — 直接使用 venv 內的執行檔，cwd 指向專案目錄
.venv/bin/python handler.py
.venv/bin/pytest
.venv/bin/python -m pytest

# 安裝套件時（uv 不需要 venv activate）
uv pip install -r requirements.txt

# 錯誤 — 未指定 venv 路徑直接執行
python handler.py
pytest
```
