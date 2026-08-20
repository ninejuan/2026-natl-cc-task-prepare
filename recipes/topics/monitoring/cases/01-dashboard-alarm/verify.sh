#!/usr/bin/env bash
# Live verify: CloudWatch dashboard (ALB/ECS-style widgets) + metric alarm
# (treat-missing-data=notBreaching + SNS action). Usage: ./verify.sh {deploy|test|teardown}
set -uo pipefail
export AWS_PAGER=""
R=ap-northeast-1
ACCT=$(aws sts get-caller-identity --query Account --output text)

DASH=lab-apne1-dashboard
ALARM=lab-apne1-alb-5xx
TOPIC_NAME=lab-apne1-monitoring-alarm
TOPIC_ARN="arn:aws:sns:${R}:${ACCT}:${TOPIC_NAME}"

deploy() {
  echo "== deploy =="
  aws sns create-topic --region $R --name $TOPIC_NAME >/dev/null
  echo "topic $TOPIC_ARN"

  # Dashboard: ALB RequestCount + TargetResponseTime, ECS CPU/Mem (widgets prove the mechanics;
  # a real ALB/ECS isn't required for put-dashboard to succeed).
  cat > /tmp/dash.json <<JSON
{"widgets":[
  {"type":"metric","x":0,"y":0,"width":12,"height":6,"properties":{
    "title":"ALB RequestCount / 5xx","region":"$R","stat":"Sum","period":60,
    "metrics":[
      ["AWS/ApplicationELB","RequestCount","LoadBalancer","app/lab-apne1-alb/0000000000000000"],
      ["AWS/ApplicationELB","HTTPCode_Target_5XX_Count","LoadBalancer","app/lab-apne1-alb/0000000000000000"]
    ]}},
  {"type":"metric","x":12,"y":0,"width":12,"height":6,"properties":{
    "title":"ALB TargetResponseTime","region":"$R","stat":"Average","period":60,
    "metrics":[["AWS/ApplicationELB","TargetResponseTime","LoadBalancer","app/lab-apne1-alb/0000000000000000"]]}},
  {"type":"metric","x":0,"y":6,"width":12,"height":6,"properties":{
    "title":"ECS CPU / Memory","region":"$R","stat":"Average","period":60,
    "metrics":[
      ["AWS/ECS","CPUUtilization","ClusterName","lab-apne1-ecs","ServiceName","lab-apne1-svc"],
      ["AWS/ECS","MemoryUtilization","ClusterName","lab-apne1-ecs","ServiceName","lab-apne1-svc"]
    ]}}
]}
JSON
  aws cloudwatch put-dashboard --region $R --dashboard-name $DASH --dashboard-body file:///tmp/dash.json
  echo "dashboard $DASH put"

  # Alarm: ALB backend 5xx, treat-missing-data=notBreaching (no traffic -> stays OK, not INSUFFICIENT_DATA)
  aws cloudwatch put-metric-alarm --region $R \
    --alarm-name $ALARM \
    --alarm-description "lab apne1: ALB target 5xx spike" \
    --namespace AWS/ApplicationELB --metric-name HTTPCode_Target_5XX_Count \
    --dimensions Name=LoadBalancer,Value=app/lab-apne1-alb/0000000000000000 \
    --statistic Sum --period 60 --evaluation-periods 1 --threshold 10 \
    --comparison-operator GreaterThanThreshold \
    --treat-missing-data notBreaching \
    --alarm-actions "$TOPIC_ARN"
  echo "alarm $ALARM put"
  echo "== deploy done =="
}

test_it() {
  echo "== verify =="
  echo "-- dashboards --"
  aws cloudwatch list-dashboards --region $R --query 'DashboardEntries[].DashboardName' --output text
  echo "-- alarm (name / state / missing-data / action) --"
  aws cloudwatch describe-alarms --region $R --alarm-names $ALARM \
    --query 'MetricAlarms[0].[AlarmName,StateValue,TreatMissingData,AlarmActions[0]]' --output text
  echo "-- optional: force ALARM via set-alarm-state to prove SNS action wiring --"
  aws cloudwatch set-alarm-state --region $R --alarm-name $ALARM \
    --state-value ALARM --state-reason "lab verify: manual transition" 2>/dev/null || true
  sleep 5
  aws cloudwatch describe-alarms --region $R --alarm-names $ALARM \
    --query 'MetricAlarms[0].[AlarmName,StateValue,StateReason]' --output text
}

teardown() {
  echo "== teardown =="
  aws cloudwatch delete-alarms --region $R --alarm-names $ALARM 2>/dev/null || true
  aws cloudwatch delete-dashboards --region $R --dashboard-names $DASH 2>/dev/null || true
  aws sns delete-topic --region $R --topic-arn "$TOPIC_ARN" 2>/dev/null || true
  echo "== teardown done =="
}

case "${1:-}" in
  deploy) deploy ;;
  test) test_it ;;
  teardown) teardown ;;
  *) echo "usage: $0 {deploy|test|teardown}"; exit 1 ;;
esac
