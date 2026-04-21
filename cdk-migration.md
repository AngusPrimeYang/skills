# Skill: 舊 Stack → iot-core-stack 零中斷遷移

本 skill 描述如何將既有 AWS 帳號中的舊 CloudFormation Stack（Serverless Framework 或獨立 CDK Stack）
遷移至 `iot-core-stack` 統一 CDK App，過程中零中斷、零資源重建。

所有資源命名透過 `product_name` 和 `deployment_mode` 參數化，
Lambda 原始碼已整合在 `iot-core-stack/lambdas/` 目錄內。

---

## 核心變數

| 變數 | 說明 | 範例 |
|------|------|------|
| `product_name` | 產品代號，小寫，透過 `-c product_name=xxx` 傳入 | `gm50`, `ej20`, `em25` |
| `deployment_mode` | 環境名稱，透過 `-c deployment_mode=xxx` 傳入 | `dev`, `prod`, `staging` |
| `PROFILE` | AWS CLI profile | `PC00001_GM50_PROD` |
| `REGION` | AWS region | `ap-northeast-1` |

Stack 名稱前綴自動由 product_name 首字母大寫產生（`gm50` → `Gm50`，`ej20` → `Ej20`）。

---

## 適用場景

- 帳號中已有舊 Serverless Framework 或獨立 CDK Stack 管理的 IoT 資源
- 目標是將這些資源整合到 `iot-core-stack` 的統一 CDK App
- 需要零中斷遷移（不刪除重建任何 AWS 資源）

---

## 前置條件

1. AWS CLI 已設定好目標帳號的 profile
2. 目標帳號已完成 CDK bootstrap
3. `iot-core-stack` 環境已就緒：
   ```bash
   cd iot-core-stack
   source .venv/bin/activate
   uv pip install -r requirements.txt
   ```
4. 已確認舊 Stack 中的資源名稱與 `iot-core-stack` 產生的名稱一致
   （如不一致，需先調整 Stack 程式碼中的命名）

---

## 遷移流程總覽

```
Step 0: 舊 Stack 全部資源 DeletionPolicy → Retain
Step 1: 刪除舊 Stack（資源因 Retain 保留在 AWS 上）
Step 1.5: 驗證資源仍存在
Step 2: cdk import 匯入資源到新 Stack
Step 2.5: cdk diff 驗證
Step 2.7: 補充 import（cdk import 遺漏的資源）
Step 3: cdk deploy 更新資源
Step 3.5: 強制更新 Lambda code/runtime + 清理舊 Permission
Step 4: 最終驗證
```

---

## Step 0: 設定 DeletionPolicy=Retain

對每個舊 Stack 執行，確保刪除 Stack 時資源不會被一起刪除：

```bash
set_all_retain() {
    local stack_name=$1
    aws cloudformation get-template --stack-name "$stack_name" \
        --profile $PROFILE --region $REGION --output json \
    | python3 -c "
import sys, json
data = json.load(sys.stdin)
t = data['TemplateBody']
for name, res in t['Resources'].items():
    res['DeletionPolicy'] = 'Retain'
    res['UpdateReplacePolicy'] = 'Retain'
print(json.dumps(t))
" > /tmp/${stack_name}-retain.json

    aws cloudformation update-stack \
        --stack-name "$stack_name" \
        --template-body "file:///tmp/${stack_name}-retain.json" \
        --capabilities CAPABILITY_NAMED_IAM \
        --profile $PROFILE --region $REGION || true

    aws cloudformation wait stack-update-complete \
        --stack-name "$stack_name" --profile $PROFILE --region $REGION
}
```

---

## Step 1: 刪除舊 Stack

對每個舊 Stack：

1. 關閉 termination protection（Serverless Framework 的 Stack 通常有）：
   ```bash
   aws cloudformation update-termination-protection \
       --no-enable-termination-protection \
       --stack-name <stack-name> --profile $PROFILE --region $REGION
   ```
2. 刪除 Stack：
   ```bash
   aws cloudformation delete-stack --stack-name <stack-name> --profile $PROFILE --region $REGION
   aws cloudformation wait stack-delete-complete --stack-name <stack-name> --profile $PROFILE --region $REGION
   ```

---

## Step 1.5: 驗證資源仍存在

逐一檢查所有資源類型：
- DynamoDB: `aws dynamodb describe-table --table-name <name>`
- S3: `aws s3api head-bucket --bucket <name>`
- Firehose: `aws firehose describe-delivery-stream --delivery-stream-name <name>`
- Lambda: `aws lambda get-function --function-name <name>`
- Step Functions: `aws stepfunctions list-state-machines`
- Cognito: `aws cognito-idp list-user-pools --max-results 20`
- API Gateway: `aws apigateway get-rest-apis`

---

## Step 2: cdk import 匯入資源

### 準備 resource-mapping JSON

