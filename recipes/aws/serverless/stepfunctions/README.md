# Step Functions

**트리거 문구** — "State machine 구성", "워크플로우로 오케스트레이션", "데이터 수집/변환/저장", "Step Functions 를 활용", "Lambda 없이"(→ SDK 직접통합).

**전제**
```bash
export R=ap-northeast-2
```

> ⚠️ **ARN 을 손으로 조립하지 마라.** zsh 에서 `"$ACCT:stateMachine:..."` 의 `:s` 가 변수 modifier 로 해석돼 ARN 이 잘린다(`...727` 뒤 소실). `InvalidArn` 의 원인. 항상 조회로 받아라:
> ```bash
> SM=$(aws stepfunctions list-state-machines --region $R --query "stateMachines[?name=='NAME'].stateMachineArn" --output text)
> ```

## ASL 예제 (전부 검증됨)

| 파일 | 다루는 것 | 검증 |
|---|---|---|
| `inventory-ddb.asl.json` | **DynamoDB SDK 직접통합**(Lambda 없이 updateItem), `States.Format`, `N.$` 동적값 | ✅ 실행 SUCCEEDED, stock/balance 변동 확인 |
| `choice-retry-catch.asl.json` | Choice 분기, Retry 지수백오프, Catch, Fail | ✅ validate |
| `map-parallel.asl.json` | 인라인 Map(항목별 저장), Parallel(동시 브랜치) | ✅ 실행 SUCCEEDED, Map/Parallel 결과 확인 |
| `distributed-map-s3.asl.json` | Distributed Map(S3 대량 병렬), ItemReader/Batcher/ResultWriter | ✅ validate |
| `callback-task-token.asl.json` | `.waitForTaskToken` 콜백(사람 승인/외부 시스템) | ✅ validate |

검증 방법 (실행 없이, 무료):
```bash
aws stepfunctions validate-state-machine-definition --region $R --definition file://X.asl.json
# result: OK / diagnostics 확인
```

## 생성·실행 (검증된 흐름)

```bash
# 역할: 직접통합하는 서비스 권한만 (예: DynamoDB)
cat > sfn-trust.json <<'JSON'
{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":"states.amazonaws.com"},"Action":"sts:AssumeRole"}]}
JSON
aws iam create-role --role-name lab-sfn-role --assume-role-policy-document file://sfn-trust.json
cat > sfn-perm.json <<'JSON'
{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Action":["dynamodb:UpdateItem","dynamodb:GetItem","dynamodb:PutItem"],"Resource":"*"}]}
JSON
aws iam put-role-policy --role-name lab-sfn-role --policy-name ddb --policy-document file://sfn-perm.json
sleep 8
ROLE=$(aws iam get-role --role-name lab-sfn-role --query Role.Arn --output text)

SM=$(aws stepfunctions create-state-machine --region $R --name lab-inv-sm \
  --definition file://inventory-ddb.asl.json --role-arn "$ROLE" --query stateMachineArn --output text)

EXEC=$(aws stepfunctions start-execution --region $R --state-machine-arn "$SM" \
  --input '{"sales":20}' --query executionArn --output text)
sleep 6
aws stepfunctions describe-execution --region $R --execution-arn "$EXEC" --query status --output text  # SUCCEEDED
```

Standard 대신 Express 가 필요하면(고빈도·단시간) `create-state-machine --type EXPRESS`. Express 는 execution 이력을 SFN 에 안 남기고 CloudWatch Logs 로 간다.

## 통합 방식 3가지

| 방식 | Resource 형식 | 쓸 때 |
|---|---|---|
| **SDK 직접통합** | `arn:aws:states:::aws-sdk:{service}:{api}` | Lambda 없이 임의 AWS API 호출. "컴퓨팅 금지" 요구의 정답 |
| **Optimized** | `arn:aws:states:::{service}:{action}` | DynamoDB/SQS/SNS/Lambda 등 자주 쓰는 것. `.sync`(완료대기)·`.waitForTaskToken` 지원 |
| **Optimized .sync** | `arn:aws:states:::ecs:runTask.sync` 등 | ECS/Glue/Batch/EMR 작업이 끝날 때까지 대기 |

optimized 예: `dynamodb:updateItem`, `sqs:sendMessage`, `sns:publish`, `lambda:invoke`, `states:startExecution.sync`.
SDK 직접통합 예: `aws-sdk:dynamodb:updateItem`, `aws-sdk:s3:putObject`, `aws-sdk:sns:publish`, `aws-sdk:ec2:describeInstances`. **optimized 에 없는 서비스는 SDK 직접통합으로 거의 다 된다.**

## 데이터 흐름 (자주 틀리는 곳)

한 state 에서:
```
입력 → [InputPath 로 걸러] → [Parameters 로 재구성] → Task 실행
     → [ResultSelector 로 결과 걸러] → [ResultPath 로 원본에 합쳐] → [OutputPath] → 출력
```
- **`ResultPath: null`** — Task 결과를 버리고 입력을 그대로 다음으로. inventory 예제에서 stock 결과를 안 쓰고 원래 `sales` 를 유지하는 데 사용.
- **`ResultPath: "$.x"`** — 결과를 입력의 `x` 키에 붙인다. 원본 보존.
- **`"키.$"`** — 값을 JSONPath/intrinsic 으로 동적 지정. `":s": {"N.$": "States.Format('{}', $.sales)"}` = sales 를 문자열로 변환해 주입(DynamoDB N 은 문자열이어야 함).

