#!/usr/bin/env bash
# 케이스 05 — AWS_IAM 접근제어 + auth policy(SigV4). "특정 principal 만 서비스 호출" 요구.
# service(또는 service network)를 auth_type=AWS_IAM 으로 만들고 auth policy(리소스 정책) 부착.
set -euo pipefail
export R=${R:-ap-northeast-2} ACCT=$(aws sts get-caller-identity --query Account --output text)

# 서비스를 IAM 인증으로 생성(또는 update-service --auth-type AWS_IAM)
SVC=$(aws vpc-lattice create-service --region $R --name lab-lattice-iam-svc \
  --auth-type AWS_IAM --query id --output text)

# auth policy: 이 계정 principal 만 허용, anonymous 거부
aws vpc-lattice put-auth-policy --region $R --resource-identifier $SVC --policy '{
  "Version":"2012-10-17",
  "Statement":[{
    "Effect":"Allow",
    "Principal":{"AWS":"arn:aws:iam::'$ACCT':root"},
    "Action":"vpc-lattice-svcs:Invoke",
    "Resource":"*",
    "Condition":{"StringNotEqualsIgnoreCase":{"aws:PrincipalType":"anonymous"}}
  }]}'

echo "auth policy 부착됨:"
aws vpc-lattice get-auth-policy --region $R --resource-identifier $SVC --query policy --output text | python3 -m json.tool
echo "service auth type:"
aws vpc-lattice get-service --region $R --service-identifier $SVC --query authType --output text
# 검증: AWS_IAM 서비스는 SigV4 서명 없는 요청 403.
#   서명 요청은 awscurl 또는 SigV4 서명 라이브러리로. anonymous 는 거부.

# 정리
# aws vpc-lattice delete-auth-policy --region $R --resource-identifier $SVC
# aws vpc-lattice delete-service --region $R --service-identifier $SVC
