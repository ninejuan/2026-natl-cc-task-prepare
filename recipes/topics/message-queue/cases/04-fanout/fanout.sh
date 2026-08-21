#!/usr/bin/env bash
# 케이스 04 — SNS → 여러 SQS 팬아웃. 한 메시지를 N개 큐가 각자 받는다. 실검증됨.
# (기반: ../../aws/serverless/sqs-sns.md 의 fan-out.)
set -euo pipefail
export R=${R:-ap-northeast-2} ACCT=$(aws sts get-caller-identity --query Account --output text)

TOPIC=$(aws sns create-topic --region $R --name lab-fanout --query TopicArn --output text)
for q in lab-fanout-a lab-fanout-b; do
  QURL=$(aws sqs create-queue --region $R --queue-name $q --query QueueUrl --output text)
  QARN=$(aws sqs get-queue-attributes --region $R --queue-url "$QURL" --attribute-names QueueArn --query Attributes.QueueArn --output text)
  # ★ 큐 정책 JSON 은 --attributes 인라인 shorthand 로 안 됨(파서가 JSON 못 읽음) → 파일로.
  cat > /tmp/qpol-$q.json <<JSON
{"Policy":"{\"Version\":\"2012-10-17\",\"Statement\":[{\"Effect\":\"Allow\",\"Principal\":{\"Service\":\"sns.amazonaws.com\"},\"Action\":\"sqs:SendMessage\",\"Resource\":\"$QARN\",\"Condition\":{\"ArnEquals\":{\"aws:SourceArn\":\"$TOPIC\"}}}]}"}
JSON
  aws sqs set-queue-attributes --region $R --queue-url "$QURL" --attributes file:///tmp/qpol-$q.json
  aws sns subscribe --region $R --topic-arn $TOPIC --protocol sqs --notification-endpoint "$QARN" >/dev/null
done

aws sns publish --region $R --topic-arn $TOPIC --message '{"event":"fanout-test"}' >/dev/null
sleep 4
echo "각 큐 메시지 수(둘 다 1이어야 fan-out 성공):"
for q in lab-fanout-a lab-fanout-b; do
  QURL=$(aws sqs get-queue-url --region $R --queue-name $q --query QueueUrl --output text)
  echo "  $q: $(aws sqs get-queue-attributes --region $R --queue-url "$QURL" --attribute-names ApproximateNumberOfMessages --query Attributes.ApproximateNumberOfMessages --output text)"
done

for q in lab-fanout-a lab-fanout-b; do
  aws sqs delete-queue --region $R --queue-url "$(aws sqs get-queue-url --region $R --queue-name $q --query QueueUrl --output text)" 2>/dev/null
done
aws sns delete-topic --region $R --topic-arn $TOPIC 2>/dev/null
