#!/bin/bash
# message-queue 03 — ReportBatchItemFailures 라이브 검증 (eu-west-1)
# 증명: 배치 3건 중 1건만 실패 → 성공 2건은 재처리 안 됨(로그 1회), 실패 1건만 재시도되어 DLQ 로.
set -x
R=eu-west-1
A=$(aws sts get-caller-identity --query Account --output text)
D="$(cd "$(dirname "$0")" && pwd)"
SRC=/Users/juany/workspace/sunrint/skills/2026-skills/national/task-prepare/recipes/topics/message-queue/cases/03-partial-batch

cd "$D"
rm -rf pkg && mkdir pkg && cp "$SRC/handler.py" pkg/ && (cd pkg && zip -q ../fn.zip handler.py)

cat > lam-trust.json <<'EOF'
{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":"lambda.amazonaws.com"},"Action":"sts:AssumeRole"}]}
EOF
aws iam create-role --role-name lab-mq03-role --assume-role-policy-document file://lam-trust.json --query Role.Arn --output text
aws iam attach-role-policy --role-name lab-mq03-role --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaSQSQueueExecutionRole
sleep 12

# DLQ 먼저
DLQ=$(aws sqs create-queue --region $R --queue-name lab-mq3b-dlq --query QueueUrl --output text)
DLQARN=$(aws sqs get-queue-attributes --region $R --queue-url $DLQ --attribute-names QueueArn --query Attributes.QueueArn --output text)
# 소스 큐: maxReceiveCount=2, visibility 30s
Q=$(aws sqs create-queue --region $R --queue-name lab-mq3b \
  --attributes "{\"VisibilityTimeout\":\"30\",\"RedrivePolicy\":\"{\\\"deadLetterTargetArn\\\":\\\"$DLQARN\\\",\\\"maxReceiveCount\\\":\\\"2\\\"}\"}" \
  --query QueueUrl --output text)
QARN=$(aws sqs get-queue-attributes --region $R --queue-url $Q --attribute-names QueueArn --query Attributes.QueueArn --output text)
echo "Q=$Q DLQ=$DLQ"

FN=$(aws lambda create-function --region $R --function-name lab-mq3b --runtime python3.12 \
  --role arn:aws:iam::$A:role/lab-mq03-role --handler handler.handler --zip-file fileb://fn.zip \
  --timeout 10 --query FunctionArn --output text)
aws lambda wait function-active-v2 --region $R --function-name lab-mq3b

# ★ 핵심 플래그: --function-response-types ReportBatchItemFailures
UUID=$(aws lambda create-event-source-mapping --region $R --function-name lab-mq3b \
  --event-source-arn $QARN --batch-size 10 --maximum-batching-window-in-seconds 5 \
  --function-response-types ReportBatchItemFailures \
  --query UUID --output text)
aws lambda get-event-source-mapping --region $R --uuid $UUID --query '[State,FunctionResponseTypes,BatchSize]' --output text
until [ "$(aws lambda get-event-source-mapping --region $R --uuid $UUID --query State --output text)" = "Enabled" ]; do sleep 5; done

echo "===== 3건 전송 (ok-1 / fail-me / ok-3) ====="
# ★ shorthand(Id=..,MessageBody={..}) 는 JSON body 의 쉼표/중괄호 때문에 파싱 실패 → JSON 리스트로
cat > entries.json <<'EOF'
[{"Id":"m1","MessageBody":"{\"id\":\"ok-1\"}"},
 {"Id":"m2","MessageBody":"{\"id\":\"fail-me\"}"},
 {"Id":"m3","MessageBody":"{\"id\":\"ok-3\"}"}]
EOF
aws sqs send-message-batch --region $R --queue-url $Q --entries file://entries.json \
  --query 'Successful[].Id' --output text

echo "===== 90초 대기(재시도 + DLQ 이동) ====="
sleep 95

echo "===== DLQ 내용: 실패한 1건만 있어야 함 ====="
aws sqs receive-message --region $R --queue-url $DLQ --max-number-of-messages 10 --wait-time-seconds 10 \
  --query 'Messages[].Body' --output text
echo "--- DLQ 메시지 수 ---"
aws sqs get-queue-attributes --region $R --queue-url $DLQ --attribute-names ApproximateNumberOfMessages ApproximateNumberOfMessagesNotVisible --query Attributes --output json
echo "--- 소스큐 잔량(0 이어야 함) ---"
aws sqs get-queue-attributes --region $R --queue-url $Q --attribute-names ApproximateNumberOfMessages ApproximateNumberOfMessagesNotVisible --query Attributes --output json

echo "===== 처리 로그: ok-1/ok-3 는 1회, fail-me 는 2회여야 함 ====="
aws logs filter-log-events --region $R --log-group-name /aws/lambda/lab-mq3b \
  --query 'events[].message' --output text 2>&1 | tr '\t' '\n' | grep -o 'failed .*\|REPORT' | head -20
echo "--- 각 body 별 수신 횟수 ---"
for k in ok-1 fail-me ok-3; do
  n=$(aws logs filter-log-events --region $R --log-group-name /aws/lambda/lab-mq3b --filter-pattern "\"$k\"" --query 'length(events)' --output text)
  echo "$k : $n"
done

echo "===== teardown ====="
aws lambda delete-event-source-mapping --region $R --uuid $UUID >/dev/null
aws lambda delete-function --region $R --function-name lab-mq3b
aws sqs delete-queue --region $R --queue-url $Q
aws sqs delete-queue --region $R --queue-url $DLQ
aws logs delete-log-group --region $R --log-group-name /aws/lambda/lab-mq3b
aws iam detach-role-policy --role-name lab-mq03-role --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaSQSQueueExecutionRole
aws iam delete-role --role-name lab-mq03-role
echo DONE
