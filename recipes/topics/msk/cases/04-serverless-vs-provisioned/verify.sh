#!/bin/bash
# msk 04 — Serverless vs Provisioned 라이브 비교 (us-east-1). 같은 VPC 에 둘 다 띄워 관찰 차이를 실측.
set -x
R=us-east-1
D="$(cd "$(dirname "$0")" && pwd)"; cd "$D"

VPC=$(aws ec2 create-vpc --region $R --cidr-block 10.60.0.0/16 --query Vpc.VpcId --output text)
aws ec2 create-tags --region $R --resources $VPC --tags Key=Name,Value=lab-msk04-vpc
aws ec2 modify-vpc-attribute --region $R --vpc-id $VPC --enable-dns-hostnames   # ★ MSK 필수
S1=$(aws ec2 create-subnet --region $R --vpc-id $VPC --cidr-block 10.60.1.0/24 --availability-zone ${R}a --query Subnet.SubnetId --output text)
S2=$(aws ec2 create-subnet --region $R --vpc-id $VPC --cidr-block 10.60.2.0/24 --availability-zone ${R}b --query Subnet.SubnetId --output text)
SG=$(aws ec2 describe-security-groups --region $R --filters Name=vpc-id,Values=$VPC Name=group-name,Values=default --query 'SecurityGroups[0].GroupId' --output text)
aws ec2 authorize-security-group-ingress --region $R --group-id $SG --protocol tcp --port 9092-9098 --source-group $SG >/dev/null
echo "VPC=$VPC S1=$S1 S2=$S2 SG=$SG"

cat > prov.json <<EOF
{
  "ClusterName": "lab-msk-prov",
  "Provisioned": {
    "BrokerNodeGroupInfo": {
      "InstanceType": "kafka.t3.small",
      "ClientSubnets": ["$S1","$S2"],
      "SecurityGroups": ["$SG"],
      "StorageInfo": {"EbsStorageInfo": {"VolumeSize": 10}}
    },
    "NumberOfBrokerNodes": 2,
    "KafkaVersion": "3.6.0",
    "ClientAuthentication": {"Sasl": {"Iam": {"Enabled": true}}},
    "EncryptionInfo": {"EncryptionInTransit": {"ClientBroker": "TLS", "InCluster": true}}
  }
}
EOF
cat > srvless.json <<EOF
{
  "ClusterName": "lab-msk-srvless",
  "Serverless": {
    "VpcConfigs": [{"SubnetIds": ["$S1","$S2"], "SecurityGroupIds": ["$SG"]}],
    "ClientAuthentication": {"Sasl": {"Iam": {"Enabled": true}}}
  }
}
EOF
PARN=$(aws kafka create-cluster-v2 --region $R --cli-input-json file://prov.json --query ClusterArn --output text)
SARN=$(aws kafka create-cluster-v2 --region $R --cli-input-json file://srvless.json --query ClusterArn --output text)
echo "PARN=$PARN SARN=$SARN"

for ARN in $SARN $PARN; do
  until [ "$(aws kafka describe-cluster-v2 --region $R --cluster-arn $ARN --query ClusterInfo.State --output text)" = "ACTIVE" ]; do
    echo "wait $(aws kafka describe-cluster-v2 --region $R --cluster-arn $ARN --query '[ClusterInfo.ClusterName,ClusterInfo.State]' --output text)"; sleep 60
  done
done

echo "===== list-clusters-v2 (타입 구분) ====="
aws kafka list-clusters-v2 --region $R --query 'ClusterInfoList[].[ClusterName,ClusterType,State]' --output text

echo "===== SERVERLESS: describe / bootstrap ====="
aws kafka describe-cluster-v2 --region $R --cluster-arn $SARN --query 'ClusterInfo.{type:ClusterType,serverless:Serverless}' --output json
aws kafka get-bootstrap-brokers --region $R --cluster-arn $SARN --output json

echo "===== PROVISIONED: describe / bootstrap ====="
aws kafka describe-cluster-v2 --region $R --cluster-arn $PARN --query 'ClusterInfo.{type:ClusterType,brokers:Provisioned.NumberOfBrokerNodes,inst:Provisioned.BrokerNodeGroupInfo.InstanceType,ver:Provisioned.CurrentBrokerSoftwareInfo.KafkaVersion,storage:Provisioned.BrokerNodeGroupInfo.StorageInfo,zk:Provisioned.ZookeeperConnectString}' --output json
aws kafka get-bootstrap-brokers --region $R --cluster-arn $PARN --output json

echo "===== provisioned 만 가능한 조작 (스토리지/브로커 수) ====="
aws kafka list-nodes --region $R --cluster-arn $PARN --query 'NodeInfoList[].[NodeARN,BrokerNodeInfo.BrokerId,BrokerNodeInfo.ClientSubnet]' --output text
echo "--- serverless 에 같은 API 를 쓰면? ---"
aws kafka list-nodes --region $R --cluster-arn $SARN --output text 2>&1 | tail -2

echo "===== teardown ====="
aws kafka delete-cluster --region $R --cluster-arn $PARN >/dev/null
aws kafka delete-cluster --region $R --cluster-arn $SARN >/dev/null
until [ "$(aws kafka list-clusters-v2 --region $R --query 'length(ClusterInfoList)' --output text)" = "0" ]; do sleep 60; done
aws ec2 delete-subnet --region $R --subnet-id $S1
aws ec2 delete-subnet --region $R --subnet-id $S2
aws ec2 revoke-security-group-ingress --region $R --group-id $SG --protocol tcp --port 9092-9098 --source-group $SG >/dev/null
aws ec2 delete-vpc --region $R --vpc-id $VPC
echo DONE
