#!/usr/bin/env bash
# 케이스 03 — IAM DB 인증. 비밀번호 대신 15분 토큰으로 접속.
# 전제: RDS 인스턴스/클러스터에 --enable-iam-database-authentication, DB 유저를 IAM 매핑.
set -euo pipefail
export R=${R:-ap-northeast-2}
ENDPOINT=${ENDPOINT:?DB 엔드포인트} DBUSER=${DBUSER:-iamuser} DB=${DB:-lab}

# 1) DB 안에서 IAM 인증 유저 생성 (psql, 최초 1회 — master 로)
#    PostgreSQL: CREATE USER iamuser; GRANT rds_iam TO iamuser;
#    MySQL:      CREATE USER 'iamuser'@'%' IDENTIFIED WITH AWSAuthenticationPlugin AS 'RDS';

# 2) IAM 정책: 그 유저로 connect 허용 (특정 DB 리소스)
cat <<'JSON'
{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Action":"rds-db:connect",
  "Resource":"arn:aws:rds-db:REGION:ACCT:dbuser:DBI_RESOURCE_ID/iamuser"}]}
JSON

# 3) 15분 토큰 생성 + SSL 로 접속 (비번 없음)
TOKEN=$(aws rds generate-db-auth-token --region $R \
  --hostname "$ENDPOINT" --port 5432 --username "$DBUSER")
echo "token 생성됨(15분 유효). 접속:"
echo "PGPASSWORD=\"\$TOKEN\" psql \"host=$ENDPOINT port=5432 dbname=$DB user=$DBUSER sslmode=require\""
# 실제:
# PGPASSWORD="$TOKEN" psql "host=$ENDPOINT port=5432 dbname=$DB user=$DBUSER sslmode=require" -c "SELECT current_user"
