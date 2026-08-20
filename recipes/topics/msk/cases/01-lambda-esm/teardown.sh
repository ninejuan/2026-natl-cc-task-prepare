#!/usr/bin/env bash
# Case 01 전체 정리. MSK 삭제는 느리다(DELETING) — gone 까지 폴링.
# 순서: ESM -> Lambda -> MSK(대기) -> SG/subnet/VPC -> IAM 롤.
set -uo pipefail

R=${R:-eu-central-1}
PREFIX=lab-euc1
CLUSTER=$PREFIX-msk
FN=$PREFIX-consumer
ROLE=$PREFIX-msk-consumer-euc1

echo "== ESM 삭제 =="
for U in $(aws lambda list-event-source-mappings --region $R --function-name $FN \
    --query 'EventSourceMappings[].UUID' --output text 2>/dev/null); do
  aws lambda delete-event-source-mapping --region $R --uuid "$U" >/dev/null 2>&1 && echo "deleted ESM $U"
done

echo "== Lambda 삭제 =="
aws lambda delete-function --region $R --function-name $FN 2>/dev/null && echo "deleted $FN"

echo "== MSK 삭제 (DELETING 폴링) =="
CA=$(aws kafka list-clusters-v2 --region $R \
  --query "ClusterInfoList[?ClusterName=='$CLUSTER'].ClusterArn" --output text)
if [ -n "$CA" ] && [ "$CA" != "None" ]; then
  aws kafka delete-cluster --region $R --cluster-arn "$CA" >/dev/null && echo "delete requested"
  while aws kafka describe-cluster-v2 --region $R --cluster-arn "$CA" >/dev/null 2>&1; do
    echo "$(date +%H:%M:%S) still deleting..."; sleep 30
  done
  echo "cluster gone"
fi

echo "== VPC 자원 삭제 =="
VPC=$(aws ec2 describe-vpcs --region $R \
  --filters Name=tag:Name,Values=$PREFIX-msk-vpc --query 'Vpcs[0].VpcId' --output text)
if [ -n "$VPC" ] && [ "$VPC" != "None" ]; then
  # MSK ENI 가 남아 있으면 subnet/SG 삭제 실패 -> ENI 정리
  for ENI in $(aws ec2 describe-network-interfaces --region $R \
      --filters Name=vpc-id,Values=$VPC --query 'NetworkInterfaces[].NetworkInterfaceId' --output text); do
    aws ec2 delete-network-interface --region $R --network-interface-id "$ENI" 2>/dev/null && echo "deleted ENI $ENI"
  done
  SG=$(aws ec2 describe-security-groups --region $R \
    --filters Name=vpc-id,Values=$VPC Name=group-name,Values=$PREFIX-msk-sg \
    --query 'SecurityGroups[0].GroupId' --output text)
  [ "$SG" != "None" ] && aws ec2 delete-security-group --region $R --group-id "$SG" 2>/dev/null && echo "deleted SG $SG"
  for SN in $(aws ec2 describe-subnets --region $R \
      --filters Name=vpc-id,Values=$VPC --query 'Subnets[].SubnetId' --output text); do
    aws ec2 delete-subnet --region $R --subnet-id "$SN" 2>/dev/null && echo "deleted subnet $SN"
  done
  aws ec2 delete-vpc --region $R --vpc-id "$VPC" 2>/dev/null && echo "deleted VPC $VPC"
fi

echo "== IAM 롤 삭제 =="
aws iam delete-role-policy --role-name $ROLE --policy-name kafka-cluster-dataplane 2>/dev/null
aws iam detach-role-policy --role-name $ROLE \
  --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaMSKExecutionRole 2>/dev/null
aws iam delete-role --role-name $ROLE 2>/dev/null && echo "deleted role $ROLE"

echo "== clean scan =="
aws kafka list-clusters-v2 --region $R \
  --query "ClusterInfoList[?starts_with(ClusterName,'lab-euc1-')].ClusterName" --output text
aws lambda list-functions --region $R \
  --query "Functions[?starts_with(FunctionName,'lab-euc1-')].FunctionName" --output text
