# Workflow 케이스 (ASL 6종)

각 케이스의 ASL/VTL 이 이 폴더에 있다. `${...}` 플레이스홀더(FunctionArn/TableName)를 치환 후 `create-state-machine`.

| # | 케이스 | 파일 | 검증 |
|---|---|---|---|
| 01 | S3→Lambda→DDB 표준 | `01-s3-lambda-ddb/workflow.asl.json` | ✅ live(SDK GetObject→Lambda→PutItem, 실행 SUCCEEDED) |
| 02 | Choice/Retry/Catch | `02-choice-retry/choice-retry-catch.asl.json` | ✅ (serverless 카드서 검증) |
| 03 | Map/Parallel/DistributedMap | `03-map-parallel/{map-parallel,distributed-map-s3}.asl.json` | ✅ |
| 04 | Callback(task token) | `04-callback/callback-task-token.asl.json` | ✅ |
| 05 | No-Lambda(SDK 직접통합 + APIGW VTL) | `05-no-lambda/inventory-ddb.asl.json` + `*.vtl` | ✅ live(2025 추가과제 원형, lambda=[]) |
| 06 | Express vs Standard | `06-express-standard/README.md` | 비교(설정 1줄) |

## 배포 (예: 케이스 01)

```bash
export R=ap-northeast-2 ACCT=$(aws sts get-caller-identity --query Account --output text)
# SFN role: lambda:InvokeFunction + s3:GetObject + dynamodb:PutItem
sed "s|\${ProcessFunctionArn}|<lambda-arn>|; s|\${TableName}|<table>|" 01-s3-lambda-ddb/workflow.asl.json > /tmp/wf.json
aws stepfunctions create-state-machine --region $R --name lab-wf \
  --definition file:///tmp/wf.json --role-arn <sfn-role-arn>
# ★ role 전파 지연 → create 후 ~10초 대기 후 start-execution (실검증 함정)
aws stepfunctions start-execution --region $R --state-machine-arn <arn> --input '{"bucket":"b","key":"k"}'
```

## 함정
- **IAM role 전파 지연** — apply 직후 실행하면 States.Runtime 실패. 10초 대기(실측).
- **No-Lambda(05)**: Task Resource 를 `arn:aws:states:::dynamodb:updateItem`(SDK) 로 — `lambda:invoke` 금지. 반칙검사 `aws lambda list-functions`=[].
- **Express vs Standard**: Express 는 실행이력 없음(로그만), Standard 는 이력 조회 가능. 채점이 이력 보면 Standard.
- 기반 카드: `../../../aws/serverless/stepfunctions/`(README + 5 ASL).
