#!/usr/bin/env bash
# 케이스 05 — EventBridge Pipes: SQS(소스) → (필터/변환) → 타깃(SFN/Lambda/SNS). 코드 없이 연결.
# Lambda ESM 대안. 필터링·enrichment 를 선언적으로.
set -euo pipefail
export R=${R:-ap-northeast-2} ACCT=$(aws sts get-caller-identity --query Account --output text)

Q=$(aws sqs create-queue --region $R --queue-name lab-pipe-src --query QueueUrl --output text)
QARN=$(aws sqs get-queue-attributes --region $R --queue-url "$Q" --attribute-names QueueArn --query Attributes.QueueArn --output text)
TOPIC=$(aws sns create-topic --region $R --name lab-pipe-tgt --query TopicArn --output text)

# Pipe role (소스 읽기 + 타깃 쓰기)
aws iam create-role --role-name lab-pipe-role --assume-role-policy-document \
  '{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":"pipes.amazonaws.com"},"Action":"sts:AssumeRole"}]}' >/dev/null 2>&1 || true
aws iam put-role-policy --role-name lab-pipe-role --policy-name p --policy-document \
  '{"Version":"2012-10-17","Statement":[
    {"Effect":"Allow","Action":["sqs:ReceiveMessage","sqs:DeleteMessage","sqs:GetQueueAttributes"],"Resource":"'$QARN'"},
    {"Effect":"Allow","Action":["sns:Publish"],"Resource":"'$TOPIC'"}]}'
sleep 10
ROLE=$(aws iam get-role --role-name lab-pipe-role --query Role.Arn --output text)

# Pipe: SQS → SNS. SourceParameters 로 배치·필터, 필터는 특정 본문만 통과.
aws pipes create-pipe --region $R --name lab-pipe \
  --source "$QARN" --target "$TOPIC" --role-arn "$ROLE" \
  --source-parameters '{"SqsQueueParameters":{"BatchSize":5},
    "FilterCriteria":{"Filters":[{"Pattern":"{\"body\":{\"type\":[\"order\"]}}"}]}}' >/dev/null

echo "pipe 상태:"
aws pipes describe-pipe --region $R --name lab-pipe --query '{state:CurrentState,src:Source,tgt:Target}' --output json
# 정리: aws pipes delete-pipe --name lab-pipe; sqs delete-queue; sns delete-topic; iam 정리
