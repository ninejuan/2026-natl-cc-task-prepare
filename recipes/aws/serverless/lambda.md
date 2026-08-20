# Lambda

**트리거 문구** — "Python으로 API를 개발", "Lambda에 배포", "저장한 데이터를 조회하는 GET 호출", ESM("SQS 큐의 메시지를 Lambda가 처리"), "이미지 리사이징" 등.

> **바로 쓰는 코드**: `lambda/` 디렉토리에 검증된 핸들러 8종(crud-booking, dynamodb-scan-api, alb-response, sqs-batch, s3-event, ddb-stream, kinesis-consumer, image-resize)이 있다. 목록·용도는 [`lambda/README.md`](lambda/README.md). 배포는 [`scripts/deploy-lambda.sh`](scripts/deploy-lambda.sh) 한 줄.

**전제**
```bash
export R=ap-northeast-2 ACCT=$(aws sts get-caller-identity --query Account --output text)
```
리소스 이름에 비번호가 들어가면 `export P=<비번호>` 후 이름에 `$P`.

> ⚠️ **ARN 을 변수로 조립할 때 `"$ACCT:role"` 처럼 쓰지 말 것.** zsh/bash 에서 문제가 되진 않지만, 값을 만들 땐 `aws iam get-role ... --query Role.Arn` 로 **받아오는 게 안전**하다. 손으로 조립한 ARN 오타로 `CreateFunction` 이 `ValidationException` 난다.

---

## 실행 역할 (모든 케이스 공통)

```bash
cat > trust.json <<'JSON'
{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":"lambda.amazonaws.com"},"Action":"sts:AssumeRole"}]}
JSON
aws iam create-role --role-name lab-lambda-role \
  --assume-role-policy-document file://trust.json --query Role.Arn --output text
aws iam attach-role-policy --role-name lab-lambda-role \
  --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole
sleep 10   # IAM 전파. 이거 없이 바로 create-function 하면 InvalidParameterValueException(assume 못함)
ROLE=$(aws iam get-role --role-name lab-lambda-role --query Role.Arn --output text)
```

DynamoDB/SQS 등 추가 권한은 인라인으로:
```bash
cat > perm.json <<'JSON'
{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Action":["dynamodb:GetItem","dynamodb:Query","dynamodb:PutItem"],"Resource":"*"}]}
JSON
aws iam put-role-policy --role-name lab-lambda-role --policy-name app --policy-document file://perm.json
```

---

## 케이스 A — zip 배포 (기본)

가장 흔한 형태. 핸들러는 `파일명.함수명`.

```bash
cat > handler.py <<'PY'
import json, os
def handler(event, context):
    qs = (event or {}).get("queryStringParameters") or {}
    return {"statusCode": 200,
            "headers": {"Content-Type": "application/json"},
            "body": json.dumps({"echo": qs, "region": os.environ.get("AWS_REGION")})}
PY
zip -q fn.zip handler.py

aws lambda create-function --region "$R" --function-name lab-fn \
  --runtime python3.13 --handler handler.handler --role "$ROLE" \
  --zip-file fileb://fn.zip --timeout 10 --memory-size 128 \
  --environment "Variables={TABLE_NAME=lab-table,MSG=hello}"
aws lambda wait function-active-v2 --region "$R" --function-name lab-fn
```

코드 갱신:
```bash
zip -q fn.zip handler.py
aws lambda update-function-code --region "$R" --function-name lab-fn --zip-file fileb://fn.zip
aws lambda wait function-updated-v2 --region "$R" --function-name lab-fn
```
설정 갱신(env/timeout/memory)은 `update-function-configuration`. **code 와 configuration 은 별도 명령**이고, 연속 호출 시 앞 작업이 끝나야(`wait function-updated-v2`) 다음이 된다 — 안 그러면 `ResourceConflictException`.

## 케이스 B — 직접 호출 (채점이 하는 방식)

```bash
aws lambda invoke --region "$R" --function-name lab-fn \
  --payload '{"queryStringParameters":{"booking_id":"C001"}}' \
  --cli-binary-format raw-in-base64-out out.json
cat out.json    # {"statusCode":200,...}
```
`--cli-binary-format raw-in-base64-out` 없으면 payload 를 base64 로 오해한다. CLI v2 필수 플래그.

## 케이스 C — Function URL (⚠️ SCP 주의)

```bash
URL=$(aws lambda create-function-url-config --region "$R" --function-name lab-fn \
  --auth-type NONE --query FunctionUrl --output text)
aws lambda add-permission --region "$R" --function-name lab-fn \
  --statement-id fnurl --action lambda:InvokeFunctionUrl \
  --principal '*' --function-url-auth-type NONE
curl -s "${URL}?hello=world"
```

> ⚠️ **`auth-type NONE` 이 403 으로 막히는 계정이 있다.** Organization SCP 가 public Function URL 을 차단하면, 정책(`get-policy`)이 올바르게 붙어 있어도 curl 이 계속 403 이다. `aws organizations describe-organization` 로 org 소속이면 의심하라. 이 경우 우회는 **ALB target 또는 API Gateway** (케이스 D/아래). 대회 연습계정에서 실제로 관측됨.
>
> `auth-type AWS_IAM` 은 SigV4 서명 요청만 받는다 — 브라우저/curl 로 바로 안 열린다.

## 케이스 D — ALB target

CloudFront → ALB → Lambda 경로(1과제 흔함). ALB 가 Lambda 를 직접 타깃으로.

