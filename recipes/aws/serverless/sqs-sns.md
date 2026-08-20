# SQS · SNS

**트리거 문구** — "Message Queue 를 활용", "Spike 트래픽 분산 처리", "SQS 큐", "SNS 알림", "fan-out", "메시지 순서 보장", "중복 제거".

**전제**
```bash
export R=ap-northeast-2
```
> ⚠️ ARN 조립 금지(zsh `:x` modifier 로 잘림). 큐 ARN 은 `aws sqs get-queue-attributes ... QueueArn` 으로 받아라.

---

## SQS 케이스 A — standard + DLQ redrive

메시지 처리가 3번 실패하면 DLQ 로 보낸다. 채점이 "실패 메시지가 DLQ 로 이동" 을 확인하는 형태.

```bash
DLQ=$(aws sqs create-queue --region $R --queue-name lab-dlq --query QueueUrl --output text)
DLQARN=$(aws sqs get-queue-attributes --region $R --queue-url "$DLQ" \
  --attribute-names QueueArn --query Attributes.QueueArn --output text)

# main 큐에 redrive policy. maxReceiveCount 초과 시 DLQ 로.
aws sqs create-queue --region $R --queue-name lab-main --attributes "$(python3 -c "
import json
print(json.dumps({
  'RedrivePolicy': json.dumps({'deadLetterTargetArn':'$DLQARN','maxReceiveCount':'3'}),
  'VisibilityTimeout': '30'
}))")"
```
`RedrivePolicy` 는 **JSON 문자열 안의 JSON** 이라 이스케이프가 까다롭다. python 으로 만드는 게 안전.

## SQS 케이스 B — FIFO (순서 보장 + 중복 제거)

```bash
aws sqs create-queue --region $R --queue-name lab-q.fifo \
  --attributes '{"FifoQueue":"true","ContentBasedDeduplication":"true"}'
FIFO=$(aws sqs get-queue-url --region $R --queue-name lab-q.fifo --query QueueUrl --output text)

# 같은 MessageGroupId 는 순서 보장. send 시 group id 필수.
for i in 1 2 3; do
  aws sqs send-message --region $R --queue-url "$FIFO" --message-body "msg$i" --message-group-id g1
done
aws sqs receive-message --region $R --queue-url "$FIFO" --max-number-of-messages 3 \
  --query 'Messages[].Body' --output text    # msg1 msg2 msg3 순서
```
- **이름이 `.fifo` 로 끝나야** FIFO 다.
- **`MessageGroupId` 필수** — 같은 group 내에서만 순서 보장. 다른 group 은 병렬.
- `ContentBasedDeduplication` 켜면 body 해시로 5분 내 중복 제거. 끄면 `MessageDeduplicationId` 를 직접 줘야 한다.

## SQS 케이스 C — Lambda 소비 (ESM)

`../lambda.md` 케이스 E 참조. 큐 → Lambda 자동 트리거.

## SNS 케이스 D — fan-out + filter policy

한 토픽 → 여러 큐. 각 구독이 filter policy 로 필요한 메시지만 받는다.

```bash
TOPIC=$(aws sns create-topic --region $R --name lab-topic --query TopicArn --output text)
SUB=$(aws sns subscribe --region $R --topic-arn "$TOPIC" --protocol sqs \
  --notification-endpoint "$(aws sqs get-queue-attributes --region $R --queue-url "$(aws sqs get-queue-url --region $R --queue-name lab-main --query QueueUrl --output text)" --attribute-names QueueArn --query Attributes.QueueArn --output text)" \
  --return-subscription-arn --query SubscriptionArn --output text)

# type=order 인 메시지만 이 큐로
aws sns set-subscription-attributes --region $R --subscription-arn "$SUB" \
  --attribute-name FilterPolicy --attribute-value '{"type":["order"]}'
```
- SNS→SQS fan-out 시 **큐 정책에 SNS 가 SendMessage 하도록 허용**해야 실제 전달된다(구독만으론 부족한 경우). `RawMessageDelivery` 를 켜면 SNS 봉투 없이 원문만 큐로.
- filter policy 는 **메시지 속성**(`MessageAttributes`) 기준이 기본. body 기준이면 `FilterPolicyScope: MessageBody` 추가.
- FIFO 토픽도 있다(`.fifo`, `FifoTopic:true`).

## 검증

```bash
aws sqs list-queues --region $R --queue-name-prefix lab --query QueueUrls --output text
aws sqs get-queue-attributes --region $R --queue-url "$MAIN" \
  --attribute-names RedrivePolicy VisibilityTimeout --query Attributes --output json
aws sns list-subscriptions-by-topic --region $R --topic-arn "$TOPIC" \
  --query 'Subscriptions[].[Protocol,Endpoint]' --output text
aws sns get-subscription-attributes --region $R --subscription-arn "$SUB" \
  --query Attributes.FilterPolicy --output text
```

## 함정

- **DLQ redrive 는 JSON-in-JSON** — 이스케이프 실수가 흔하다. python 으로 만들어라.
- **FIFO 는 `.fifo` 접미사 + MessageGroupId** 둘 다 필수.
- **SNS→SQS 전달 안 됨** — 큐 리소스 정책이 SNS 를 허용하는지 확인. 콘솔 구독은 자동으로 붙지만 CLI 는 수동일 수 있다.
- **VisibilityTimeout < 처리시간** 이면 메시지가 중복 처리된다. Lambda ESM 은 함수 타임아웃의 6배 이상 권장.
- **maxReceiveCount** 를 너무 낮게(1) 잡으면 일시적 오류에도 바로 DLQ 로 간다.

## 정리
```bash
aws sqs delete-queue --region $R --queue-url "$MAIN"
aws sqs delete-queue --region $R --queue-url "$DLQ"
aws sqs delete-queue --region $R --queue-url "$FIFO"
aws sns delete-topic --region $R --topic-arn "$TOPIC"
```
