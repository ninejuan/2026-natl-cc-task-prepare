#!/usr/bin/env bash
# 케이스 01 — FIFO 큐 순서 보장 + 콘텐츠 기반 중복제거. 실검증됨.
# order-2 를 두 번 보내면 중복제거로 1개만, 순서는 group 내 보장.
set -euo pipefail
export R=${R:-ap-northeast-2}

Q=$(aws sqs create-queue --region $R --queue-name lab-mq.fifo \
  --attributes 'FifoQueue=true,ContentBasedDeduplication=true' --query QueueUrl --output text)

# 같은 MessageGroupId=g1 → 순서 보장. 본문 같으면 5분 dedup 윈도우로 중복제거.
aws sqs send-message --region $R --queue-url "$Q" --message-body "order-1" --message-group-id g1 >/dev/null
aws sqs send-message --region $R --queue-url "$Q" --message-body "order-2" --message-group-id g1 >/dev/null
aws sqs send-message --region $R --queue-url "$Q" --message-body "order-2" --message-group-id g1 >/dev/null  # 중복→제거

sleep 2
echo "수신(중복 order-2 는 1개만, order-1→order-2 순서):"
aws sqs receive-message --region $R --queue-url "$Q" --max-number-of-messages 10 --wait-time-seconds 2 \
  --query 'Messages[].Body' --output text
# 실검증 결과: "order-1  order-2"  (3건 발행했지만 2건, 순서 보장)

aws sqs delete-queue --region $R --queue-url "$Q"
