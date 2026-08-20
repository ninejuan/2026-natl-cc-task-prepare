#!/usr/bin/env bash
# DAX 정리 — 클러스터 삭제 완료 후 서브넷그룹/VPC/SG/IAM 롤 제거. 이름으로 재조회.
set -uo pipefail
R=${R:-eu-west-1}
NAME=${NAME:-lab-euw1-dax}
ROLE=${ROLE:-lab-euw1-dax-role-euw1}
DDB_POLICY=arn:aws:iam::aws:policy/AmazonDynamoDBFullAccess

# 1) 클러스터 삭제 + 완료 대기
aws dax delete-cluster --region "$R" --cluster-name "$NAME" 2>/dev/null || true
echo "DAX 클러스터 삭제 대기..."
until ! aws dax describe-clusters --region "$R" --cluster-names "$NAME" >/dev/null 2>&1; do
  sleep 15; echo -n .
done; echo

# 2) DAX 서브넷 그룹
aws dax delete-subnet-group --region "$R" --subnet-group-name lab-euw1-dax-subnets 2>/dev/null || true

# 3) VPC/서브넷/SG (이름 태그로 조회)
VPC=$(aws ec2 describe-vpcs --region "$R" --filters Name=tag:Name,Values=lab-euw1-dax-vpc \
  --query 'Vpcs[0].VpcId' --output text 2>/dev/null)
if [ -n "$VPC" ] && [ "$VPC" != "None" ]; then
  for s in $(aws ec2 describe-subnets --region "$R" --filters Name=vpc-id,Values="$VPC" \
      --query 'Subnets[].SubnetId' --output text); do
    aws ec2 delete-subnet --region "$R" --subnet-id "$s"
  done
  SG=$(aws ec2 describe-security-groups --region "$R" \
    --filters Name=vpc-id,Values="$VPC" Name=group-name,Values=lab-euw1-dax-sg \
    --query 'SecurityGroups[0].GroupId' --output text 2>/dev/null)
  [ -n "$SG" ] && [ "$SG" != "None" ] && aws ec2 delete-security-group --region "$R" --group-id "$SG"
  aws ec2 delete-vpc --region "$R" --vpc-id "$VPC"
fi

# 4) IAM 롤
aws iam detach-role-policy --role-name "$ROLE" --policy-arn "$DDB_POLICY" 2>/dev/null || true
aws iam delete-role --role-name "$ROLE" 2>/dev/null || true
echo "teardown done"
