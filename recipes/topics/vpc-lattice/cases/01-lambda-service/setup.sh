#!/usr/bin/env bash
# 케이스 01 — Lambda 타깃 서비스 (최단 경로). service network + service + listener + Lambda target group.
# 실검증됨(ap-northeast-2). VPC 는 이 모듈 전용으로 하나 만든다(가이드 독립성).
set -euo pipefail
export R=${R:-ap-northeast-2}
ACCT=$(aws sts get-caller-identity --query Account --output text)

# ── 0. 전용 VPC (Lattice 는 VPC association 필요) ──
VPC=$(aws ec2 create-vpc --region $R --cidr-block 10.20.0.0/16 \
  --tag-specifications 'ResourceType=vpc,Tags=[{Key=Name,Value=lab-lattice-vpc}]' \
  --query Vpc.VpcId --output text)
aws ec2 wait vpc-available --region $R --vpc-ids $VPC

# ── 1. Lambda (타깃) ──
cat > /tmp/lat-fn.py <<'PY'
def handler(event, context):
    return {"statusCode": 200, "headers": {"content-type": "text/plain"},
            "body": "hello from vpc-lattice lambda target"}
PY
( cd /tmp && zip -q lat-fn.zip lat-fn.py )
aws iam create-role --role-name lab-lattice-fn-role \
  --assume-role-policy-document '{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":"lambda.amazonaws.com"},"Action":"sts:AssumeRole"}]}' >/dev/null 2>&1 || true
aws iam attach-role-policy --role-name lab-lattice-fn-role \
  --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole >/dev/null 2>&1 || true
sleep 10
FNARN=$(aws lambda create-function --region $R --function-name lab-lattice-fn \
  --runtime python3.12 --handler lat-fn.handler --timeout 10 \
  --role arn:aws:iam::${ACCT}:role/lab-lattice-fn-role \
  --zip-file fileb:///tmp/lat-fn.zip --query FunctionArn --output text)

# ── 2. Lattice: service network, service, target group(LAMBDA), listener ──
NET=$(aws vpc-lattice create-service-network --region $R --name lab-lattice-net \
  --auth-type NONE --query id --output text)
SVC=$(aws vpc-lattice create-service --region $R --name lab-lattice-svc \
  --auth-type NONE --query id --output text)
TG=$(aws vpc-lattice create-target-group --region $R --name lab-tg-lambda \
  --type LAMBDA --query id --output text)

# Lattice 가 Lambda 를 호출할 권한
aws lambda add-permission --region $R --function-name lab-lattice-fn \
  --statement-id lattice --action lambda:InvokeFunction \
  --principal vpc-lattice.amazonaws.com >/dev/null

aws vpc-lattice register-targets --region $R --target-group-identifier $TG \
  --targets "id=$FNARN"

# listener (HTTP, default forward → TG)
aws vpc-lattice create-listener --region $R --service-identifier $SVC \
  --name http --protocol HTTP --port 80 \
  --default-action "forward={targetGroups=[{targetGroupIdentifier=$TG}]}" >/dev/null

# ── 3. association: service network ↔ service, service network ↔ VPC ──
aws vpc-lattice create-service-network-service-association --region $R \
  --service-network-identifier $NET --service-identifier $SVC >/dev/null
aws vpc-lattice create-service-network-vpc-association --region $R \
  --service-network-identifier $NET --vpc-identifier $VPC >/dev/null

echo "VPC=$VPC NET=$NET SVC=$SVC TG=$TG"
echo "service DNS:"
aws vpc-lattice get-service --region $R --service-identifier $SVC --query 'dnsEntry.domainName' --output text
echo "→ 이 VPC 안 EC2 에서: curl http://<위 DNS>/  (Lambda 응답 200)"
