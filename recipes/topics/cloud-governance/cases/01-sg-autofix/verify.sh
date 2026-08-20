#!/usr/bin/env bash
# Live verify: SG 0.0.0.0/0 auto-remediation (EventBridge/CloudTrail + Lambda).
# Deterministic names = no state file; teardown finds everything by name/tag.
# Usage: ./verify.sh {deploy|test|teardown}
#   deploy   - VPC+SG, SNS, IAM role, Lambda(handler.py), CloudTrail, EventBridge rule
#   test     - add tcp/22 0.0.0.0/0, fire remediation, confirm ingress gone (before/after)
#   teardown - remove everything
set -uo pipefail
export AWS_PAGER=""
R=ap-northeast-1
ACCT=$(aws sts get-caller-identity --query Account --output text)
HERE="$(cd "$(dirname "$0")" && pwd)"

VPC_NAME=lab-apne1-govern-vpc
SG_NAME=lab-apne1-govern-sg
TOPIC_NAME=lab-apne1-sg-autofix
ROLE=lab-apne1-sg-autofix-apne1
FN=lab-apne1-sg-autofix
RULE=lab-apne1-sg-autofix
TRAIL=lab-apne1-trail
TRAIL_BUCKET=lab-apne1-cloudtrail-${ACCT}

vpc_id()  { aws ec2 describe-vpcs --region $R --filters "Name=tag:Name,Values=$VPC_NAME" --query "Vpcs[0].VpcId" --output text 2>/dev/null; }
sg_id()   { local v=$1; aws ec2 describe-security-groups --region $R --filters "Name=vpc-id,Values=$v" "Name=group-name,Values=$SG_NAME" --query "SecurityGroups[0].GroupId" --output text 2>/dev/null; }
topic_arn(){ echo "arn:aws:sns:${R}:${ACCT}:${TOPIC_NAME}"; }

