# ECS (+ CloudMap)

**트리거 문구** — "ECS 에서 구동", "Fargate", "Task Definition", "서비스 디스커버리"(→ CloudMap), "FireLens/awslogs 로그", "ELB 연동", "중앙 집중 로깅"(ECS logging 모듈).

**전제**
```bash
export R=ap-northeast-2 ACCT=$(aws sts get-caller-identity --query Account --output text)
```
EKS 대신 ECS 로 나올 수 있다(1과제 "ECS 혹은 EKS", 2025 logging/monitoring 모듈은 ECS).

---

## 케이스 A — Fargate cluster + taskdef + service [검증됨: task RUNNING]

```bash
aws ecs create-cluster --region $R --cluster-name lab-ecs

# task execution role (이미지 pull + 로그)
cat > t.json <<'JSON'
{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":"ecs-tasks.amazonaws.com"},"Action":"sts:AssumeRole"}]}
JSON
aws iam create-role --role-name lab-ecs-exec --assume-role-policy-document file://t.json
aws iam attach-role-policy --role-name lab-ecs-exec --policy-arn arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy
sleep 10
EXEC=$(aws iam get-role --role-name lab-ecs-exec --query Role.Arn --output text)

aws logs create-log-group --region $R --log-group-name /ecs/lab

# task definition (awsvpc + Fargate + awslogs)
cat > td.json <<JSON
{
  "family": "lab-task", "networkMode": "awsvpc",
  "requiresCompatibilities": ["FARGATE"], "cpu": "256", "memory": "512",
  "executionRoleArn": "$EXEC",
  "containerDefinitions": [{
    "name": "web", "image": "public.ecr.aws/nginx/nginx:latest",
    "portMappings": [{"containerPort": 80}], "essential": true,
    "logConfiguration": {"logDriver": "awslogs", "options": {
      "awslogs-group": "/ecs/lab", "awslogs-region": "$R", "awslogs-stream-prefix": "web"}}
  }]
}
JSON
aws ecs register-task-definition --region $R --cli-input-json file://td.json

# service (Fargate)
aws ecs create-service --region $R --cluster lab-ecs --service-name lab-svc \
  --task-definition lab-task --desired-count 1 --launch-type FARGATE \
  --network-configuration "awsvpcConfiguration={subnets=[$SUB],securityGroups=[$SG],assignPublicIp=DISABLED}"
```
- **`awsvpc` 모드**: task 마다 ENI. `taskRoleArn`(앱 권한) vs `executionRoleArn`(pull+로그) **구분**.
- **`assignPublicIp`**: public 서브넷이면 ENABLED(NAT 없이 이미지 pull), private+NAT 면 DISABLED.

## ★ 케이스 B — CloudMap 서비스 디스커버리 [검증됨: 인스턴스 자동등록]

ECS service 를 CloudMap 에 연결하면 **task IP 가 DNS(A레코드)로 자동 등록**된다. 마이크로서비스 간 `web.lab.local` 로 호출.

```bash
# private DNS 네임스페이스 (VPC 연결, 비동기)
OP=$(aws servicediscovery create-private-dns-namespace --region $R --name lab.local --vpc $VPC --query OperationId --output text)
# SUCCESS 대기 후 네임스페이스 ID
NSID=$(aws servicediscovery get-operation --region $R --operation-id $OP --query 'Operation.Targets.NAMESPACE' --output text)

# CloudMap service (A레코드)
SD=$(aws servicediscovery create-service --region $R --name web \
  --namespace-id $NSID --dns-config "NamespaceId=$NSID,DnsRecords=[{Type=A,TTL=60}]" \
  --health-check-custom-config FailureThreshold=1 --query 'Service.Arn' --output text)

# ECS service 에 --service-registries 로 연결
aws ecs create-service --region $R --cluster lab-ecs --service-name lab-svc \
  --task-definition lab-task --desired-count 1 --launch-type FARGATE \
  --network-configuration "awsvpcConfiguration={subnets=[$SUB],securityGroups=[$SG],assignPublicIp=DISABLED}" \
  --service-registries "registryArn=$SD"

# task IP 자동 등록 확인
SDID=$(echo $SD | awk -F/ '{print $NF}')
aws servicediscovery list-instances --region $R --service-id $SDID --query 'Instances[].Attributes.AWS_INSTANCE_IPV4' --output text
# 다른 task 에서: curl http://web.lab.local
```

