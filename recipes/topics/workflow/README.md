# Workflow 플레이북 (2025 #7 / 2026 #6, 2025 추가과제 Serverless Inventory 원형)

**가이드 원문** — "데이터 수집/변환/저장 오케스트레이션. 수집=S3, 처리=Lambda, 저장=DynamoDB. 오케스트레이션=**Step Functions**."
- 필수: S3, Lambda, DynamoDB, Step Functions / 선택: X

**★ 2025 추가과제 실제 출제**: Serverless Inventory — SFN + **API Gateway(AWS Service Proxy) + DynamoDB**, **컴퓨팅(Lambda/EC2/ECS) 전면 금지**. `aws lambda list-functions` 가 `[]` 여야 채점 통과. 이 변형(No-Lambda)을 반드시 대비.

**트리거 문구** — "Step Functions 워크플로", "수집→처리→저장", "상태 머신", "오케스트레이션", "재고 관리".

**리전 격리** — 전용. 예시 `ap-northeast-2`(2025 추가과제는 us-west-1 이었음).

**기반 카드**: ASL 5종 `../../aws/serverless/stepfunctions/`(실검증), Inventory ASL `../../aws/serverless/stepfunctions/inventory-ddb.asl.json`, APIGW VTL 직접통합 `../../aws/serverless/apigateway/vtl/`(SFN start·DDB), Lambda 핸들러 `../../aws/serverless/lambda/`.

---

## 케이스 인덱스

| # | 케이스 | 구조 | 검증 |
|---|---|---|---|
| 01 | S3→Lambda→DDB (표준 워크플로) | SFN + Lambda task | ✅ live `cases/01-s3-lambda-ddb/` (실행 SUCCEEDED, DDB 저장 확인) |
| 02 | Choice/Retry/Catch | 에러 처리·분기 | `cases/02-choice-retry/` ✓ |
| 03 | Map / Parallel / DistributedMap | 대량 병렬 | `cases/03-map-parallel/` ✓ |
| 04 | Callback(task token) | 외부 대기 | `cases/04-callback/` ✓ |
| 05 | **No-Lambda(SDK 직접통합)** | SFN→DDB SDK, APIGW→SFN VTL | ✅ live `cases/05-no-lambda/` (lambda=[]) |
| 06 | Express vs Standard | 고빈도 단기 vs 장기 | `cases/06-express-standard/` |

## ★ No-Lambda 변형 (2025 추가과제 핵심)

컴퓨팅 금지 시 **SFN 의 AWS SDK 직접통합**으로 Lambda 없이:
```
API Gateway (AWS Service Proxy, VTL) ──> Step Functions ──SDK통합──> DynamoDB
   /inventory GET → DDB GetItem 직접                SFN: dynamodb:updateItem 직접
```
- APIGW 는 `../../aws/serverless/apigateway/vtl/sfn-start-req.vtl`, `ddb-getitem-req.vtl`.
- SFN Task 는 `"Resource":"arn:aws:states:::dynamodb:updateItem"` (SDK 통합, Lambda 아님).
- 반칙검사: `aws lambda list-functions --query Functions` → `[]`.

## 검증 (채점자 문체)

```bash
aws stepfunctions list-state-machines --region $R --query 'stateMachines[].name' --output text
# 실행 → 결과 DDB 확인 (2025 추가과제 채점 방식)
ARN=$(aws stepfunctions list-state-machines --region $R --query "stateMachines[?name=='inventory-state-machine'].stateMachineArn" --output text)
aws stepfunctions start-execution --region $R --state-machine-arn "$ARN" --input '{"sales":20}'
sleep 5
aws dynamodb get-item --region $R --table-name inventory --key '{"name":{"S":"balance"}}' --query Item.value.N --output text
aws lambda list-functions --region $R --query Functions --output text   # [] (컴퓨팅 금지 검증)
```

## 함정

- **No-Lambda 면 SFN SDK 통합 + APIGW AWS Service Proxy** — Lambda 하나라도 있으면 0점(2025).
- **SFN Task ARN**: `arn:aws:states:::dynamodb:updateItem`(SDK) vs `arn:aws:states:::lambda:invoke`(Lambda). zsh `${VAR}` 주의.
- **IAM role 전파 지연** — apply 직후 실행하면 실패. 10초 대기(실검증).
- **Express 는 로그만**(실행 이력 없음), Standard 는 실행 이력 조회 가능. 채점이 이력 보면 Standard.
- APIGW 응답에서 큰따옴표 제거(VTL `$util` / integration response).
- **논프록시(AWS type) 요청템플릿의 에러 분기 body 는 클라가 못 본다(실검증)** — 요청템플릿 출력은 DDB 로 보내는 요청 payload 이고, 클라 응답 body 는 항상 통합 **응답**템플릿(`ddb-value-raw-res.vtl`)에서 나온다. `ddb-getitem-req.vtl` 의 `mysecret*`/빈값 분기는 `$context.responseOverride.status`(403/400)만 실제로 전달되고 body 는 응답템플릿의 "Not Found" 로 덮인다. 상태코드 검증엔 충분하나, 에러 body 까지 원하면 응답템플릿에서 status 별로 분기할 것.

## context7 참고

- `aws_sfn_state_machine`·`aws_api_gateway_integration`(AWS type) (TF AWS v6)
- SFN SDK 통합: https://docs.aws.amazon.com/step-functions/latest/dg/supported-services-awssdk.html
