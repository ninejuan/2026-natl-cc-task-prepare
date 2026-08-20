#!/usr/bin/env bash
# 케이스 04 — Secrets Manager 자격증명 + 자동 회전. RDS 마스터 비번을 코드 밖에.
set -euo pipefail
export R=${R:-ap-northeast-2}

# 방법 A — RDS 가 secret 을 아예 관리(가장 간단, 회전 포함)
#   create-db-cluster/instance 에 --manage-master-user-password
#   → RDS 가 Secrets 생성 + 회전 스케줄 관리. MasterUserSecret.SecretArn 로 참조.
CLUSTER=${CLUSTER:-lab-aurora}
aws rds describe-db-clusters --region $R --db-cluster-identifier "$CLUSTER" \
  --query 'DBClusters[0].MasterUserSecret.{arn:SecretArn,status:SecretStatus,kms:KmsKeyId}' --output json 2>/dev/null || \
  echo "(클러스터 없으면 케이스 01/02 먼저)"

# 방법 B — 직접 secret + 회전 Lambda 붙이기
#   aws secretsmanager create-secret --name lab/db --secret-string '{"username":"labadmin","password":"..."}'
#   aws secretsmanager rotate-secret --secret-id lab/db \
#     --rotation-lambda-arn <SecretsManagerRDSPostgreSQLRotationSingleUser> \
#     --rotation-rules AutomaticallyAfterDays=30
echo "회전 상태 확인:"
echo "  aws secretsmanager describe-secret --secret-id <arn> --query '{rotation:RotationEnabled,rules:RotationRules}'"
# 앱은 항상 GetSecretValue 로 최신 자격증명을 읽는다(회전돼도 코드 무변경).
