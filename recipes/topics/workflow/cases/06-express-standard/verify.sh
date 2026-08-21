#!/bin/bash
# workflow 06 — Express vs Standard 라이브 검증 (us-west-2)
set -x
R=us-west-2
A=$(aws sts get-caller-identity --query Account --output text)
cd "$(dirname "$0")"

cat > sfn-trust.json <<'EOF'
{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":"states.amazonaws.com"},"Action":"sts:AssumeRole"}]}
EOF
cat > sfn-logs.json <<'EOF'
{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Action":["logs:CreateLogDelivery","logs:GetLogDelivery","logs:UpdateLogDelivery","logs:DeleteLogDelivery","logs:ListLogDeliveries","logs:PutResourcePolicy","logs:DescribeResourcePolicies","logs:DescribeLogGroups"],"Resource":"*"}]}
EOF
cat > wf.json <<'EOF'
{"Comment":"express vs standard 비교용 동일 ASL","StartAt":"Stamp","States":{"Stamp":{"Type":"Pass","Parameters":{"ok.$":"$.id","at.$":"$$.Execution.StartTime"},"End":true}}}
EOF

aws iam create-role --role-name lab-wf06-role --assume-role-policy-document file://sfn-trust.json --query Role.Arn --output text
aws iam put-role-policy --role-name lab-wf06-role --policy-name logs --policy-document file://sfn-logs.json
ROLE=arn:aws:iam::$A:role/lab-wf06-role
aws logs create-log-group --region $R --log-group-name /aws/vendedlogs/states/lab-exp 2>&1 | head -1
sleep 12

STD=$(aws stepfunctions create-state-machine --region $R --name lab-std --type STANDARD \
  --definition file://wf.json --role-arn $ROLE --query stateMachineArn --output text)
EXP=$(aws stepfunctions create-state-machine --region $R --name lab-exp --type EXPRESS \
  --definition file://wf.json --role-arn $ROLE \
  --logging-configuration "{\"level\":\"ALL\",\"includeExecutionData\":true,\"destinations\":[{\"cloudWatchLogsLogGroup\":{\"logGroupArn\":\"arn:aws:logs:$R:$A:log-group:/aws/vendedlogs/states/lab-exp:*\"}}]}" \
  --query stateMachineArn --output text)
echo "STD=$STD EXP=$EXP"

echo "===== STANDARD: start-execution → 실행이력 조회 ====="
EX=$(aws stepfunctions start-execution --region $R --state-machine-arn $STD --name run1 --input '{"id":"s-1"}' --query executionArn --output text)
sleep 5
aws stepfunctions describe-execution --region $R --execution-arn $EX --query '[status,output]' --output text
echo "--- list-executions (STANDARD) ---"
aws stepfunctions list-executions --region $R --state-machine-arn $STD --query 'executions[].[name,status]' --output text

echo "===== EXPRESS: start-sync-execution (동기 결과) ====="
aws stepfunctions start-sync-execution --region $R --state-machine-arn $EXP --name run1 --input '{"id":"e-1"}' \
  --query '[status,output]' --output text

echo "===== EXPRESS: list-executions → 이력 없음(증명) ====="
aws stepfunctions list-executions --region $R --state-machine-arn $EXP --query 'executions[].[name,status]' --output text 2>&1

echo "===== EXPRESS: 이력은 CloudWatch Logs 에만 ====="
sleep 25
aws logs filter-log-events --region $R --log-group-name /aws/vendedlogs/states/lab-exp \
  --query 'events[].message' --output text 2>&1 | head -c 1200
echo
echo "===== teardown ====="
aws stepfunctions delete-state-machine --region $R --state-machine-arn $STD
aws stepfunctions delete-state-machine --region $R --state-machine-arn $EXP
aws logs delete-log-group --region $R --log-group-name /aws/vendedlogs/states/lab-exp
aws iam delete-role-policy --role-name lab-wf06-role --policy-name logs
aws iam delete-role --role-name lab-wf06-role
echo DONE
