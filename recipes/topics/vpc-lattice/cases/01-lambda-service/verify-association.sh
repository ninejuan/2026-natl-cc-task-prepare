#!/usr/bin/env bash
# 케이스 01 보강 — VPC association 이 ACTIVE 에 도달하고 service DNS 가 발급되는지 실검증.
# (기존 setup.sh/teardown.sh 는 lab-lattice- 이름의 전체 흐름 레시피. 이 스크립트는 lab-apne2-
#  이름으로 association=ACTIVE + dnsEntry 발급만 독립 확인하고 스스로 정리한다.)
# ★ 실제 end-to-end HTTP 호출은 associate 된 VPC "안"의 클라이언트(EC2 등)에서만 DNS 가
#   풀린다(Lattice 관리형 리졸버). EC2 없이는 association=ACTIVE + DNS 발급까지가 검증 한계.
set -euo pipefail
export R=${R:-ap-northeast-2}
ACCT=$(aws sts get-caller-identity --query Account --output text)

# ── 0. 전용 VPC ──
VPC=$(aws ec2 create-vpc --region $R --cidr-block 10.40.0.0/16 \
  --tag-specifications 'ResourceType=vpc,Tags=[{Key=Name,Value=lab-apne2-lattice-vpc}]' \
  --query Vpc.VpcId --output text)
aws ec2 wait vpc-available --region $R --vpc-ids $VPC

# ── 1. Lambda 타깃 ──
cat > /tmp/lab-apne2-lat-fn.py <<'PY'
def handler(event, context):
    return {"statusCode": 200, "headers": {"content-type": "text/plain"},
            "body": "hello from lab-apne2 vpc-lattice lambda"}
PY
( cd /tmp && zip -q lab-apne2-lat-fn.zip lab-apne2-lat-fn.py )
aws iam create-role --role-name lab-lattice-fn-apne2 \
  --assume-role-policy-document '{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":"lambda.amazonaws.com"},"Action":"sts:AssumeRole"}]}' >/dev/null 2>&1 || true
aws iam attach-role-policy --role-name lab-lattice-fn-apne2 \
  --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole >/dev/null 2>&1 || true
sleep 10
FNARN=$(aws lambda create-function --region $R --function-name lab-apne2-lattice-fn \
  --runtime python3.12 --handler lab-apne2-lat-fn.handler --timeout 10 \
  --role arn:aws:iam::${ACCT}:role/lab-lattice-fn-apne2 \
  --zip-file fileb:///tmp/lab-apne2-lat-fn.zip --query FunctionArn --output text)

# ── 2. Lattice: network, service, TG(LAMBDA), listener (throttle 대비 sleep) ──
NET=$(aws vpc-lattice create-service-network --region $R --name lab-apne2-lattice-net \
  --auth-type NONE --query id --output text); sleep 2
SVC=$(aws vpc-lattice create-service --region $R --name lab-apne2-lattice-svc \
  --auth-type NONE --query id --output text); sleep 2
TG=$(aws vpc-lattice create-target-group --region $R --name lab-apne2-tg-lambda \
  --type LAMBDA --query id --output text); sleep 2

aws lambda add-permission --region $R --function-name lab-apne2-lattice-fn \
  --statement-id lattice --action lambda:InvokeFunction \
  --principal vpc-lattice.amazonaws.com >/dev/null
aws vpc-lattice register-targets --region $R --target-group-identifier $TG --targets "id=$FNARN"; sleep 2
aws vpc-lattice create-listener --region $R --service-identifier $SVC \
  --name http --protocol HTTP --port 80 \
  --default-action "forward={targetGroups=[{targetGroupIdentifier=$TG}]}" >/dev/null; sleep 2

# ── 3. association: network↔service, network↔VPC ──
aws vpc-lattice create-service-network-service-association --region $R \
  --service-network-identifier $NET --service-identifier $SVC >/dev/null; sleep 2
VPCASSOC=$(aws vpc-lattice create-service-network-vpc-association --region $R \
  --service-network-identifier $NET --vpc-identifier $VPC --query id --output text)

# ── 검증: VPC association 이 ACTIVE 될 때까지 폴링 ──
echo "VPC association($VPCASSOC) 상태 폴링:"
for i in $(seq 1 20); do
  ST=$(aws vpc-lattice get-service-network-vpc-association --region $R \
    --service-network-vpc-association-identifier $VPCASSOC --query status --output text)
  echo "  attempt $i: $ST"
  [ "$ST" = "ACTIVE" ] && break
  sleep 6
done

echo "== service DNS(dnsEntry.domainName) =="
aws vpc-lattice get-service --region $R --service-identifier $SVC --query 'dnsEntry.domainName' --output text
echo "== target group 상태(ACTIVE 면 동작; Lambda 타깃 헬스는 UNAVAILABLE 이 정상) =="
aws vpc-lattice get-target-group --region $R --target-group-identifier $TG --query status --output text

echo "VPC=$VPC NET=$NET SVC=$SVC TG=$TG VPCASSOC=$VPCASSOC"

# ── teardown: association(service·vpc) → ENI 회수 대기 → service → TG → network → lambda/role → VPC ──
for a in $(aws vpc-lattice list-service-network-service-associations --region $R --service-network-identifier "$NET" --query 'items[].id' --output text 2>/dev/null); do
  aws vpc-lattice delete-service-network-service-association --region $R --service-network-service-association-identifier $a; done
aws vpc-lattice delete-service-network-vpc-association --region $R --service-network-vpc-association-identifier $VPCASSOC 2>/dev/null || true
echo "association ENI 회수 대기…"
for i in $(seq 1 20); do
  n=$(aws vpc-lattice list-service-network-vpc-associations --region $R --service-network-identifier "$NET" --query 'length(items)' --output text 2>/dev/null || echo 0)
  [ "$n" = "0" ] && break; sleep 8
done
for t in $(aws vpc-lattice list-targets --region $R --target-group-identifier $TG --query 'items[].id' --output text 2>/dev/null); do
  aws vpc-lattice deregister-targets --region $R --target-group-identifier $TG --targets id=$t; done
aws vpc-lattice delete-service --region $R --service-identifier $SVC; sleep 5
aws vpc-lattice delete-target-group --region $R --target-group-identifier $TG 2>/dev/null || true
aws vpc-lattice delete-service-network --region $R --service-network-identifier $NET
aws lambda delete-function --region $R --function-name lab-apne2-lattice-fn 2>/dev/null || true
aws iam detach-role-policy --role-name lab-lattice-fn-apne2 --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole 2>/dev/null || true
aws iam delete-role --role-name lab-lattice-fn-apne2 2>/dev/null || true
for i in $(seq 1 12); do aws ec2 delete-vpc --region $R --vpc-id $VPC 2>/dev/null && { echo "VPC deleted"; break; }; echo "  VPC busy(ENI 회수), retry…"; sleep 10; done
echo "teardown done"
