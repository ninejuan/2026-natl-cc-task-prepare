# EventBridge (Rule · Scheduler · Pipes)

**트리거 문구** — "이벤트를 감지하여", "특정 상태로 변하면 알림", "정해진 시간에", "S3 이벤트 → Lambda", "SQS → 다른 서비스로 전달", Cloud event handling / governance 모듈.

**전제**
```bash
export R=ap-northeast-2
```
> ⚠️ ARN 조립 금지. 조회로 받아라(zsh `:x` modifier 함정).

세 가지가 별개 기능이다:
- **Rule** — 이벤트 패턴 매칭 → 타깃 (감지·반응)
- **Scheduler** — cron/rate 로 타깃 호출 (시간 기반). CloudWatch Events 규칙보다 신형·유연
- **Pipes** — source → (filter → enrich) → target 파이프라인 (point-to-point 통합)

---

## 케이스 A — Rule (이벤트 패턴 → 타깃) [검증됨: topics/cloud-governance 01 — SG 자동복구]

SG 변경, EC2 상태 변화, S3 업로드 등을 감지. governance/event handling 모듈의 핵심.

```bash
# 예: SG 인바운드 변경 감지 → SNS 알림 (2024/2025 governance 형)
aws events put-rule --region $R --name lab-sg-rule \
  --event-pattern '{
    "source": ["aws.ec2"],
    "detail-type": ["AWS API Call via CloudTrail"],
    "detail": {
      "eventSource": ["ec2.amazonaws.com"],
      "eventName": ["AuthorizeSecurityGroupIngress"]
    }
  }'
aws events put-targets --region $R --rule lab-sg-rule \
  --targets "Id=1,Arn=$TOPIC_ARN"
```
- CloudTrail 이벤트를 받으려면 **CloudTrail 이 켜져 있어야** 한다(management events). 이게 governance 문제의 숨은 전제.
- Lambda 를 타깃으로 하면 `aws lambda add-permission --principal events.amazonaws.com --source-arn <rule arn>` 필요.

**이벤트 패턴 매칭 종류:**
```json
{"detail": {
  "state": ["running", "stopped"],              // 정확 일치 (OR)
  "amount": [{"numeric": [">", 100]}],          // 숫자 비교
  "name": [{"prefix": "prod-"}],                // 접두어
  "tag": [{"exists": true}],                    // 존재
  "region": [{"anything-but": ["us-east-1"]}]   // 부정
}}
```

## 케이스 B — Scheduler (시간 기반) [검증됨: TF apply→SQS]

```bash
cat > trust.json <<'JSON'
{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":"scheduler.amazonaws.com"},"Action":"sts:AssumeRole"}]}
JSON
aws iam create-role --role-name lab-sched-role --assume-role-policy-document file://trust.json
cat > perm.json <<'JSON'
{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Action":["sqs:SendMessage"],"Resource":"*"}]}
JSON
aws iam put-role-policy --role-name lab-sched-role --policy-name t --policy-document file://perm.json
sleep 8
SROLE=$(aws iam get-role --role-name lab-sched-role --query Role.Arn --output text)
QARN=$(aws sqs get-queue-attributes --region $R --queue-url "$QURL" --attribute-names QueueArn --query Attributes.QueueArn --output text)

aws scheduler create-schedule --region $R --name lab-sched \
  --schedule-expression "rate(5 minutes)" \
  --flexible-time-window '{"Mode":"OFF"}' \
  --target "{\"Arn\":\"$QARN\",\"RoleArn\":\"$SROLE\",\"Input\":\"tick\"}"
```
- `--schedule-expression`: `rate(5 minutes)`, `cron(0 9 * * ? *)`, `at(2026-06-01T00:00:00)`.
- `--schedule-expression-timezone "Asia/Seoul"` 로 KST cron.
- `flexible-time-window Mode OFF` = 정확한 시각. `FLEXIBLE` 이면 윈도우 내 분산.
- **Scheduler role 필요** — 타깃 서비스 호출 권한. Rule(EventBridge)과 달리 Scheduler 는 항상 role 로 호출.
- 일회성은 `at(...)` + `--action-after-completion NONE`.

