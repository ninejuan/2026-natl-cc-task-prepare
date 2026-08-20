#!/usr/bin/env bash
# RDS Connection 토픽 공통 정리. Proxy → 인스턴스 → 클러스터 → subnet group → role.
set -uo pipefail
export R=${R:-ap-northeast-2}
retry() { for i in $(seq 1 30); do "$@" 2>/dev/null && return 0; sleep 15; done; }

# Proxy (case 01)
aws rds deregister-db-proxy-targets --region $R --db-proxy-name lab-proxy --db-cluster-identifier lab-proxy-db 2>/dev/null || true
aws rds delete-db-proxy --region $R --db-proxy-name lab-proxy 2>/dev/null || true

for CL in lab-aurora lab-proxy-db; do
  for INST in ${CL}-1; do
    aws rds delete-db-instance --region $R --db-instance-identifier $INST --skip-final-snapshot 2>/dev/null || true
  done
done
# 인스턴스 삭제 대기 후 클러스터
for CL in lab-aurora lab-proxy-db; do
  aws rds wait db-instance-deleted --region $R --db-instance-identifier ${CL}-1 2>/dev/null || true
  aws rds delete-db-cluster --region $R --db-cluster-identifier $CL --skip-final-snapshot 2>/dev/null || true
done
for CL in lab-aurora lab-proxy-db; do
  aws rds wait db-cluster-deleted --region $R --db-cluster-identifier $CL 2>/dev/null || true
done
for SNG in lab-aurora-sng lab-proxy-sng; do
  retry aws rds delete-db-subnet-group --region $R --db-subnet-group-name $SNG
done
aws iam delete-role-policy --role-name lab-proxy-role --policy-name s 2>/dev/null || true
aws iam delete-role --role-name lab-proxy-role 2>/dev/null || true
echo "RDS teardown done"