## 케이스 C — ALB 연동

```bash
# target-type ip (Fargate awsvpc). TG → service loadBalancers
aws ecs create-service --region $R --cluster lab-ecs --service-name lab-web \
  --task-definition lab-task --desired-count 2 --launch-type FARGATE \
  --network-configuration "awsvpcConfiguration={subnets=[$SUB1,$SUB2],securityGroups=[$SG]}" \
  --load-balancers "targetGroupArn=$TG,containerName=web,containerPort=80" \
  --health-check-grace-period-seconds 60
```
TG 는 **target-type=ip**(instance 아님). ALB SG → task SG 80 허용.

## 케이스 D — FireLens (중앙 집중 로깅, 2025 logging 모듈)

```json
"containerDefinitions": [
  {"name":"app","image":"...","logConfiguration":{"logDriver":"awsfirelens",
    "options":{"Name":"cloudwatch","region":"ap-northeast-2","log_group_name":"/ecs/app","auto_create_group":"true","log_stream_prefix":"app-"}}},
  {"name":"log-router","image":"public.ecr.aws/aws-observability/aws-for-fluent-bit:stable",
    "essential":true,
    "firelensConfiguration":{"type":"fluentbit","options":{"enable-ecs-log-metadata":"true"}}}
]
```
사이드카(log-router)가 앱 로그를 받아 CloudWatch/OpenSearch/S3 로. `awslogs`(단순) vs `awsfirelens`(가공·다중 목적지).

## 케이스 E — ECS Exec (디버깅)

```bash
aws ecs update-service --region $R --cluster lab-ecs --service lab-svc --enable-execute-command
aws ecs execute-command --region $R --cluster lab-ecs --task <task-id> \
  --container web --interactive --command "/bin/sh"
```
task role 에 SSM 권한 필요. 채점이 컨테이너 내부 확인할 때.

## 검증

```bash
aws ecs describe-services --region $R --cluster lab-ecs --services lab-svc \
  --query 'services[0].[status,runningCount,launchType]' --output text   # ACTIVE 1 FARGATE
aws ecs list-tasks --region $R --cluster lab-ecs --query taskArns --output text
aws servicediscovery list-instances --region $R --service-id $SDID --query 'Instances[].Attributes.AWS_INSTANCE_IPV4' --output text
aws logs describe-log-streams --region $R --log-group-name /ecs/lab --query 'logStreams[].logStreamName' --output text
```

## 함정

- **taskRole vs executionRole** — execution 은 pull+로그(ECS 가 사용), task 는 앱 권한(컨테이너가 사용). 앱이 S3/DDB 접근하면 taskRole 에.
- **awsvpc = ENI 마다 SG** — ALB SG 에서 task SG 로 컨테이너 포트 허용. 안 하면 TG unhealthy.
- **private 서브넷 + NAT 없음 = 이미지 pull 실패** — assignPublicIp ENABLED(public) 또는 ECR/S3 endpoint.
- **CloudMap 네임스페이스 생성은 비동기** — operation SUCCESS 대기.
- **desired-count 0 이면 task 없음** — service 는 ACTIVE 여도 runningCount 0.
- **health-check-grace-period** 없으면 앱 기동 전 ALB 가 unhealthy 판정 → 무한 재시작.
- FireLens 는 **log-router 사이드카가 essential** 이어야 앱과 생명주기 동기화.

## 정리
```bash
aws ecs update-service --region $R --cluster lab-ecs --service lab-svc --desired-count 0
aws ecs delete-service --region $R --cluster lab-ecs --service lab-svc --force
aws servicediscovery delete-service --region $R --service-id $SDID
aws servicediscovery delete-namespace --region $R --id $NSID
aws ecs delete-cluster --region $R --cluster lab-ecs
```