## 케이스 C — Pipes (source → filter → enrich → target) [검증됨: topics/message-queue 05 — pipe RUNNING]

SQS/Kinesis/DDB Stream/MSK 를 source 로, 다른 서비스로 point-to-point 연결. Lambda 글루 코드를 없앤다.

```bash
cat > trust.json <<'JSON'
{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":"pipes.amazonaws.com"},"Action":"sts:AssumeRole"}]}
JSON
aws iam create-role --role-name lab-pipe-role --assume-role-policy-document file://trust.json
cat > perm.json <<'JSON'
{"Version":"2012-10-17","Statement":[
 {"Effect":"Allow","Action":["sqs:ReceiveMessage","sqs:DeleteMessage","sqs:GetQueueAttributes"],"Resource":"*"},
 {"Effect":"Allow","Action":["sns:Publish"],"Resource":"*"}]}
JSON
aws iam put-role-policy --role-name lab-pipe-role --policy-name p --policy-document file://perm.json
sleep 8
PROLE=$(aws iam get-role --role-name lab-pipe-role --query Role.Arn --output text)

aws pipes create-pipe --region $R --name lab-pipe \
  --source "$SRC_QUEUE_ARN" --target "$TARGET_TOPIC_ARN" --role-arn "$PROLE" \
  --source-parameters '{"FilterCriteria":{"Filters":[{"Pattern":"{\"body\":{\"type\":[\"order\"]}}"}]}}'

# RUNNING 될 때까지
aws pipes describe-pipe --region $R --name lab-pipe --query CurrentState --output text
```
- source/target 은 **role 에 양쪽 권한** 필요(소비 + 발행).
- filter 로 특정 메시지만 통과. enrichment(Lambda/API destination)로 변환 삽입 가능.
- target 파라미터로 변환(`TargetParameters.InputTemplate`) 가능.

## 케이스 D — custom bus + archive/replay [검증됨: 전용 버스→CW 3건, archive EventCount 3, replay COMPLETED]

```bash
aws events create-event-bus --region $R --name lab-bus
# 커스텀 이벤트 발행
aws events put-events --region $R --entries '[{"Source":"myapp","DetailType":"OrderPlaced","Detail":"{\"id\":1}","EventBusName":"lab-bus"}]'
# archive → 나중에 replay
aws events create-archive --region $R --archive-name lab-arc \
  --event-source-arn "$(aws events describe-event-bus --region $R --name lab-bus --query Arn --output text)"
```

## 검증

```bash
aws events list-rules --region $R --query 'Rules[].[Name,State]' --output text
aws events list-targets-by-rule --region $R --rule lab-sg-rule --query 'Targets[].Arn' --output text
aws scheduler get-schedule --region $R --name lab-sched --query '[Name,State,ScheduleExpression]' --output text
aws pipes describe-pipe --region $R --name lab-pipe --query '[Name,CurrentState]' --output text
```

## Rule vs Scheduler 선택

| | Rule (EventBridge) | Scheduler |
|---|---|---|
| 트리거 | 이벤트 발생 | 시간 (cron/rate/at) |
| role | 타깃별(Lambda 는 resource policy) | 항상 필요 |
| 용도 | 감지·반응 | 정기 작업·예약 |

"~를 감지하면" = Rule. "매일 9시" / "N분마다" = Scheduler. (구형 `put-rule --schedule-expression` 도 되지만 Scheduler 가 신형·권장)

## Terraform [검증됨: Scheduler→SQS apply/destroy]

`terraform-messaging/main.tf` 에 Scheduler→SQS 가 포함(검증). Rule/Pipes 도 TF 로:

