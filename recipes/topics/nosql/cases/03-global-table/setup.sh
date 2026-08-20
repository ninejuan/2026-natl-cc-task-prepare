#!/usr/bin/env bash
# DynamoDB Global Table (멀티리전 복제) — live 검증됨(eu-west-1 ↔ eu-central-1)
# Global Table 은 스트림 필수(NEW_AND_OLD_IMAGES) + 각 리전 동일 테이블명.
set -euo pipefail
R=${R:-eu-west-1}          # 홈 리전
R2=${R2:-eu-central-1}     # 복제 리전
T=${T:-lab-euw1-gt}

# 1) 홈 리전 테이블 — Global Table 은 스트림 NEW_AND_OLD_IMAGES 필수
aws dynamodb create-table --region "$R" --table-name "$T" \
  --attribute-definitions AttributeName=pk,AttributeType=S \
  --key-schema AttributeName=pk,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST \
  --stream-specification StreamEnabled=true,StreamViewType=NEW_AND_OLD_IMAGES
aws dynamodb wait table-exists --region "$R" --table-name "$T"

# 2) 복제본 추가 — 같은 테이블명이 R2 에 자동 생성
#    함정: 생성 직후엔 update-table 이 대상 리전에 대해 일시적으로
#    UnrecognizedClientException(security token invalid) 를 던진다 → 재시도로 해결.
until aws dynamodb update-table --region "$R" --table-name "$T" \
    --replica-updates '[{"Create":{"RegionName":"'"$R2"'"}}]' >/dev/null 2>&1; do
  echo -n "r"; sleep 10
done

# 3) 복제본 ACTIVE 대기 (수 분)
echo "복제본 생성 대기..."
until [ "$(aws dynamodb describe-table --region "$R" --table-name "$T" \
    --query "Table.Replicas[?RegionName=='$R2'].ReplicaStatus" --output text)" = "ACTIVE" ]; do
  sleep 15; echo -n .
done; echo

# 4) 검증: Replicas 에 양쪽 리전
aws dynamodb describe-table --region "$R" --table-name "$T" \
  --query 'Table.Replicas[].RegionName' --output text

# 5) 왕복: R 에 put → R2 에서 read (복제 몇 초 소요)
aws dynamodb put-item --region "$R" --table-name "$T" \
  --item '{"pk":{"S":"multi#1"},"msg":{"S":"hello from '"$R"'"}}'
sleep 8
echo -n "R2 read: "
aws dynamodb get-item --region "$R2" --table-name "$T" \
  --key '{"pk":{"S":"multi#1"}}' --query 'Item.msg.S' --output text
