#!/usr/bin/env bash
# 케이스 05 — firewall 엔드포인트 배포 + inspection 라우팅. (정책은 케이스 04)
# 💸 firewall 엔드포인트는 시간과금(~$0.395/h). 검증 후 즉시 teardown.
# inspection VPC 패턴: IGW → firewall subnet(endpoint) → protected subnet.
set -euo pipefail
export R=${R:-ap-northeast-2} ACCT=$(aws sts get-caller-identity --query Account --output text)

# 전용 VPC + firewall subnet + protected subnet (같은 AZ)
VPC=$(aws ec2 create-vpc --region $R --cidr-block 10.30.0.0/16 \
  --tag-specifications 'ResourceType=vpc,Tags=[{Key=Name,Value=lab-nfw-vpc}]' --query Vpc.VpcId --output text)
aws ec2 wait vpc-available --region $R --vpc-ids $VPC
AZ=$(aws ec2 describe-availability-zones --region $R --query 'AvailabilityZones[0].ZoneName' --output text)
FW_SUB=$(aws ec2 create-subnet --region $R --vpc-id $VPC --cidr-block 10.30.1.0/24 --availability-zone $AZ \
  --tag-specifications 'ResourceType=subnet,Tags=[{Key=Name,Value=lab-nfw-fw-subnet}]' --query Subnet.SubnetId --output text)
PROT_SUB=$(aws ec2 create-subnet --region $R --vpc-id $VPC --cidr-block 10.30.2.0/24 --availability-zone $AZ \
  --tag-specifications 'ResourceType=subnet,Tags=[{Key=Name,Value=lab-nfw-prot-subnet}]' --query Subnet.SubnetId --output text)

POLICY=$(aws network-firewall describe-firewall-policy --region $R --firewall-policy-name lab-nfw-policy --query 'FirewallPolicyResponse.FirewallPolicyArn' --output text)

# firewall (firewall subnet 에 endpoint 생성 — READY 까지 수 분)
aws network-firewall create-firewall --region $R --firewall-name lab-nfw \
  --firewall-policy-arn "$POLICY" --vpc-id $VPC \
  --subnet-mappings "SubnetId=$FW_SUB" >/dev/null
echo "firewall 생성 중, READY 대기(수 분)..."
for i in $(seq 1 40); do
  ST=$(aws network-firewall describe-firewall --region $R --firewall-name lab-nfw --query 'FirewallStatus.Status' --output text)
  [ "$ST" = READY ] && break; sleep 15
done
echo "firewall status: $ST"
# endpoint id (라우팅에 사용)
EP=$(aws network-firewall describe-firewall --region $R --firewall-name lab-nfw \
  --query "FirewallStatus.SyncStates.\"$AZ\".Attachment.EndpointId" --output text)
echo "endpoint: $EP"

# ── 라우팅: protected subnet 아웃바운드를 firewall endpoint 로 (inspection 강제) ──
# IGW + firewall subnet RT(→IGW), protected subnet RT(0.0.0.0/0 → firewall endpoint)
IGW=$(aws ec2 create-internet-gateway --region $R --query InternetGateway.InternetGatewayId --output text)
aws ec2 attach-internet-gateway --region $R --internet-gateway-id $IGW --vpc-id $VPC
PROT_RT=$(aws ec2 create-route-table --region $R --vpc-id $VPC --query RouteTable.RouteTableId --output text)
aws ec2 associate-route-table --region $R --route-table-id $PROT_RT --subnet-id $PROT_SUB >/dev/null
aws ec2 create-route --region $R --route-table-id $PROT_RT --destination-cidr-block 0.0.0.0/0 --vpc-endpoint-id $EP >/dev/null
FW_RT=$(aws ec2 create-route-table --region $R --vpc-id $VPC --query RouteTable.RouteTableId --output text)
aws ec2 associate-route-table --region $R --route-table-id $FW_RT --subnet-id $FW_SUB >/dev/null
aws ec2 create-route --region $R --route-table-id $FW_RT --destination-cidr-block 0.0.0.0/0 --gateway-id $IGW >/dev/null

echo "VPC=$VPC FW_SUB=$FW_SUB PROT_SUB=$PROT_SUB EP=$EP IGW=$IGW"
echo "검증: protected subnet EC2 에서 egress → deny 도메인 차단 확인. 끝나면 teardown.sh."
