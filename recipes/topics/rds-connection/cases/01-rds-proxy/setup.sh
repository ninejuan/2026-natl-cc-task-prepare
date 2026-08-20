#!/usr/bin/env bash
# 케이스 01 — RDS Proxy + Secrets Manager 인증. 앱→Proxy→Aurora. 커넥션 풀링.
# 💸 RDS 생성 ~10분. 검증 후 삭제.
set -euo pipefail
export R=${R:-ap-northeast-2} ACCT=$(aws sts get-caller-identity --query Account --output text)
SUB1=${SUB1:?} SUB2=${SUB2:?} SG=${SG:?}   # 전용 VPC 서브넷 2개 + SG(5432 self)

# DB (Aurora PostgreSQL, master 비번 Secrets 자동관리 → Proxy 가 참조)
aws rds create-db-subnet-group --region $R --db-subnet-group-name lab-proxy-sng \
  --db-subnet-group-description lab --subnet-ids $SUB1 $SUB2 >/dev/null
aws rds create-db-cluster --region $R --db-cluster-identifier lab-proxy-db \
  --engine aurora-postgresql --engine-mode provisioned \
  --database-name lab --master-username labadmin --manage-master-user-password \
  --serverless-v2-scaling-configuration MinCapacity=0,MaxCapacity=1 \
  --db-subnet-group-name lab-proxy-sng --vpc-security-group-ids $SG >/dev/null
aws rds create-db-instance --region $R --db-instance-identifier lab-proxy-db-1 \
  --db-cluster-identifier lab-proxy-db --engine aurora-postgresql --db-instance-class db.serverless >/dev/null
aws rds wait db-cluster-available --region $R --db-cluster-identifier lab-proxy-db
SECRET=$(aws rds describe-db-clusters --region $R --db-cluster-identifier lab-proxy-db --query 'DBClusters[0].MasterUserSecret.SecretArn' --output text)

# Proxy role (Secrets 읽기)
aws iam create-role --role-name lab-proxy-role --assume-role-policy-document \
  '{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":"rds.amazonaws.com"},"Action":"sts:AssumeRole"}]}' >/dev/null 2>&1 || true
aws iam put-role-policy --role-name lab-proxy-role --policy-name s --policy-document \
  '{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Action":["secretsmanager:GetSecretValue"],"Resource":"'$SECRET'"}]}'
sleep 10
PROLE=$(aws iam get-role --role-name lab-proxy-role --query Role.Arn --output text)

# Proxy (engine POSTGRESQL, SECRETS 인증, TLS 강제)
aws rds create-db-proxy --region $R --db-proxy-name lab-proxy \
  --engine-family POSTGRESQL --role-arn "$PROLE" \
  --auth "AuthScheme=SECRETS,SecretArn=$SECRET,IAMAuth=DISABLED" \
  --require-tls --vpc-subnet-ids $SUB1 $SUB2 --vpc-security-group-ids $SG >/dev/null
aws rds wait db-proxy-available --region $R --db-proxy-name lab-proxy 2>/dev/null || sleep 60

# Proxy 를 클러스터에 타깃 등록
aws rds register-db-proxy-targets --region $R --db-proxy-name lab-proxy \
  --db-cluster-identifier lab-proxy-db >/dev/null

echo "Proxy 엔드포인트:"
aws rds describe-db-proxies --region $R --db-proxy-name lab-proxy \
  --query 'DBProxies[0].{status:Status,endpoint:Endpoint,tls:RequireTLS}' --output json
echo "→ 앱은 이 엔드포인트로 psql(TLS). 커넥션 풀링은 Proxy 가."
