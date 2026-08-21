#!/bin/bash
# ecs-logging 03 — FireLens → OpenSearch 라이브 검증 (ap-northeast-2)
set -x
R=ap-northeast-2
D="$(cd "$(dirname "$0")" && pwd)"; cd "$D"
. ./oslog.env    # VPC= IGW= SUB= RT= SG=
EP=$(aws opensearch describe-domain --region $R --domain-name lab-oslog --query DomainStatus.Endpoint --output text)
echo "OS_ENDPOINT=$EP"
A=$(aws sts get-caller-identity --query Account --output text)
sed "s|OSHOST|$EP|; s|ACCTID|$A|g" td-tpl.json > td.json
python3 -c "import json;json.load(open('td.json'));print('td.json ok')"

TD=$(aws ecs register-task-definition --region $R --cli-input-json file://td.json --query 'taskDefinition.taskDefinitionArn' --output text)
echo "TD=$TD"
TASK=$(aws ecs run-task --region $R --cluster lab-oslog-cluster --launch-type FARGATE --task-definition $TD \
  --network-configuration "awsvpcConfiguration={subnets=[$SUB],securityGroups=[$SG],assignPublicIp=ENABLED}" \
  --query 'tasks[0].taskArn' --output text)
echo "TASK=$TASK"
[ -z "$TASK" ] && exit 1
while true; do
  S=$(aws ecs describe-tasks --region $R --cluster lab-oslog-cluster --tasks $TASK --query 'tasks[0].lastStatus' --output text)
  echo "status=$S"
  [ "$S" = "RUNNING" ] && break
  [ "$S" = "STOPPED" ] && break
  sleep 10
done
aws ecs describe-tasks --region $R --cluster lab-oslog-cluster --tasks $TASK \
  --query 'tasks[0].{status:lastStatus,reason:stoppedReason,containers:containers[].[name,lastStatus,reason]}' --output json

echo "===== 90초 로그 적재 대기 ====="
sleep 90
echo "===== OpenSearch 인덱스 확인 ====="
python3 osquery.py "$EP" "/_cat/indices?v"
echo "===== 문서 검색(앱 로그 + ecs 메타) ====="
python3 osquery.py "$EP" "/ecs-logs*/_search?size=3&pretty"
echo "===== log-router 사이드카 로그 ====="
aws logs filter-log-events --region $R --log-group-name /ecs/lab-firelens-router --limit 20 \
  --query 'events[].message' --output text 2>&1 | tr '\t' '\n' | tail -15
echo RUNDONE