先 synth 取得 CDK Logical ID：
```bash
cd iot-core-stack
source .venv/bin/activate
cdk synth --all -c product_name={product} -c deployment_mode={env} --quiet
```

從 `cdk.out/{StackPrefix}*.template.json` 中取得每個資源的 Logical ID，
與 AWS 上的實際資源名稱對應，產生 resource-mapping JSON：

```json
{
  "<CDK_LogicalId>": {
    "<IdentifierKey>": "<實際資源名稱>"
  }
}
```

常見 IdentifierKey：

| 資源類型 | IdentifierKey |
|---------|--------------|
| DynamoDB Table | `TableName` |
| S3 Bucket | `BucketName` |
| Lambda Function | `FunctionName` |
| IAM Role | `RoleName` |
| Firehose Stream | `DeliveryStreamName` |
| IoT Rule | `RuleName` |
| Log Group | `LogGroupName` |
| Cognito User Pool | `UserPoolId` |
| API Gateway | `RestApiId` |

### 執行 cdk import

```bash
cdk import {StackPrefix}ShadowLogger \
    -c product_name={product} -c deployment_mode={env} \
    --profile $PROFILE --resource-mapping resource-mapping-{env}-shadow-logger.json --force
```

### 特殊處理：CfnStateMachine（Step Functions）

`cdk import` 對 L1 `CfnStateMachine` 有 bug（送 `StateMachineArn` 但 CloudFormation 期望 `Arn`），
需改用 CloudFormation CLI 直接 import：

1. `cdk synth {StackPrefix}IotCertDelete` 產生 template
2. 用 Python 移除 `CDKMetadata`、`Conditions`、`Outputs`，加上 `DeletionPolicy: Retain`
3. 準備 `resources-to-import` JSON（Step Function 用 `Arn` 作為 identifier）
4. `aws cloudformation create-change-set --change-set-type IMPORT`
5. `aws cloudformation wait change-set-create-complete`
6. `aws cloudformation execute-change-set`
7. `aws cloudformation wait stack-import-complete`
8. 再用 `cdk deploy` 補回 `CfnOutput` 和 `CDKMetadata`

### 特殊處理：API Gateway 子資源

`cdk import` 無法處理 API Gateway 的 Resource、Method、Deployment、Stage。
需用 supplement import（取得現有 Stack template，合併 CDK synth 的新資源後用 change-set import）。

---

## Step 2.5: cdk diff 驗證

```bash
cdk diff --all -c product_name={product} -c deployment_mode={env} --profile $PROFILE
```

確認 diff 結果合理後再繼續。

---

## Step 2.7: 補充 import

`cdk import` 可能遺漏的資源：
- Lambda LogGroup（CDK 用 `log_group=` 參數明確指定時，LogGroup 是獨立資源）
- API Gateway 子資源（Resource, Method, Deployment, Stage）

使用 supplement import：
1. 取得現有 Stack template
2. 從 CDK synth 的 template 中找到需要補充的資源
3. 合併後用 `create-change-set --change-set-type IMPORT` 匯入

---

## Step 3: cdk deploy

```bash
# 部署順序（有依賴關係）
cdk deploy {StackPrefix}IotCertDelete -c product_name={product} -c deployment_mode={env} --profile $PROFILE --require-approval never --force
cdk deploy {StackPrefix}ShadowLogger  -c product_name={product} -c deployment_mode={env} --profile $PROFILE --require-approval never --force
cdk deploy {StackPrefix}SignalParser  -c product_name={product} -c deployment_mode={env} --profile $PROFILE --require-approval never --force
cdk deploy {StackPrefix}UserIdentify  -c product_name={product} -c deployment_mode={env} --profile $PROFILE --require-approval never --force
```

---

## Step 3.5: 強制更新 Lambda code/runtime + 清理舊 Permission

import 後 CloudFormation state 與 template 一致，但 AWS 上 Lambda 實際的 code 和 runtime 未更新。
需用 CLI 強制修正：

```bash
ASSET_BUCKET="cdk-xox010xox-assets-$(aws sts get-caller-identity --profile $PROFILE --query 'Account' --output text)-$REGION"

for stack in {StackPrefix}IotCertDelete {StackPrefix}ShadowLogger {StackPrefix}SignalParser {StackPrefix}UserIdentify; do
    aws cloudformation get-template --stack-name $stack --profile $PROFILE --region $REGION --output json | python3 -c "
import sys, json
data = json.load(sys.stdin)
t = data['TemplateBody']
for lid, res in t.get('Resources', {}).items():
    if res['Type'] == 'AWS::Lambda::Function':
        props = res['Properties']
        fn_name = props.get('FunctionName', '')
        s3key = props.get('Code', {}).get('S3Key', '')
        runtime = props.get('Runtime', '')
        if fn_name and s3key:
            print(f'{fn_name}|{s3key}|{runtime}')
" | while IFS='|' read -r fn_name s3key runtime; do
        aws lambda update-function-code --function-name "$fn_name" \
            --s3-bucket "$ASSET_BUCKET" --s3-key "$s3key" \
            --profile $PROFILE --region $REGION --no-cli-pager >/dev/null
        aws lambda wait function-updated --function-name "$fn_name" --profile $PROFILE --region $REGION
        aws lambda update-function-configuration --function-name "$fn_name" --runtime "$runtime" \
            --profile $PROFILE --region $REGION --no-cli-pager >/dev/null
        aws lambda wait function-updated --function-name "$fn_name" --profile $PROFILE --region $REGION
    done
done
```

