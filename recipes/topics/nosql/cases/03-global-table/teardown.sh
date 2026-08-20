#!/usr/bin/env bash
# Global Table 정리 — 복제본 먼저 제거 후 테이블 삭제.
set -uo pipefail
R=${R:-eu-west-1}; R2=${R2:-eu-central-1}; T=${T:-lab-euw1-gt}

# 1) 복제본 제거 (R2 쪽 테이블이 사라짐)
aws dynamodb update-table --region "$R" --table-name "$T" \
  --replica-updates '[{"Delete":{"RegionName":"'"$R2"'"}}]' 2>/dev/null || true
echo "복제본 제거 대기..."
until [ -z "$(aws dynamodb describe-table --region "$R" --table-name "$T" \
    --query "Table.Replicas[?RegionName=='$R2'].RegionName" --output text 2>/dev/null)" ]; do
  sleep 15; echo -n .
done; echo

# 2) 홈 테이블 삭제
aws dynamodb delete-table --region "$R" --table-name "$T" 2>/dev/null || true
echo "teardown done"
