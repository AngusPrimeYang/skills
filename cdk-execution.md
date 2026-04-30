---
inclusion: fileMatch
fileMatchPattern: "cdk*"
---

# CDK 執行規則

執行 CDK 相關指令（`cdk synth`、`cdk diff`、`cdk deploy`、`cdk_deploy_agent.py`）時，這些指令耗時較長，不需要等待結果。

## 規則

- 使用 `controlBashProcess` 的 `start` action 啟動指令，不要用 `executeBash`
- 啟動後立即回覆使用者「已執行」，不需要輪詢或等待輸出
- 等使用者回報結果後再進行下一步動作
- 如果使用者貼回執行結果，根據結果判斷後續操作

## 適用指令

- `.venv/bin/python cdk_deploy_agent.py ...`
- `cdk synth ...`
- `cdk diff ...`
- `cdk deploy ...`

## 範例流程

1. 使用 `controlBashProcess` start 啟動指令
2. 回覆：「已執行，完成後請回報結果。」
3. 使用者貼回結果 → 根據結果繼續處理