deploy() {
  echo "== deploy =="
  local V; V=$(vpc_id)
  if [ "$V" = "None" ] || [ -z "$V" ]; then
    V=$(aws ec2 create-vpc --region $R --cidr-block 10.90.0.0/16 --query Vpc.VpcId --output text)
    aws ec2 create-tags --region $R --resources "$V" --tags Key=Name,Value=$VPC_NAME
    echo "created VPC $V"
  else echo "reuse VPC $V"; fi

  local SG; SG=$(sg_id "$V")
  if [ "$SG" = "None" ] || [ -z "$SG" ]; then
    SG=$(aws ec2 create-security-group --region $R --group-name $SG_NAME --description "lab apne1 governance" --vpc-id "$V" --query GroupId --output text)
    aws ec2 create-tags --region $R --resources "$SG" --tags Key=Name,Value=$SG_NAME
    echo "created SG $SG"
  else echo "reuse SG $SG"; fi

  local TOPIC; TOPIC=$(aws sns create-topic --region $R --name $TOPIC_NAME --query TopicArn --output text)
  echo "topic $TOPIC"

  # IAM role (global)
  if ! aws iam get-role --role-name $ROLE >/dev/null 2>&1; then
    aws iam create-role --role-name $ROLE \
      --assume-role-policy-document '{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":"lambda.amazonaws.com"},"Action":"sts:AssumeRole"}]}' >/dev/null
    aws iam attach-role-policy --role-name $ROLE --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole
    aws iam put-role-policy --role-name $ROLE --policy-name sg-remediate \
      --policy-document '{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Action":["ec2:RevokeSecurityGroupIngress","ec2:DescribeSecurityGroups"],"Resource":"*"},{"Effect":"Allow","Action":"sns:Publish","Resource":"*"}]}'
    echo "created role $ROLE; sleeping 12s for IAM propagation"; sleep 12
  else echo "reuse role $ROLE"; fi
  local ROLE_ARN; ROLE_ARN=$(aws iam get-role --role-name $ROLE --query Role.Arn --output text)

  # Lambda package
  local ZIP; ZIP=$(mktemp -d)/fn.zip
  (cd "$HERE" && zip -q "$ZIP" handler.py)
  if aws lambda get-function --region $R --function-name $FN >/dev/null 2>&1; then
    aws lambda update-function-code --region $R --function-name $FN --zip-file "fileb://$ZIP" >/dev/null
    echo "updated lambda code"
  else
    # retry loop for IAM role eventual consistency
    for i in 1 2 3 4 5; do
      if aws lambda create-function --region $R --function-name $FN \
          --runtime python3.12 --handler handler.handler --role "$ROLE_ARN" \
          --timeout 30 --environment "Variables={TOPIC=$(topic_arn)}" \
          --zip-file "fileb://$ZIP" >/dev/null 2>/tmp/lerr; then echo "created lambda $FN"; break; fi
      echo "lambda create retry $i ..."; sleep 8
    done
  fi
  local FN_ARN; FN_ARN=$(aws lambda get-function --region $R --function-name $FN --query Configuration.FunctionArn --output text)
  echo "lambda $FN_ARN"

  # CloudTrail (management events) so EventBridge can fire in real time
  if ! aws s3api head-bucket --bucket $TRAIL_BUCKET 2>/dev/null; then
    aws s3api create-bucket --region $R --bucket $TRAIL_BUCKET --create-bucket-configuration LocationConstraint=$R >/dev/null
  fi
  aws s3api put-bucket-policy --bucket $TRAIL_BUCKET --policy "{\"Version\":\"2012-10-17\",\"Statement\":[{\"Sid\":\"AWSCloudTrailAclCheck\",\"Effect\":\"Allow\",\"Principal\":{\"Service\":\"cloudtrail.amazonaws.com\"},\"Action\":\"s3:GetBucketAcl\",\"Resource\":\"arn:aws:s3:::${TRAIL_BUCKET}\"},{\"Sid\":\"AWSCloudTrailWrite\",\"Effect\":\"Allow\",\"Principal\":{\"Service\":\"cloudtrail.amazonaws.com\"},\"Action\":\"s3:PutObject\",\"Resource\":\"arn:aws:s3:::${TRAIL_BUCKET}/AWSLogs/${ACCT}/*\",\"Condition\":{\"StringEquals\":{\"s3:x-amz-acl\":\"bucket-owner-full-control\"}}}]}"
  if ! aws cloudtrail describe-trails --region $R --trail-name-list $TRAIL --query 'trailList[0]' --output text 2>/dev/null | grep -q $TRAIL; then
    aws cloudtrail create-trail --region $R --name $TRAIL --s3-bucket-name $TRAIL_BUCKET --is-multi-region-trail >/dev/null
  fi
  aws cloudtrail start-logging --region $R --name $TRAIL
  echo "trail $TRAIL logging"

  # EventBridge rule: CloudTrail AuthorizeSecurityGroupIngress -> Lambda
  aws events put-rule --region $R --name $RULE \
    --event-pattern '{"source":["aws.ec2"],"detail-type":["AWS API Call via CloudTrail"],"detail":{"eventSource":["ec2.amazonaws.com"],"eventName":["AuthorizeSecurityGroupIngress"]}}' >/dev/null
  aws lambda add-permission --region $R --function-name $FN --statement-id eb-invoke \
    --action lambda:InvokeFunction --principal events.amazonaws.com \
    --source-arn "arn:aws:events:${R}:${ACCT}:rule/${RULE}" >/dev/null 2>&1 || true
  aws events put-targets --region $R --rule $RULE --targets "Id=1,Arn=${FN_ARN}" >/dev/null
  echo "rule $RULE -> $FN"
  echo "== deploy done =="
}

before_after() {
  local V SG; V=$(vpc_id); SG=$(sg_id "$V")
  echo "SG=$SG"
  echo "-- add tcp/22 0.0.0.0/0 --"
  aws ec2 authorize-security-group-ingress --region $R --group-id "$SG" --protocol tcp --port 22 --cidr 0.0.0.0/0 >/dev/null 2>&1 || echo "(already present)"
  echo "-- BEFORE (ingress) --"
  aws ec2 describe-security-groups --region $R --group-ids "$SG" --query "SecurityGroups[0].IpPermissions" --output json
}

