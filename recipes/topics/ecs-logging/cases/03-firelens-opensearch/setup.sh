#!/bin/bash
# ecs-logging 03 — 인프라 생성(OpenSearch 도메인 + VPC + ECS 클러스터 + role). 실검증 스크립트.
# 사용: bash setup.sh   →  (도메인 ~50분)  →  bash verify.sh  →  bash teardown.sh
set -x
R=${R:-ap-northeast-2}
A=$(aws sts get-caller-identity --query Account --output text)
D="$(cd "$(dirname "$0")" && pwd)"; cd "$D"

# 1) OpenSearch 도메인 (가장 오래 걸리므로 먼저)
cat > osaccess.json <<EOF
{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"AWS":"arn:aws:iam::$A:root"},"Action":"es:ESHttp*","Resource":"arn:aws:es:$R:$A:domain/lab-oslog/*"}]}
EOF
aws opensearch create-domain --region $R --domain-name lab-oslog \
  --engine-version OpenSearch_2.19 \
  --cluster-config InstanceType=t3.small.search,InstanceCount=1,DedicatedMasterEnabled=false,ZoneAwarenessEnabled=false \
  --ebs-options EBSEnabled=true,VolumeType=gp3,VolumeSize=10 \
  --node-to-node-encryption-options Enabled=true --encryption-at-rest-options Enabled=true \
  --domain-endpoint-options EnforceHTTPS=true,TLSSecurityPolicy=Policy-Min-TLS-1-2-2019-07 \
  --access-policies "$(cat osaccess.json)" --tag-list Key=Name,Value=lab-oslog \
  --query 'DomainStatus.[DomainName,Created]' --output text

# 2) VPC + 퍼블릭 서브넷 (Fargate 가 ECR/OpenSearch 로 나가야 함)
VPC=$(aws ec2 create-vpc --region $R --cidr-block 10.90.0.0/16 --query Vpc.VpcId --output text)
aws ec2 create-tags --region $R --resources $VPC --tags Key=Name,Value=lab-oslog-vpc
aws ec2 modify-vpc-attribute --region $R --vpc-id $VPC --enable-dns-hostnames
IGW=$(aws ec2 create-internet-gateway --region $R --query InternetGateway.InternetGatewayId --output text)
aws ec2 attach-internet-gateway --region $R --vpc-id $VPC --internet-gateway-id $IGW
SUB=$(aws ec2 create-subnet --region $R --vpc-id $VPC --cidr-block 10.90.1.0/24 --availability-zone ${R}a --query Subnet.SubnetId --output text)
aws ec2 modify-subnet-attribute --region $R --subnet-id $SUB --map-public-ip-on-launch
RT=$(aws ec2 create-route-table --region $R --vpc-id $VPC --query RouteTable.RouteTableId --output text)
aws ec2 create-route --region $R --route-table-id $RT --destination-cidr-block 0.0.0.0/0 --gateway-id $IGW >/dev/null
aws ec2 associate-route-table --region $R --route-table-id $RT --subnet-id $SUB >/dev/null
SG=$(aws ec2 describe-security-groups --region $R --filters Name=vpc-id,Values=$VPC Name=group-name,Values=default --query 'SecurityGroups[0].GroupId' --output text)
echo "VPC=$VPC IGW=$IGW SUB=$SUB RT=$RT SG=$SG" | tee oslog.env

# 3) ECS 클러스터 + 로그그룹
aws logs create-log-group --region $R --log-group-name /ecs/lab-firelens-router
aws ecs create-cluster --region $R --cluster-name lab-oslog-cluster --query 'cluster.status' --output text

# 4) IAM — execution(+logs:CreateLogGroup) / task(es:ESHttp*)
cat > trust.json <<'EOF'
{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":"ecs-tasks.amazonaws.com"},"Action":"sts:AssumeRole"}]}
EOF
aws iam create-role --role-name lab-oslog-exec --assume-role-policy-document file://trust.json --query Role.Arn --output text
aws iam attach-role-policy --role-name lab-oslog-exec --policy-arn arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy
aws iam put-role-policy --role-name lab-oslog-exec --policy-name cw-creategroup \
  --policy-document '{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Action":["logs:CreateLogGroup"],"Resource":"*"}]}'
aws iam create-role --role-name lab-oslog-task --assume-role-policy-document file://trust.json --query Role.Arn --output text
aws iam put-role-policy --role-name lab-oslog-task --policy-name es-http \
  --policy-document "{\"Version\":\"2012-10-17\",\"Statement\":[{\"Effect\":\"Allow\",\"Action\":[\"es:ESHttp*\"],\"Resource\":\"arn:aws:es:$R:$A:domain/lab-oslog/*\"}]}"
echo "SETUPDONE — 도메인 Endpoint 가 뜰 때까지(실측 ~50분) 기다린 뒤 verify.sh"
