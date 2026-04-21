---
inclusion: manual
---

# 使用 moto 模擬 AWS 服務驗證 Lambda 在指定 Python 版本下的相容性

## 目的

在本地使用 moto（mock AWS 服務）搭配指定 Python 版本（如 3.14），驗證 Lambda handler 能否正常執行，不需要真實 AWS 資源。

---

## 環境建立

### 1. 使用 uv 建立指定 Python 版本的 venv

```bash
uv venv --python 3.14
source .venv/bin/activate
uv init  # 如果尚未初始化
```

### 2. pyproject.toml 設定 dev 依賴

根據 handler 用到的 AWS 服務，在 `[dependency-groups]` 加入對應的 moto extras：

```toml
[dependency-groups]
dev = [
    "boto3>=1.42.68",
    "botocore>=1.42.68",
    "moto[iot,dynamodb,s3,stepfunctions,cognitoidp,firehose]>=5.1.22",
    "pytest>=9.0.2",
]
```

只加你實際用到的服務，常見對應：
- IoT Core → `moto[iot]`
- DynamoDB → `moto[dynamodb]`
- S3 → `moto[s3]`
- Cognito → `moto[cognitoidp]`（注意：需要額外裝 `joserfc`）
- Firehose → `moto[firehose]`
- Step Functions → `moto[stepfunctions]`

### 3. 同步環境

```bash
uv sync --all-groups
```

---

## 注意事項與踩坑紀錄

### 注意事項 1：venv 隔離問題

每個專案有自己的 `.venv`。跑 pytest 時務必確認用的是當前專案的 venv，不是其他專案的。

錯誤徵兆：`ModuleNotFoundError` 但明明裝過了，traceback 路徑指向其他專案的 `.venv`。

解法：永遠用 `python -m pytest` 而非直接 `pytest`：

```bash
# 推薦做法
source .venv/bin/activate
python -m pytest test_handler.py -v

# 或不 activate，直接指定
.venv/bin/python -m pytest test_handler.py -v
```

### 注意事項 2：模組層級的 boto3 client 不在 mock scope 內

handler.py 通常在模組層級建立 boto3 client：

```python
firehose_client = boto3.client('firehose')  # 模組載入時就建立
```

這個 client 在 `@mock_aws` decorator 之外建立，mock 攔不到。

解法 A（推薦）：用 `unittest.mock.patch` 直接 mock 掉呼叫 AWS 的函式：

```python
from unittest.mock import patch

@patch("handler.firehose_put")
def test_shadow_logger(mock_fh):
    result = et35ShadowLogger(event, None)
    assert result["statusCode"] == 200
    mock_fh.assert_called_once()
```

解法 B：在測試裡重新指向 mock 環境的 client：

```python
import handler

@mock_aws
def test_something():
    handler.iot_client = boto3.client("iot", region_name="ap-northeast-1")
    handler.table = boto3.resource("dynamodb", region_name="ap-northeast-1").Table("xxx")
    # ... 測試邏輯
```

### 注意事項 3：handler 模組層級讀環境變數

如果 handler.py 在 import 時就讀 `os.environ`：

```python
STATE_MACHINE_ARN = os.environ["STEP_FUNCTION_ARN"]
```

必須在 `import handler` 之前設定環境變數：

```python
import os
os.environ["STEP_FUNCTION_ARN"] = "arn:aws:states:ap-northeast-1:123456789012:stateMachine:fake"
os.environ["CILENT_ID"] = "fake-client-id"
os.environ["USER_POOL_ID"] = "ap-northeast-1_FakePool"

# 之後才 import
import handler
```

### 注意事項 4：moto[cognitoidp] 需要 joserfc

moto 模擬 Cognito 時內部依賴 `joserfc` 來產生 JWT token。如果沒裝會報：

```
ModuleNotFoundError: No module named 'joserfc'
```

解法：

```bash
uv add --dev joserfc
```

注意 `joserfc` 和 `python-jose` 是不同套件：
- `python-jose`（`from jose import jwt`）→ 你的程式碼用的，放 `dependencies`
- `joserfc`（`from joserfc import jwk, jwt`）→ moto 內部用的，放 `dev` dependencies

### 注意事項 5：moto Firehose 的 S3 destination 限制

用 `ExtendedS3DestinationConfiguration` 建立 Firehose delivery stream 時，moto 會嘗試寫入 S3 bucket。如果 bucket 不存在會報：

```
Firehose PutRecord(Batch to S3 destination failed
```

解法（推薦）：不要 mock Firehose 本身，直接 `@patch("handler.firehose_put")` mock 掉寫入函式。測試重點是 handler 邏輯，不是 Firehose。

### 注意事項 6：IoT Thing Type 必須先建立

如果 handler 在 `create_thing()` 時指定了 `thingTypeName`：

```python
iot_client.create_thing(thingName=name, thingTypeName="ET35", ...)
```

測試裡必須先建立該 Thing Type，否則 moto 會報 `The specified resource does not exist`：

```python
iot = boto3.client("iot", region_name="ap-northeast-1")
iot.create_thing_type(thingTypeName="ET35")
```

### 注意事項 7：Python 版本升級後套件版本可能需要跟著升

舊版套件可能不支援新 Python。用 uv 安裝時會自動解析相容版本，但 `requirements.in` 裡鎖的舊版本可能裝不上。

常見需要升版的套件（以 3.14 為例）：
- `cffi` 1.17.x → 需升到 2.0+
- `pycparser` 2.22 → 需升到 3.00+
- `urllib3` 1.26.x → 會升到 2.x（breaking change，但 botocore 已適配）
- `pyasn1` 0.4.x → 需升到 0.6+

驗證方式：在目標 Python 版本的 venv 裡跑：

```python
python -c "
import boto3, botocore, cffi, ecdsa, jmespath, pyasn1
import pycparser, dateutil, jose, rsa, s3transfer, six, urllib3
print('All imports OK')
"
```

---

## 測試檔案範本

```python
import json
import os
import boto3
from unittest.mock import patch
from moto import mock_aws

# 環境變數必須在 import handler 之前設定
os.environ["MY_ENV_VAR"] = "fake-value"

from handler import my_function


@mock_aws
def test_with_mock_aws():
    """需要 mock AWS 資源的測試"""
    # 1. 建立 mock 資源
    client = boto3.client("iot", region_name="ap-northeast-1")
    client.create_thing_type(thingTypeName="MyType")
    client.create_policy(policyName="my-policy", policyDocument='{}')

    # 2. 重新指向 mock client（如果 handler 在模組層級建立 client）
    import handler
    handler.iot_client = boto3.client("iot", region_name="ap-northeast-1")

    # 3. 執行測試
    result = handler.my_function(event, None)
    assert result["statusCode"] == 200


@patch("handler.external_service_call")
def test_with_patch(mock_call):
    """mock 掉外部呼叫的測試"""
    result = my_function(event, None)
    assert result["statusCode"] == 200
    mock_call.assert_called_once()
```

---

## 執行測試

```bash
# 確認 Python 版本
python --version

# 跑測試
python -m pytest test_handler.py -v

# 跑測試並顯示 print 輸出（debug 用）
python -m pytest test_handler.py -v -s

# 只跑單一測試
python -m pytest test_handler.py::test_create_thing_success -v
```