```hcl
# Scheduler (검증됨)
resource "aws_scheduler_schedule" "s" {
  flexible_time_window { mode = "OFF" }
  schedule_expression = "rate(5 minutes)"
  target {
    arn      = aws_sqs_queue.q.arn
    role_arn = aws_iam_role.sched.arn   # Scheduler 는 role 필수
  }
}
# Rule (이벤트 패턴)
resource "aws_cloudwatch_event_rule" "r" {          # EventBridge = cloudwatch_event_*
  event_pattern = jsonencode({ source = ["aws.ec2"], "detail-type" = ["AWS API Call via CloudTrail"] })
}
resource "aws_cloudwatch_event_target" "t" {
  rule = aws_cloudwatch_event_rule.r.name
  arn  = aws_lambda_function.fn.arn
}
resource "aws_lambda_permission" "eb" {              # Lambda 타깃은 permission 필수
  action = "lambda:InvokeFunction"
  function_name = aws_lambda_function.fn.function_name
  principal = "events.amazonaws.com"
  source_arn = aws_cloudwatch_event_rule.r.arn
}
# Pipes
resource "aws_pipes_pipe" "p" {
  role_arn = aws_iam_role.pipe.arn
  source   = aws_sqs_queue.src.arn
  target   = aws_sns_topic.tgt.arn
}
```
> ⚠️ TF 에서 EventBridge Rule 은 **`aws_cloudwatch_event_rule`**(옛 CloudWatch Events 이름 유지). `aws_eventbridge_*` 아님. Scheduler·Pipes 는 `aws_scheduler_schedule`·`aws_pipes_pipe`.

## Console 팁

- **Rule 이벤트 패턴 빌더**: 콘솔이 이벤트 소스·타입을 드롭다운으로 주고 **샘플 이벤트로 패턴 매칭을 테스트**해준다. JSON 패턴을 손으로 짜다 틀리는 걸 막는다.
- **Scheduler**: cron/rate 를 폼으로 + "다음 10개 실행 시각" 미리보기. flexible window·타임존 설정도 클릭.
- **Pipes**: source→filter→enrichment→target 을 단계별 화면으로. 필터 패턴을 샘플로 테스트.
- **Sandbox**: EventBridge 콘솔의 "Send events" 로 커스텀 이벤트를 즉석 발행해 rule 을 검증.

## 참고 문서

- EventBridge 사용 설명서: https://docs.aws.amazon.com/eventbridge/latest/userguide/
- 이벤트 패턴: https://docs.aws.amazon.com/eventbridge/latest/userguide/eb-event-patterns.html
- Scheduler: https://docs.aws.amazon.com/scheduler/latest/UserGuide/
- Pipes: https://docs.aws.amazon.com/eventbridge/latest/userguide/eb-pipes.html
- Terraform `aws_scheduler_schedule`: https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/scheduler_schedule

## 함정

- **CloudTrail 없으면 API Call 이벤트가 안 온다.** governance 문제의 숨은 전제.
- **Lambda 타깃은 add-permission**, 다른 서비스 타깃은 role. Rule 은 이 둘이 섞인다.
- **Scheduler 는 role 필수** — Rule 감각으로 role 없이 만들면 타깃 호출 실패.
- **Pipes role 은 source+target 양쪽 권한**. 한쪽 빠지면 CREATING 에서 안 넘어가거나 메시지가 안 흐른다.
- **이벤트 패턴은 부분 매칭** — 명시한 필드만 본다. 너무 느슨하면 원치 않는 이벤트도 잡힌다.
- ARN 조립 금지(zsh 함정).

## 정리
```bash
aws events remove-targets --region $R --rule lab-sg-rule --ids 1
aws events delete-rule --region $R --name lab-sg-rule
aws scheduler delete-schedule --region $R --name lab-sched
aws pipes delete-pipe --region $R --name lab-pipe
aws iam delete-role-policy --role-name lab-sched-role --policy-name t; aws iam delete-role --role-name lab-sched-role
aws iam delete-role-policy --role-name lab-pipe-role --policy-name p; aws iam delete-role --role-name lab-pipe-role
```
