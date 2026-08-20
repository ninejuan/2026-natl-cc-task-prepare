#!/usr/bin/env bash
# Case 01: Producer -> MSK Serverless -> Lambda ESM -> (DDB)
# 실검증됨 (eu-central-1, 2026-08-20): 클러스터 ACTIVE + ESM State=Enabled.
#
# MSK 생성이 ~10-15분 걸린다. ARN 은 ${VAR}+aws --query 로만 조립한다.
# 이름 규칙: lab-euc1-* / IAM 롤 접미사 -euc1.
set -euo pipefail

R=${R:-eu-central-1}
PREFIX=lab-euc1
CLUSTER=$PREFIX-msk
FN=$PREFIX-consumer
ROLE=$PREFIX-msk-consumer-euc1
TOPIC=${TOPIC:-lab-topic}
CG=${CG:-lab-cg}

echo "== 1. VPC + 2 subnets(2 AZ) + SG(self-inbound 9098) =="
VPC=$(aws ec2 create-vpc --region $R --cidr-block 10.42.0.0/16 \
  --tag-specifications "ResourceType=vpc,Tags=[{Key=Name,Value=$PREFIX-msk-vpc}]" \
  --query 'Vpc.VpcId' --output text)
# MSK Serverless 는 VPC DNS hostnames/support 필수 (아니면 CreateClusterV2 BadRequest)
aws ec2 modify-vpc-attribute --region $R --vpc-id "$VPC" --enable-dns-hostnames
aws ec2 modify-vpc-attribute --region $R --vpc-id "$VPC" --enable-dns-support
S1=$(aws ec2 create-subnet --region $R --vpc-id "$VPC" --cidr-block 10.42.1.0/24 \
  --availability-zone ${R}a \
  --tag-specifications "ResourceType=subnet,Tags=[{Key=Name,Value=$PREFIX-msk-sn-a}]" \
  --query 'Subnet.SubnetId' --output text)
S2=$(aws ec2 create-subnet --region $R --vpc-id "$VPC" --cidr-block 10.42.2.0/24 \
  --availability-zone ${R}b \
  --tag-specifications "ResourceType=subnet,Tags=[{Key=Name,Value=$PREFIX-msk-sn-b}]" \
  --query 'Subnet.SubnetId' --output text)
SG=$(aws ec2 create-security-group --region $R --group-name $PREFIX-msk-sg \
  --description "$PREFIX MSK IAM SASL 9098 self-inbound" --vpc-id "$VPC" \
  --query 'GroupId' --output text)
# self-inbound 9098 (IAM SASL). MSK 실패의 대부분이 이 규칙 누락.
aws ec2 authorize-security-group-ingress --region $R --group-id "$SG" \
  --protocol tcp --port 9098 --source-group "$SG" >/dev/null
echo "VPC=$VPC S1=$S1 S2=$S2 SG=$SG"

echo "== 2. MSK Serverless 클러스터 생성 =="
cat > /tmp/$PREFIX-msk.json <<JSON
{
  "ClusterName": "$CLUSTER",
  "Serverless": {
    "VpcConfigs": [{"SubnetIds": ["$S1","$S2"], "SecurityGroupIds": ["$SG"]}],
    "ClientAuthentication": {"Sasl": {"Iam": {"Enabled": true}}}
  }
}
JSON
aws kafka create-cluster-v2 --region $R --cli-input-json file:///tmp/$PREFIX-msk.json
CA=$(aws kafka list-clusters-v2 --region $R \
  --query "ClusterInfoList[?ClusterName=='$CLUSTER'].ClusterArn" --output text)
echo "CA=$CA"

echo "== 3. Lambda 실행 롤 (ESM 권한) =="
cat > /tmp/$PREFIX-trust.json <<'JSON'
{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":"lambda.amazonaws.com"},"Action":"sts:AssumeRole"}]}
JSON
ROLE_ARN=$(aws iam create-role --role-name $ROLE \
  --assume-role-policy-document file:///tmp/$PREFIX-trust.json \
  --query 'Role.Arn' --output text)
# 컨트롤플레인(kafka:DescribeClusterV2/GetBootstrapBrokers) + ec2 ENI + logs
aws iam attach-role-policy --role-name $ROLE \
  --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaMSKExecutionRole
# 데이터플레인(IAM SASL): AWSLambdaMSKExecutionRole 에는 없음 -> 인라인 필수
cat > /tmp/$PREFIX-kafka.json <<'JSON'
{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Action":["kafka-cluster:Connect","kafka-cluster:DescribeCluster","kafka-cluster:DescribeClusterDynamicConfiguration","kafka-cluster:*Topic*","kafka-cluster:ReadData","kafka-cluster:DescribeGroup","kafka-cluster:AlterGroup"],"Resource":"*"}]}
JSON
aws iam put-role-policy --role-name $ROLE \
  --policy-name kafka-cluster-dataplane --policy-document file:///tmp/$PREFIX-kafka.json
echo "ROLE_ARN=$ROLE_ARN"

echo "== 4. Lambda consumer 함수 =="
cd "$(dirname "$0")"
zip -q /tmp/$PREFIX-fn.zip handler.py
for i in 1 2 3 4 5 6; do
  if aws lambda create-function --region $R --function-name $FN \
      --runtime python3.12 --handler handler.handler --role "$ROLE_ARN" \
      --zip-file fileb:///tmp/$PREFIX-fn.zip --timeout 30 >/dev/null 2>/tmp/$PREFIX-lerr; then
    break; else echo "롤 전파 대기 $i: $(cat /tmp/$PREFIX-lerr)"; sleep 10; fi
done

echo "== 5. 클러스터 ACTIVE 대기 (~10-15분) =="
while true; do
  ST=$(aws kafka describe-cluster-v2 --region $R --cluster-arn "$CA" --query 'ClusterInfo.State' --output text)
  echo "$(date +%H:%M:%S) State=$ST"
  [ "$ST" = "ACTIVE" ] && break
  [ "$ST" = "FAILED" ] && { echo "CLUSTER FAILED"; exit 1; }
  sleep 30
done

echo "== 6. 부트스트랩 브로커 (IAM SASL, 9098) =="
aws kafka get-bootstrap-brokers --region $R --cluster-arn "$CA" \
  --query 'BootstrapBrokerStringSaslIam' --output text

echo "== 7. Lambda ESM (MSK -> Lambda) =="
UUID=$(aws lambda create-event-source-mapping --region $R \
  --function-name $FN --event-source-arn "$CA" \
  --topics "$TOPIC" --starting-position LATEST \
  --amazon-managed-kafka-event-source-config "{\"ConsumerGroupId\":\"$CG\"}" \
  --query 'UUID' --output text)
echo "ESM UUID=$UUID"
# Enabled 될 때까지
while true; do
  ES=$(aws lambda get-event-source-mapping --region $R --uuid "$UUID" --query 'State' --output text)
  echo "$(date +%H:%M:%S) ESM=$ES"
  [ "$ES" = "Enabled" ] && break
  [ "$ES" = "Disabled" ] && { echo "ESM DISABLED"; break; }
  sleep 15
done

echo
echo "== 검증 =="
aws kafka list-clusters-v2 --region $R \
  --query "ClusterInfoList[?ClusterName=='$CLUSTER'].{name:ClusterName,state:State,type:ClusterType}" --output table
aws lambda list-event-source-mappings --region $R --function-name $FN \
  --query 'EventSourceMappings[].{uuid:UUID,state:State,topics:Topics}' --output table
