#!/usr/bin/env bash
# 케이스 05 정리. firewall → 라우트/IGW/subnet → VPC. (rule group·policy 는 별도)
set -uo pipefail
export R=${R:-ap-northeast-2}
VPC=$(aws ec2 describe-vpcs --region $R --filters Name=tag:Name,Values=lab-nfw-vpc --query 'Vpcs[0].VpcId' --output text 2>/dev/null)

# ★ 삭제 순서(실측): firewall endpoint 를 참조하는 라우트를 "먼저" 지워야 firewall 삭제 가능.
#   안 그러면 InvalidRequestException("related VPC endpoint still exist in route table").
#   ★★ create-route --vpc-endpoint-id 로 만든 라우트는 describe 시 endpoint 가 GatewayId 필드에 뜬다
#      (VpcEndpointId 아님!). 그래서 vpce 라우트는 dst cidr 로 지운다.
aws network-firewall update-firewall-delete-protection --region $R --firewall-name lab-nfw --no-delete-protection 2>/dev/null || true
if [ "$VPC" != "None" ] && [ -n "$VPC" ]; then
  for rt in $(aws ec2 describe-route-tables --region $R --filters Name=vpc-id,Values=$VPC --query 'RouteTables[].RouteTableId' --output text); do
    for cidr in $(aws ec2 describe-route-tables --region $R --route-table-ids $rt \
        --query "RouteTables[0].Routes[?starts_with(GatewayId,'vpce-')].DestinationCidrBlock" --output text); do
      aws ec2 delete-route --region $R --route-table-id $rt --destination-cidr-block $cidr 2>/dev/null; done
  done
fi
aws network-firewall delete-firewall --region $R --firewall-name lab-nfw 2>/dev/null || true
echo "firewall 삭제 대기..."
for i in $(seq 1 40); do
  aws network-firewall describe-firewall --region $R --firewall-name lab-nfw >/dev/null 2>&1 || { echo "firewall 삭제됨"; break; }
  sleep 15
done

if [ "$VPC" != "None" ] && [ -n "$VPC" ]; then
  # 라우트/RT/IGW/subnet 정리
  for rt in $(aws ec2 describe-route-tables --region $R --filters Name=vpc-id,Values=$VPC --query 'RouteTables[?Associations[0].Main!=`true`].RouteTableId' --output text); do
    for a in $(aws ec2 describe-route-tables --region $R --route-table-ids $rt --query 'RouteTables[0].Associations[].RouteTableAssociationId' --output text); do
      aws ec2 disassociate-route-table --region $R --association-id $a 2>/dev/null; done
    aws ec2 delete-route-table --region $R --route-table-id $rt 2>/dev/null; done
  for igw in $(aws ec2 describe-internet-gateways --region $R --filters Name=attachment.vpc-id,Values=$VPC --query 'InternetGateways[].InternetGatewayId' --output text); do
    aws ec2 detach-internet-gateway --region $R --internet-gateway-id $igw --vpc-id $VPC
    aws ec2 delete-internet-gateway --region $R --internet-gateway-id $igw; done
  for s in $(aws ec2 describe-subnets --region $R --filters Name=vpc-id,Values=$VPC --query 'Subnets[].SubnetId' --output text); do
    aws ec2 delete-subnet --region $R --subnet-id $s; done
  for i in $(seq 1 6); do aws ec2 delete-vpc --region $R --vpc-id $VPC 2>/dev/null && { echo "VPC deleted"; break; }; sleep 10; done
fi
echo "teardown done (rule group/policy 는 별도 삭제)"
