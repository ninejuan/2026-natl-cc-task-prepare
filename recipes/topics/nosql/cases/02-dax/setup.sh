#!/usr/bin/env bash
# DynamoDB DAX (마이크로초 캐시) — 전용 VPC 클러스터. live 검증됨(eu-west-1). ~8분.
# DAX 는 VPC 리소스: 서브넷그룹 + SG + IAM 롤(DAX 가 DDB 접근 위해 assume) 필요.
set -euo pipefail
R=${R:-eu-west-1}
NAME=${NAME:-lab-euw1-dax}         # 클러스터명 (최대 20자)
ROLE=${ROLE:-lab-euw1-dax-role-euw1}
DDB_POLICY=arn:aws:iam::aws:policy/AmazonDynamoDBFullAccess

# 1) 전용 VPC + 서브넷 2개(2 AZ) + SG
VPC=$(aws ec2 create-vpc --region "$R" --cidr-block 10.20.0.0/16 \
  --tag-specifications 'ResourceType=vpc,Tags=[{Key=Name,Value=lab-euw1-dax-vpc}]' \
  --query Vpc.VpcId --output text)
AZ1=$(aws ec2 describe-availability-zones --region "$R" --query 'AvailabilityZones[0].ZoneName' --output text)
AZ2=$(aws ec2 describe-availability-zones --region "$R" --query 'AvailabilityZones[1].ZoneName' --output text)
SUB1=$(aws ec2 create-subnet --region "$R" --vpc-id "$VPC" --cidr-block 10.20.1.0/24 --availability-zone "$AZ1" \
  --tag-specifications 'ResourceType=subnet,Tags=[{Key=Name,Value=lab-euw1-dax-sub1}]' --query Subnet.SubnetId --output text)
SUB2=$(aws ec2 create-subnet --region "$R" --vpc-id "$VPC" --cidr-block 10.20.2.0/24 --availability-zone "$AZ2" \
  --tag-specifications 'ResourceType=subnet,Tags=[{Key=Name,Value=lab-euw1-dax-sub2}]' --query Subnet.SubnetId --output text)
SG=$(aws ec2 create-security-group --region "$R" --group-name lab-euw1-dax-sg \
  --description "lab-euw1 dax" --vpc-id "$VPC" --query GroupId --output text)
# DAX 포트 8111(비암호화)/9111(암호화) — VPC 내부 self-ingress
aws ec2 authorize-security-group-ingress --region "$R" --group-id "$SG" \
  --protocol tcp --port 8111-9111 --source-group "$SG" >/dev/null

# 2) DAX 서브넷 그룹
aws dax create-subnet-group --region "$R" --subnet-group-name lab-euw1-dax-subnets \
  --subnet-ids "$SUB1" "$SUB2" >/dev/null

# 3) IAM 롤 — DAX 가 DynamoDB 접근하려 assume (dax.amazonaws.com)
aws iam create-role --role-name "$ROLE" \
  --assume-role-policy-document '{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":"dax.amazonaws.com"},"Action":"sts:AssumeRole"}]}' >/dev/null
aws iam attach-role-policy --role-name "$ROLE" --policy-arn "$DDB_POLICY"
ROLE_ARN=$(aws iam get-role --role-name "$ROLE" --query Role.Arn --output text)
sleep 15   # 롤 전파 대기(create-cluster 가 assume 가능 검증)

# 4) 클러스터 — 가장 작은 노드 dax.t3.small, 단일 노드
aws dax create-cluster --region "$R" --cluster-name "$NAME" --node-type dax.t3.small \
  --replication-factor 1 --iam-role-arn "$ROLE_ARN" \
  --subnet-group-name lab-euw1-dax-subnets --security-group-ids "$SG" >/dev/null

# 5) available 대기 (~8분)
echo "DAX 클러스터 생성 대기..."
until [ "$(aws dax describe-clusters --region "$R" --cluster-names "$NAME" \
    --query 'Clusters[0].Status' --output text 2>/dev/null)" = "available" ]; do
  sleep 20; echo -n .
done; echo

# 6) 검증: Status + 엔드포인트
aws dax describe-clusters --region "$R" --cluster-names "$NAME" \
  --query 'Clusters[0].{Status:Status,Node:NodeType,Endpoint:ClusterDiscoveryEndpoint.Address,Port:ClusterDiscoveryEndpoint.Port}' --output json