test_trail() {
  before_after
  echo "-- wait up to 900s for CloudTrail->EventBridge->Lambda to revoke (new trails deliver slowly) --"
  local V SG; V=$(vpc_id); SG=$(sg_id "$V")
  # NOTE: nested-filter projections silently return empty; flatten IpRanges with [] BEFORE filtering.
  local Q='SecurityGroups[0].IpPermissions[?ToPort==`22`].IpRanges[] | [?CidrIp==`0.0.0.0/0`].CidrIp'
  for i in $(seq 1 90); do
    sleep 10
    local open; open=$(aws ec2 describe-security-groups --region $R --group-ids "$SG" --query "$Q" --output text)
    if [ -z "$open" ]; then echo "REMEDIATED via trail after ~$((i*10))s"; break; fi
    echo "  still open (${i}0s)..."
  done
}

test_direct() {
  before_after
  local V SG; V=$(vpc_id); SG=$(sg_id "$V")
  echo "-- direct invoke with synthetic AuthorizeSecurityGroupIngress event --"
  local PAYLOAD; PAYLOAD=$(mktemp)
  cat > "$PAYLOAD" <<JSON
{"detail":{"eventName":"AuthorizeSecurityGroupIngress","requestParameters":{"groupId":"$SG","ipPermissions":{"items":[{"ipProtocol":"tcp","fromPort":22,"toPort":22,"ipRanges":{"items":[{"cidrIp":"0.0.0.0/0"}]}}]}}}}
JSON
  aws lambda invoke --region $R --function-name $FN --cli-binary-format raw-in-base64-out \
    --payload "file://$PAYLOAD" /tmp/lambda-out.json >/tmp/lambda-invoke.json
  echo "invoke meta:"; cat /tmp/lambda-invoke.json
  echo "lambda return:"; cat /tmp/lambda-out.json; echo
  sleep 3
  echo "-- AFTER (ingress) --"
  aws ec2 describe-security-groups --region $R --group-ids "$SG" --query "SecurityGroups[0].IpPermissions" --output json
  local Q='SecurityGroups[0].IpPermissions[?ToPort==`22`].IpRanges[] | [?CidrIp==`0.0.0.0/0`].CidrIp'
  local open; open=$(aws ec2 describe-security-groups --region $R --group-ids "$SG" --query "$Q" --output text)
  [ -z "$open" ] && echo "RESULT: 0.0.0.0/0:22 GONE (remediated)" || echo "RESULT: STILL OPEN"
}

teardown() {
  echo "== teardown =="
  aws events remove-targets --region $R --rule $RULE --ids 1 2>/dev/null || true
  aws events delete-rule --region $R --name $RULE 2>/dev/null || true
  aws lambda delete-function --region $R --function-name $FN 2>/dev/null || true
  aws cloudtrail stop-logging --region $R --name $TRAIL 2>/dev/null || true
  aws cloudtrail delete-trail --region $R --name $TRAIL 2>/dev/null || true
  aws s3 rb s3://$TRAIL_BUCKET --force 2>/dev/null || true
  aws sns delete-topic --region $R --topic-arn "$(topic_arn)" 2>/dev/null || true
  local V; V=$(vpc_id)
  if [ "$V" != "None" ] && [ -n "$V" ]; then
    local SG; SG=$(sg_id "$V")
    [ "$SG" != "None" ] && [ -n "$SG" ] && aws ec2 delete-security-group --region $R --group-id "$SG" 2>/dev/null || true
    aws ec2 delete-vpc --region $R --vpc-id "$V" 2>/dev/null || true
  fi
  aws iam delete-role-policy --role-name $ROLE --policy-name sg-remediate 2>/dev/null || true
  aws iam detach-role-policy --role-name $ROLE --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole 2>/dev/null || true
  aws iam delete-role --role-name $ROLE 2>/dev/null || true
  echo "== teardown done =="
}

case "${1:-}" in
  deploy) deploy ;;
  test) test_direct ;;
  test-trail) test_trail ;;
  teardown) teardown ;;
  *) echo "usage: $0 {deploy|test|test-trail|teardown}"; exit 1 ;;
esac
