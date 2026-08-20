#!/usr/bin/env bash
# 케이스 02 — Aurora Serverless v2 (PostgreSQL) + Data API(HTTP endpoint). 커넥션 없이 SQL.
# 💸 Aurora 생성 ~10분. min_capacity=0(auto-pause)로 유휴 과금 최소. 검증 후 삭제.
set -euo pipefail
export R=${R:-ap-northeast-2} ACCT=$(aws sts get-caller-identity --query Account --output text)

# subnet group (2 AZ) — 전용 VPC 서브넷 2개 필요(생략: 기존/전용 VPC 서브넷 SUB1,SUB2)
SUB1=${SUB1:?서브넷1} SUB2=${SUB2:?서브넷2}
aws rds create-db-subnet-group --region $R --db-subnet-group-name lab-aurora-sng \
  --db-subnet-group-description lab --subnet-ids $SUB1 $SUB2 >/dev/null

# Aurora PostgreSQL Serverless v2 + Data API + Secrets 자동관리
# ★ --skip-final-snapshot 은 create 옵션이 아니다(delete-db-cluster 전용). create 에 넣으면 Unknown options.
aws rds create-db-cluster --region $R --db-cluster-identifier lab-aurora \
  --engine aurora-postgresql --engine-mode provisioned \
  --database-name lab --master-username labadmin \
  --manage-master-user-password \
  --enable-http-endpoint \
  --serverless-v2-scaling-configuration MinCapacity=0,MaxCapacity=1 \
  --db-subnet-group-name lab-aurora-sng >/dev/null
# 인스턴스(db.serverless) 하나
aws rds create-db-instance --region $R --db-instance-identifier lab-aurora-1 \
  --db-cluster-identifier lab-aurora --engine aurora-postgresql \
  --db-instance-class db.serverless >/dev/null

echo "클러스터 + 인스턴스 available 대기(~10분)..."
aws rds wait db-cluster-available --region $R --db-cluster-identifier lab-aurora
# ★ Data API 는 인스턴스가 available 이어야 동작. cluster-available 만으론 부족
#   (인스턴스 creating 중이면 DatabaseNotFoundException "Cannot find DBInstance in DBCluster").
aws rds wait db-instance-available --region $R --db-instance-identifier lab-aurora-1

CARN=$(aws rds describe-db-clusters --region $R --db-cluster-identifier lab-aurora --query 'DBClusters[0].DBClusterArn' --output text)
SARN=$(aws rds describe-db-clusters --region $R --db-cluster-identifier lab-aurora --query 'DBClusters[0].MasterUserSecret.SecretArn' --output text)
echo "CARN=$CARN"
echo "SARN=$SARN"
echo "HttpEndpointEnabled: $(aws rds describe-db-clusters --region $R --db-cluster-identifier lab-aurora --query 'DBClusters[0].HttpEndpointEnabled' --output text)"

# ── Data API 로 커넥션 없이 쿼리 (핵심 검증) ──
aws rds-data execute-statement --region $R --resource-arn "$CARN" --secret-arn "$SARN" \
  --database lab --sql "CREATE TABLE IF NOT EXISTS items(id serial primary key, name text)"
aws rds-data execute-statement --region $R --resource-arn "$CARN" --secret-arn "$SARN" \
  --database lab --sql "INSERT INTO items(name) VALUES('widget'),('gadget')"
aws rds-data execute-statement --region $R --resource-arn "$CARN" --secret-arn "$SARN" \
  --database lab --sql "SELECT count(*) FROM items" --query 'records[0][0].longValue' --output text  # 2
