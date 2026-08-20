#!/usr/bin/env bash
# 케이스 02 — FireLens(Fluent Bit 사이드카) → CloudWatch Logs. Fargate 라이브 검증됨.
# app(nginx) stdout/stderr → awsfirelens 드라이버 → log-router(Fluent Bit) → CloudWatch.
# 리전 전용. 이름 lab-apse1-*. VPC/역할/클러스터/태스크까지 자립 생성.
set -euo pipefail
export R=${R:-ap-southeast-1} ACCT=$(aws sts get-caller-identity --query Account --output text)
STATE=${STATE:-/tmp/lab-apse1-ecs-state.env}   # 04-firelens-s3 가 재사용

# --- IAM 역할 -------------------------------------------------------------
# exec 역할: 이미지 pull + 라우터 사이드카 awslogs. 관리형 정책엔 CreateLogGroup 이 없어
#            awslogs-create-group=true 를 쓰면 인라인으로 logs:CreateLogGroup 을 더해야 함(함정).
# task 역할: Fluent Bit 이 앱 로그를 CloudWatch/S3 로 보낼 때 이 자격증명을 씀.
TRUST='{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":"ecs-tasks.amazonaws.com"},"Action":"sts:AssumeRole"}]}'
aws iam create-role --role-name lab-apse1-ecs-exec-apse1 --assume-role-policy-document "$TRUST" 2>/dev/null || true
aws iam attach-role-policy --role-name lab-apse1-ecs-exec-apse1 \
  --policy-arn arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy
aws iam put-role-policy --role-name lab-apse1-ecs-exec-apse1 --policy-name create-log-group \
  --policy-document '{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Action":["logs:CreateLogGroup"],"Resource":"*"}]}'
aws iam create-role --role-name lab-apse1-ecs-task-apse1 --assume-role-policy-document "$TRUST" 2>/dev/null || true
aws iam put-role-policy --role-name lab-apse1-ecs-task-apse1 --policy-name firelens-out \
  --policy-document '{"Version":"2012-10-17","Statement":[{"Sid":"logs","Effect":"Allow","Action":["logs:CreateLogGroup","logs:CreateLogStream","logs:PutLogEvents","logs:PutRetentionPolicy","logs:DescribeLogGroups","logs:DescribeLogStreams"],"Resource":"*"},{"Sid":"s3out","Effect":"Allow","Action":["s3:PutObject"],"Resource":"arn:aws:s3:::lab-apse1-*/*"}]}'
EXEC_ARN=$(aws iam get-role --role-name lab-apse1-ecs-exec-apse1 --query Role.Arn --output text)
TASK_ARN=$(aws iam get-role --role-name lab-apse1-ecs-task-apse1 --query Role.Arn --output text)
sleep 8   # IAM 전파

# --- VPC (퍼블릭 서브넷 + IGW) — Fargate 가 퍼블릭IP 로 이미지 pull + CW 도달 ----
VPC=$(aws ec2 create-vpc --region $R --cidr-block 10.90.0.0/16 \
  --tag-specifications 'ResourceType=vpc,Tags=[{Key=Name,Value=lab-apse1-vpc}]' --query Vpc.VpcId --output text)
aws ec2 modify-vpc-attribute --region $R --vpc-id $VPC --enable-dns-hostnames
IGW=$(aws ec2 create-internet-gateway --region $R --query InternetGateway.InternetGatewayId --output text)
aws ec2 attach-internet-gateway --region $R --internet-gateway-id $IGW --vpc-id $VPC
AZ=$(aws ec2 describe-availability-zones --region $R --query 'AvailabilityZones[0].ZoneName' --output text)
SUBNET=$(aws ec2 create-subnet --region $R --vpc-id $VPC --cidr-block 10.90.1.0/24 --availability-zone $AZ \
  --query Subnet.SubnetId --output text)
aws ec2 modify-subnet-attribute --region $R --subnet-id $SUBNET --map-public-ip-on-launch
RT=$(aws ec2 create-route-table --region $R --vpc-id $VPC --query RouteTable.RouteTableId --output text)
aws ec2 create-route --region $R --route-table-id $RT --destination-cidr-block 0.0.0.0/0 --gateway-id $IGW >/dev/null
ASSOC=$(aws ec2 associate-route-table --region $R --route-table-id $RT --subnet-id $SUBNET --query AssociationId --output text)
SG=$(aws ec2 create-security-group --region $R --group-name lab-apse1-ecs-sg \
  --description "lab-apse1 ecs egress" --vpc-id $VPC --query GroupId --output text)

# --- 클러스터 + 태스크 정의(FireLens → CloudWatch) ------------------------
aws ecs create-cluster --region $R --cluster-name lab-apse1-firelens --query cluster.clusterArn --output text
aws ecs register-task-definition --region $R --cli-input-json "$(cat <<JSON
{ "family":"lab-apse1-firelens-cw","networkMode":"awsvpc","requiresCompatibilities":["FARGATE"],
  "cpu":"512","memory":"1024","executionRoleArn":"$EXEC_ARN","taskRoleArn":"$TASK_ARN",
  "containerDefinitions":[
    {"name":"app","image":"public.ecr.aws/nginx/nginx:latest","essential":true,"portMappings":[{"containerPort":80}],
     "logConfiguration":{"logDriver":"awsfirelens","options":{
       "Name":"cloudwatch","region":"$R","log_group_name":"/ecs/lab-apse1-app",
       "auto_create_group":"true","log_stream_prefix":"app-"}}},
    {"name":"log-router","image":"public.ecr.aws/aws-observability/aws-for-fluent-bit:stable","essential":true,
     "firelensConfiguration":{"type":"fluentbit","options":{"enable-ecs-log-metadata":"true"}},
     "logConfiguration":{"logDriver":"awslogs","options":{
       "awslogs-group":"/ecs/lab-apse1-router","awslogs-region":"$R",
       "awslogs-stream-prefix":"router","awslogs-create-group":"true"}}}
  ]}
JSON
)" --query 'taskDefinition.[family,revision]' --output text

TASKARN=$(aws ecs run-task --region $R --cluster lab-apse1-firelens --launch-type FARGATE --count 1 \
  --task-definition lab-apse1-firelens-cw \
  --network-configuration "awsvpcConfiguration={subnets=[$SUBNET],securityGroups=[$SG],assignPublicIp=ENABLED}" \
  --query 'tasks[0].taskArn' --output text)

cat > "$STATE" <<EOF
VPC=$VPC
IGW=$IGW
SUBNET=$SUBNET
RT=$RT
ASSOC=$ASSOC
SG=$SG
CW_TASK=$TASKARN
EOF
echo "run-task: $TASKARN"
echo "상태 저장: $STATE"
echo "검증(2~3분 뒤): aws logs filter-log-events --region $R --log-group-name /ecs/lab-apse1-app --limit 5 --query 'events[].message'"
