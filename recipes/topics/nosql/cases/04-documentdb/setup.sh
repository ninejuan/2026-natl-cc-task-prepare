#!/usr/bin/env bash
# DocumentDB (MongoDB 호환) — 전용 VPC 클러스터+인스턴스. live 검증됨(eu-west-1). ~10분.
# DocDB 는 VPC 내부 + TLS. 서브넷 그룹은 최소 2 AZ 필수.
set -euo pipefail
R=${R:-eu-west-1}
CL=${CL:-lab-euw1-docdb}
USER=${DOCDB_USER:-labadmin}
PASS=${DOCDB_PASS:-LabEuw1Pass123}   # 8~100자, / " @ 공백 불가

# 1) 전용 VPC + 서브넷 2개(2 AZ) + SG
VPC=$(aws ec2 create-vpc --region "$R" --cidr-block 10.21.0.0/16 \
  --tag-specifications 'ResourceType=vpc,Tags=[{Key=Name,Value=lab-euw1-docdb-vpc}]' \
  --query Vpc.VpcId --output text)
AZ1=$(aws ec2 describe-availability-zones --region "$R" --query 'AvailabilityZones[0].ZoneName' --output text)
AZ2=$(aws ec2 describe-availability-zones --region "$R" --query 'AvailabilityZones[1].ZoneName' --output text)
SUB1=$(aws ec2 create-subnet --region "$R" --vpc-id "$VPC" --cidr-block 10.21.1.0/24 --availability-zone "$AZ1" \
  --tag-specifications 'ResourceType=subnet,Tags=[{Key=Name,Value=lab-euw1-docdb-sub1}]' --query Subnet.SubnetId --output text)
SUB2=$(aws ec2 create-subnet --region "$R" --vpc-id "$VPC" --cidr-block 10.21.2.0/24 --availability-zone "$AZ2" \
  --tag-specifications 'ResourceType=subnet,Tags=[{Key=Name,Value=lab-euw1-docdb-sub2}]' --query Subnet.SubnetId --output text)
SG=$(aws ec2 create-security-group --region "$R" --group-name lab-euw1-docdb-sg \
  --description "lab-euw1 docdb" --vpc-id "$VPC" --query GroupId --output text)
aws ec2 authorize-security-group-ingress --region "$R" --group-id "$SG" \
  --protocol tcp --port 27017 --source-group "$SG" >/dev/null   # mongo 포트, VPC 내부

# 2) DB 서브넷 그룹
aws docdb create-db-subnet-group --region "$R" \
  --db-subnet-group-name lab-euw1-docdb-subnets \
  --db-subnet-group-description "lab-euw1 docdb" \
  --subnet-ids "$SUB1" "$SUB2" >/dev/null

# 3) 클러스터 + 인스턴스 (db.t3.medium)
aws docdb create-db-cluster --region "$R" --db-cluster-identifier "$CL" \
  --engine docdb --master-username "$USER" --master-user-password "$PASS" \
  --db-subnet-group-name lab-euw1-docdb-subnets --vpc-security-group-ids "$SG" >/dev/null
aws docdb create-db-instance --region "$R" \
  --db-instance-identifier "${CL}-1" --db-instance-class db.t3.medium \
  --engine docdb --db-cluster-identifier "$CL" >/dev/null

# 4) available 대기 (~10분)
echo "DocumentDB 인스턴스 생성 대기..."
aws docdb wait db-instance-available --region "$R" --db-instance-identifier "${CL}-1"

# 5) 검증: Status + engine + 엔드포인트
aws docdb describe-db-clusters --region "$R" --db-cluster-identifier "$CL" \
  --query 'DBClusters[0].{Status:Status,Engine:Engine,Endpoint:Endpoint,Port:Port}' --output json