## intrinsic 함수 (자주 씀)

```
States.Format('{} - {}', $.a, $.b)     문자열 조합
States.StringToJson($.jsonString)      문자열 → JSON
States.JsonToString($.obj)             JSON → 문자열
States.Array($.a, $.b)                 배열 생성
States.ArrayLength($.items)            길이
States.MathAdd($.x, 1)                 산술
States.UUID()                          UUID
```

## 검증 (채점 관점)

```bash
aws stepfunctions list-state-machines --region $R --query "stateMachines[].name" --output text
aws stepfunctions describe-state-machine --region $R --state-machine-arn "$SM" --query '[name,type,status]' --output text
# 실행 후 결과를 DynamoDB 등 대상 리소스에서 확인 (2025 채점은 put-item 으로 값 세팅 → start-execution → get-item 으로 검증)
```

## Terraform [검증됨: apply→execute SUCCEEDED→destroy]

`../terraform-sfn/main.tf` — state machine + IAM + DynamoDB(시드 포함). ASL 을 `jsonencode()` 로 인라인(HCL 객체 → JSON). `.asl.json` 파일을 그대로 쓰려면 `definition = file("inventory-ddb.asl.json")`.

```bash
cd ../terraform-sfn
terraform init && terraform apply -auto-approve
SM=$(terraform output -raw state_machine_arn)
sleep 10   # ★ IAM 전파 — 아래 함정
aws stepfunctions start-execution --region ap-northeast-2 --state-machine-arn "$SM" --input '{"sales":30}'
terraform destroy -auto-approve
```
- ASL 을 HCL `jsonencode()` 로 쓰면 `"N.$" = "States.Format(...)"` 처럼 **동적 키(`.$`)를 문자열 키로** 그대로 넣을 수 있다. TF 보간 `${...}` 과 ASL `$.x` 는 안 겹친다(ASL 은 문자열 안).
- 파일 분리 선호 시: `definition = file("${path.module}/x.asl.json")` — 검증된 `.asl.json` 재사용.
- `type = "EXPRESS"` + `publish = true` 로 버전 관리.

> ⚠️ **IAM 전파 지연(실검증)**: `apply` 직후 6초 뒤 실행하면 role 이 아직 전파 안 돼 `TaskFailed`(AccessDenied) 로 FAILED. 10초 여유 주면 SUCCEEDED. TF create 는 role 전파를 재시도하지만, **실행(start-execution)은 별개** — apply 후 잠깐 대기 후 실행하라.

## Console 팁

- **Workflow Studio**: 드래그앤드롭으로 상태를 배치하고 ASL 을 자동 생성. Choice/Map/Parallel 을 시각적으로 짤 때 훨씬 빠르다. 완성 후 "Definition" 탭에서 ASL 을 복사해 `.asl.json` 으로.
- **실행 그래프**: 실행 상세에서 각 상태의 입력/출력을 색으로. 어느 상태에서 어떤 데이터로 실패했는지 즉시 보인다(CLI `get-execution-history` 보다 빠름).
- **Data flow simulator**: InputPath/Parameters/ResultSelector/ResultPath 를 미리 시뮬레이션. 데이터 흐름 디버깅의 핵심 도구.
- 대회 팁: **Workflow Studio 로 만들고 ASL 뽑아 TF/CLI 로 재현**. 복잡한 상태 기계는 손코딩보다 스튜디오가 정확하다.

## 참고 문서

- ASL 스펙: https://docs.aws.amazon.com/step-functions/latest/dg/concepts-amazon-states-language.html
- SDK 서비스 통합: https://docs.aws.amazon.com/step-functions/latest/dg/supported-services-awssdk.html
- optimized 통합(.sync/.waitForTaskToken): https://docs.aws.amazon.com/step-functions/latest/dg/connect-to-resource.html
- intrinsic 함수: https://docs.aws.amazon.com/step-functions/latest/dg/amazon-states-language-intrinsic-functions.html
- Terraform `aws_sfn_state_machine`: https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/sfn_state_machine

## 함정

- **ARN 조립 금지**(위 zsh 경고). 조회로 받아라.
- **DynamoDB N 값은 문자열**. `{"N": 20}` 아니라 `{"N.$": "States.Format('{}', $.sales)"}` 또는 `{"N": "20"}`.
- **`.sync` 없는 ecs/glue Task 는 제출 즉시 다음으로 넘어간다** — 완료를 기다리려면 `.sync`.
- **역할 권한**: 직접통합하는 모든 서비스 액션을 role 에 넣어야 한다. `.sync` 는 추가로 EventBridge/describe 권한이 필요한 경우가 있다(ecs.sync 등).
- **Map ItemProcessor 안의 상태**는 바깥과 별개 스코프. 바깥 변수는 `$$.Map.Item` 등 context 로 접근.
- **Distributed Map 은 자식 실행을 별도로 만든다** — IAM 에 `states:StartExecution` 필요, 실행 이력이 폭증할 수 있음.
- **validate-state-machine-definition** 은 문법·구조만 본다. 런타임 권한·데이터 오류는 못 잡는다. 실제 start-execution 으로 확인.

## 정리
```bash
aws stepfunctions delete-state-machine --region $R --state-machine-arn "$SM"
aws iam delete-role-policy --role-name lab-sfn-role --policy-name ddb
aws iam delete-role --role-name lab-sfn-role
```
