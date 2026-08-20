#!/usr/bin/env bash
# 케이스 02 — DLQ + redrive. maxReceiveCount 초과 시 실패 메시지가 DLQ 로 이동.
# 실검증됨(ap-northeast-2). 소스 큐 + DLQ, RedrivePolicy maxReceiveCount=2,
# 메시지 1건을 삭제 없이 3회 이상 수신 → ReceiveCount 가 2 초과 → DLQ 로 자동 이동.
set -euo pipefail
export R=${R:-ap-northeast-2}

# 1. DLQ 먼저 (RedrivePolicy 의 대상 ARN 이 필요) — 소스와 같은 타입(standard).
DLQ=$(aws sqs create-queue --region $R --queue-name lab-apne2-mq-dlq --query QueueUrl --output text)
DLQ_ARN=$(aws sqs get-queue-attributes --region $R --queue-url "$DLQ" \
  --attribute-names QueueArn --query Attributes.QueueArn --output text)

# 2. 소스 큐: DLQ 지정 + maxReceiveCount=2. VisibilityTimeout=0 → 수신 직후 재노출(반복 수신용).
#    RedrivePolicy 는 JSON 문자열을 값으로 갖는 attribute(이스케이프 주의).
Q=$(aws sqs create-queue --region $R --queue-name lab-apne2-mq-src \
  --attributes '{"VisibilityTimeout":"0","RedrivePolicy":"{\"deadLetterTargetArn\":\"'"$DLQ_ARN"'\",\"maxReceiveCount\":\"2\"}"}' \
  --query QueueUrl --output text)

echo "RedrivePolicy(소스):"
aws sqs get-queue-attributes --region $R --queue-url "$Q" \
  --attribute-names RedrivePolicy --query Attributes.RedrivePolicy --output text

# 3. 메시지 1건 발행.
aws sqs send-message --region $R --queue-url "$Q" --message-body "poison-message" >/dev/null

# 4. 삭제하지 않고 반복 수신 → ReceiveCount 가 maxReceiveCount(2) 를 넘으면 SQS 가 DLQ 로 이동.
for i in $(seq 1 6); do
  aws sqs receive-message --region $R --queue-url "$Q" \
    --visibility-timeout 0 --wait-time-seconds 1 \
    --query 'Messages[].Body' --output text >/dev/null 2>&1 || true
  sleep 1
done

# 5. 검증: DLQ 로 이동했는지(ApproximateNumberOfMessages 가 1 이 됨). 최종 일관성 → 폴링.
echo "DLQ 메시지 수(1 이면 redrive 성공):"
for i in $(seq 1 10); do
  N=$(aws sqs get-queue-attributes --region $R --queue-url "$DLQ" \
    --attribute-names ApproximateNumberOfMessages \
    --query Attributes.ApproximateNumberOfMessages --output text)
  echo "  attempt $i: DLQ=$N"
  [ "$N" = "1" ] && break
  sleep 3
done

# 정리
aws sqs delete-queue --region $R --queue-url "$Q"
aws sqs delete-queue --region $R --queue-url "$DLQ"
echo "teardown done"
