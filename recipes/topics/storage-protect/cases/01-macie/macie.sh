#!/usr/bin/env bash
# 케이스 01 — Macie 로 S3 의 PII(민감데이터) 자동 탐지 job.
# ⚠️ Macie 는 계정 단위. 이미 켜져 있으면 끄지 말 것. job 은 수 분 소요.
set -euo pipefail
export R=${R:-ap-northeast-2} ACCT=$(aws sts get-caller-identity --query Account --output text)
B=lab-protect-$ACCT

# Macie 활성화 (이미 ENABLED 면 무시)
aws macie2 enable-macie --region $R 2>/dev/null || echo "(Macie 이미 활성)"

# 일회성 분류 job — 대상 버킷의 객체를 스캔해 PII finding 생성
aws macie2 create-classification-job --region $R \
  --name lab-pii-scan --job-type ONE_TIME \
  --s3-job-definition "{\"bucketDefinitions\":[{\"accountId\":\"$ACCT\",\"buckets\":[\"$B\"]}]}" \
  --query jobId --output text

echo "job 상태(RUNNING→COMPLETE, 수 분):"
aws macie2 list-classification-jobs --region $R \
  --query "items[?name=='lab-pii-scan'].{id:jobId,status:jobStatus}" --output json
echo "finding 조회(완료 후):"
echo "  aws macie2 list-findings --region $R --query findingIds"
echo "  aws macie2 get-findings --region $R --finding-ids <id> --query 'findings[].{type:type,sev:severity.description,count:classificationDetails.result.sensitiveData}'"
# "조치": finding → EventBridge(source aws.macie) → Lambda 로 격리/태깅.