清理舊的 Lambda resource-based policy：
```bash
for fn in <lambda-function-names>; do
    policy=$(aws lambda get-policy --function-name $fn --profile $PROFILE --region $REGION \
        --query 'Policy' --output text 2>/dev/null || echo "")
    if [ -n "$policy" ]; then
        echo "$policy" | python3 -c "
import sys, json
p = json.loads(sys.stdin.read())
for s in p['Statement']:
    sid = s['Sid']
    if not sid.startswith('{StackPrefix}'):
        print(sid)
" | while read sid; do
            aws lambda remove-permission --function-name $fn --statement-id "$sid" \
                --profile $PROFILE --region $REGION
        done
    fi
done
```

---

## Step 4: 最終驗證

```bash
PRODUCT={PRODUCT}

# 檢查 Stack 狀態
for stack in ${PRODUCT}IotCertDelete ${PRODUCT}ShadowLogger ${PRODUCT}SignalParser ${PRODUCT}UserIdentify; do
    status=$(aws cloudformation describe-stacks --stack-name $stack \
        --profile $PROFILE --region $REGION \
        --query 'Stacks[0].StackStatus' --output text 2>/dev/null || echo "NOT_FOUND")
    echo "$stack: $status"
done

# 檢查 Lambda runtime
for stack in ${PRODUCT}IotCertDelete ${PRODUCT}ShadowLogger ${PRODUCT}SignalParser ${PRODUCT}UserIdentify; do
    aws cloudformation describe-stack-resources --stack-name $stack \
        --profile $PROFILE --region $REGION \
        --query "StackResources[?ResourceType=='AWS::Lambda::Function'].PhysicalResourceId" \
        --output text | tr '\t' '\n' | while read fn; do
        rt=$(aws lambda get-function-configuration --function-name "$fn" \
            --profile $PROFILE --region $REGION --query 'Runtime' --output text)
        echo "  $fn: $rt"
    done
done
```

---

## 資源名稱差異注意事項

不同帳號/環境的資源名稱可能與 `iot-core-stack` 預設的命名不一致，需確認：

- Lambda function name 大小寫差異（如 `gm50ShadowLogger` vs `gm50shadowlogger`）
- IAM Role name（舊 Serverless 自動產生 vs 新 CDK 明確指定）
- S3 bucket name（如 `gm50-rawdata` vs `gm50-dev-rawdata`）
- Firehose IAM Role name（每個帳號不同，含隨機後綴）

如果名稱不一致，有兩種處理方式：
1. 修改 `iot-core-stack/stacks/` 中的 Stack 程式碼，加入該環境的特殊命名分支
2. 先用 AWS CLI 重新命名資源（部分資源不支援重新命名）

---

## resource-mapping 檔案命名慣例

```
iot-core-stack/resource-mapping-{env}-iot-cert-delete.json
iot-core-stack/resource-mapping-{env}-shadow-logger.json
iot-core-stack/resource-mapping-{env}-signal-parser.json
iot-core-stack/resource-mapping-{env}-user-identify.json
```

---

## 遷移後清理

- 刪除舊 Serverless Framework 的 deployment bucket（`*-serverlessdeploymentbucket-*`）
- 確認舊 Stack 已完全刪除
- 確認 IoT Rules 狀態正確（shadow_logger / event_log 預設 disabled）

---

## 常見問題

### cdk import 失敗：資源已存在於其他 Stack
確認舊 Stack 已完全刪除（`stack-delete-complete`），資源不再被任何 Stack 管理。

### cdk deploy 後 Lambda runtime 沒更新
這是 import 的已知行為。CloudFormation 認為 state 與 template 一致所以不更新。
用 Step 3.5 的 CLI 強制更新。

### cdk import 對 CfnStateMachine 報錯
已知 bug，改用 CloudFormation CLI 直接 import（見 Step 2 特殊處理）。

### supplement import change set 建立失敗
確認 template 中的 Logical ID 與 import JSON 中的一致，且資源確實存在於 AWS 上。

### 舊 Stack 資源名稱與 iot-core-stack 不一致
需要在 Stack 程式碼中加入該 deployment_mode 的特殊命名分支，
或在遷移前用 AWS CLI 調整資源名稱。