```bash
# Lambda 에 ALB 호출 허용
aws lambda add-permission --region "$R" --function-name lab-fn \
  --statement-id alb --action lambda:InvokeFunction \
  --principal elasticloadbalancing.amazonaws.com
# target group (target-type lambda)
TG=$(aws elbv2 create-target-group --region "$R" --name lab-fn-tg \
  --target-type lambda --query 'TargetGroups[0].TargetGroupArn' --output text)
aws elbv2 register-targets --region "$R" --target-group-arn "$TG" \
  --targets Id=arn:aws:lambda:$R:$ACCT:function:lab-fn
```
ALB 리스너 규칙에서 이 TG 로 라우팅. Lambda 는 ALB 이벤트 형식(`{"httpMethod","path","queryStringParameters",...}`)을 받고 `{"statusCode","headers","body","isBase64Encoded"}` 를 반환해야 한다. API Gateway proxy 형식과 미묘하게 다르다.

## 케이스 E — ESM (SQS/DDB Stream/MSK 소비)

```bash
QURL=$(aws sqs create-queue --region "$R" --queue-name lab-esm-q --query QueueUrl --output text)
QARN=$(aws sqs get-queue-attributes --region "$R" --queue-url "$QURL" \
  --attribute-names QueueArn --query Attributes.QueueArn --output text)
# 역할에 소비 권한 필수
cat > sqs.json <<'JSON'
{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Action":["sqs:ReceiveMessage","sqs:DeleteMessage","sqs:GetQueueAttributes"],"Resource":"*"}]}
JSON
aws iam put-role-policy --role-name lab-lambda-role --policy-name sqs --policy-document file://sqs.json
sleep 8

aws lambda create-event-source-mapping --region "$R" --function-name lab-fn \
  --event-source-arn "$QARN" --batch-size 5 \
  --maximum-batching-window-in-seconds 5 \
  --function-response-types ReportBatchItemFailures
```

- **batch window** 를 주면 채점 대기(3분) 안에 처리되도록 짧게(5s).
- **`ReportBatchItemFailures`** 를 켜면 핸들러가 `{"batchItemFailures":[{"itemIdentifier": msgId}]}` 를 반환해 실패한 메시지만 재시도. 전체 배치 재처리를 막는다.
- **필터**: `--filter-criteria '{"Filters":[{"Pattern":"{\"body\":{\"type\":[\"order\"]}}"}]}'` — 특정 메시지만 트리거.
- DDB Stream 은 `--starting-position LATEST` 필요. MSK 는 `--topics`.

## 케이스 F — layer / VPC / 동시성

```bash
# layer (공통 의존성)
aws lambda publish-layer-version --region "$R" --layer-name lab-deps \
  --zip-file fileb://layer.zip --compatible-runtimes python3.13
aws lambda update-function-configuration --region "$R" --function-name lab-fn \
  --layers arn:aws:lambda:$R:$ACCT:layer:lab-deps:1

# VPC (RDS/ElastiCache 접근 시). 역할에 AWSLambdaVPCAccessExecutionRole 필요
aws lambda update-function-configuration --region "$R" --function-name lab-fn \
  --vpc-config SubnetIds=subnet-aaa,subnet-bbb,SecurityGroupIds=sg-xxx

# 예약 동시성 (다른 함수 자원 보호) / 프로비저닝 동시성 (콜드스타트 제거)
aws lambda put-function-concurrency --region "$R" --function-name lab-fn --reserved-concurrent-executions 5
```
> VPC 를 붙이면 **NAT 없이는 인터넷/AWS API 를 못 나간다.** DynamoDB 등은 VPC endpoint 가 필요하다. VPC 붙였는데 타임아웃 나면 이걸 의심.

## 검증

```bash
aws lambda get-function-configuration --region "$R" --function-name lab-fn \
  --query '[FunctionName,Runtime,Handler,State,MemorySize,Timeout,Environment.Variables]' --output json
aws lambda invoke --region "$R" --function-name lab-fn \
  --payload '{"queryStringParameters":{"k":"v"}}' --cli-binary-format raw-in-base64-out /tmp/o.json >/dev/null && cat /tmp/o.json; echo
# ESM 상태 + 소비 확인
aws lambda list-event-source-mappings --region "$R" --function-name lab-fn \
  --query 'EventSourceMappings[].[State,BatchSize,EventSourceArn]' --output text
```

## 함정

- **IAM 전파**: role 만들고 바로 `create-function` 하면 실패. `sleep 10`.
- **code/config 동시 갱신**: 각각 별도 명령 + `wait function-updated-v2` 사이에 둬라. `ResourceConflictException`.
- **Function URL 403**: SCP 로 auth NONE 이 막힐 수 있다(위 케이스 C). org 계정이면 ALB/APIGW 로.
- **VPC 붙이면 인터넷 차단**: NAT/endpoint 없으면 외부 호출 타임아웃.
- **핸들러 이름**: `handler.handler` = `handler.py` 의 `handler` 함수. 파일명·함수명 불일치가 `Unable to import module` 의 원인.
- **payload base64**: invoke 시 `--cli-binary-format raw-in-base64-out` 빠뜨리면 payload 깨짐.
- **runtime 버전**: python3.13 확인됨(2026-08 기준). 과제지가 특정 버전 요구하면 맞춰라.

## 정리
```bash
aws lambda delete-event-source-mapping --region "$R" --uuid <UUID>
aws lambda delete-function --region "$R" --function-name lab-fn
aws sqs delete-queue --region "$R" --queue-url "$QURL"
aws iam delete-role-policy --role-name lab-lambda-role --policy-name sqs
aws iam detach-role-policy --role-name lab-lambda-role --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole
aws iam delete-role --role-name lab-lambda-role
```
