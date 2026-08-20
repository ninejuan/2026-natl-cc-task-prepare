#!/usr/bin/env bash
# 케이스 04 — SNS → 여러 SQS 팬아웃. 한 메시지를 N개 큐가 각자 받는다.
# (기반: ../../aws/serverless/sqs-sns.md 의 fan-out. 여기선 실행 가능한 최소 재현.)
set -euo pipefail
export R=${R:-ap-northeast-2} ACCT=$(aws sts get-caller-identity --query Account --output text)

TOPIC=$(aws sns create-topic --region $R --name lab-fanout --query TopicArn --output text)
# 두 소비자 큐
for q in lab-fanout-a lab-fanout-b; do
  QURL=$(aws sqs create-queue --region $R --queue-name $q --query QueueUrl --output text)
  QARN=$(aws sqs get-queue-attributes --region $R --queue-url "$QURL" --attribute-names QueueArn --query Attributes.QueueArn --output text)
  # 큐 정책: SNS 가 이 큐에 보낼 수 있게
  aws sqs set-queue-attributes --region $R --queue-url "$QURL" --attributes \
    "Policy={\"Version\":\"2012-10-17\",\"Statement\":[{\"Effect\":\"Allow\",\"Principal\":{\"Service\":\"sns.amazonaws.com\"},\"Action\":\"sqs:SendMessage\",\"Resource\":\"$QARN\",\"Condition\":{\"ArnEquals\":{\"aws:SourceArn\":\"$TOPIC\"}}}]}"
  aws sns subscribe --region $R --topic-arn $TOPIC --protocol sqs --notification-endpoint "$QARN" >/dev/null
done
# 발행 1건 → 두 큐 모두 도착 확인
aws sns publish --region $R --topic-arn $TOPIC --message '{"event":"fanout-test"}' >/dev/null
sleep 3
echo "각 큐 메시지 수(둘 다 1이어야 fan-out 성공):"
for q in lab-fanout-a lab-fanout-b; do
  QURL=$(aws sqs get-queue-url --region $R --queue-name $q --query QueueUrl --output text)
  echo "  $q: $(aws sqs get-queue-attributes --region $R --queue-url "$QURL" --attribute-names ApproximateNumberOfMessages --query Attributes.ApproximateNumberOfMessages --output text)"
done

# 정리
for q in lab-fanout-a lab-fanout-b; do
  aws sqs delete-queue --region $R --queue-url "$(aws sqs get-queue-url --region $R --queue-name $q --query QueueUrl --output text)" 2>/dev/null
done
aws sns delete-topic --region $R --topic-arn $TOPIC 2>/dev/null
