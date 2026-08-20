#!/usr/bin/env bash
# DocumentDB 정리 — 인스턴스 → 클러스터 → 서브넷그룹 → VPC/서브넷/SG. 이름으로 재조회.
set -uo pipefail
R=${R:-eu-west-1}
CL=${CL:-lab-euw1-docdb}

# 1) 인스턴스 삭제 + 완료 대기
aws docdb delete-db-instance --region "$R" --db-instance-identifier "${CL}-1" 2>/dev/null || true
echo "DocDB 인스턴스 삭제 대기..."
aws docdb wait db-instance-deleted --region "$R" --db-instance-identifier "${CL}-1" 2>/dev/null || true

# 2) 클러스터 삭제 + 완료 대기
aws docdb delete-db-cluster --region "$R" --db-cluster-identifier "$CL" --skip-final-snapshot 2>/dev/null || true
until ! aws docdb describe-db-clusters --region "$R" --db-cluster-identifier "$CL" >/dev/null 2>&1; do
  sleep 15; echo -n .
done; echo

# 3) DB 서브넷 그룹
aws docdb delete-db-subnet-group --region "$R" --db-subnet-group-name lab-euw1-docdb-subnets 2>/dev/null || true

# 4) VPC/서브넷/SG (이름 태그로 조회)
VPC=$(aws ec2 describe-vpcs --region "$R" --filters Name=tag:Name,Values=lab-euw1-docdb-vpc \
  --query 'Vpcs[0].VpcId' --output text 2>/dev/null)
if [ -n "$VPC" ] && [ "$VPC" != "None" ]; then
  for s in $(aws ec2 describe-subnets --region "$R" --filters Name=vpc-id,Values="$VPC" \
      --query 'Subnets[].SubnetId' --output text); do
    aws ec2 delete-subnet --region "$R" --subnet-id "$s"
  done
  SG=$(aws ec2 describe-security-groups --region "$R" \
    --filters Name=vpc-id,Values="$VPC" Name=group-name,Values=lab-euw1-docdb-sg \
    --query 'SecurityGroups[0].GroupId' --output text 2>/dev/null)
  [ -n "$SG" ] && [ "$SG" != "None" ] && aws ec2 delete-security-group --region "$R" --group-id "$SG"
  aws ec2 delete-vpc --region "$R" --vpc-id "$VPC"
fi
echo "teardown done"
