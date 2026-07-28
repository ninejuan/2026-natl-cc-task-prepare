#!/usr/bin/env bash
# AWS 쪽 SAML 설정. Keycloak 이 먼저 떠 있어야 한다.
#
#   export P=<비번호> KC_URL=http://<keycloak-주소>
#   ./setup-aws-saml.sh
#
# 출력된 Role ARN 을 Keycloak 유저의 Role attribute 에 넣는다:
#   <Role ARN>,<SAML Provider ARN>
set -euo pipefail
export AWS_PAGER=""

: "${KC_URL:?KC_URL 을 지정하라 (예: http://1.2.3.4:8080)}"
REALM="${REALM:-aws}"
PROVIDER_NAME="${PROVIDER_NAME:-keycloak}"
ACCOUNT=$(aws sts get-caller-identity --query Account --output text)

# 1) Keycloak IdP metadata 내려받기
curl -sf "$KC_URL/realms/$REALM/protocol/saml/descriptor" -o /tmp/keycloak-metadata.xml
grep -q EntityDescriptor /tmp/keycloak-metadata.xml || { echo "metadata 가 이상하다"; exit 1; }

# 2) SAML Identity Provider 등록 (이미 있으면 갱신)
if SAML_ARN=$(aws iam get-saml-provider --saml-provider-arn "arn:aws:iam::$ACCOUNT:saml-provider/$PROVIDER_NAME" \
      --query 'Tags' --output text 2>/dev/null); then
  SAML_ARN="arn:aws:iam::$ACCOUNT:saml-provider/$PROVIDER_NAME"
  aws iam update-saml-provider --saml-provider-arn "$SAML_ARN" \
    --saml-metadata-document file:///tmp/keycloak-metadata.xml >/dev/null
else
  SAML_ARN=$(aws iam create-saml-provider --name "$PROVIDER_NAME" \
    --saml-metadata-document file:///tmp/keycloak-metadata.xml \
    --query SAMLProviderArn --output text)
fi
echo "SAML_PROVIDER_ARN=$SAML_ARN"

# 3) trust policy — 이 SAML Provider 로 온 SAML 만 assume 가능
cat > /tmp/saml-trust.json <<JSON
{"Version":"2012-10-17","Statement":[{
  "Effect":"Allow",
  "Principal":{"Federated":"$SAML_ARN"},
  "Action":"sts:AssumeRoleWithSAML",
  "Condition":{"StringEquals":{"SAML:aud":"https://signin.aws.amazon.com/saml"}}
}]}
JSON

# 4) Role 2개. 과제지가 이름을 지정하면 그대로 맞춘다.
create_role() {
  local name=$1 policy=$2
  aws iam create-role --role-name "$name" \
    --assume-role-policy-document file:///tmp/saml-trust.json \
    --max-session-duration 3600 >/dev/null 2>&1 \
  || aws iam update-assume-role-policy --role-name "$name" \
       --policy-document file:///tmp/saml-trust.json
  aws iam attach-role-policy --role-name "$name" --policy-arn "$policy"
  echo "ROLE_ARN=arn:aws:iam::$ACCOUNT:role/$name,$SAML_ARN"
}

create_role admin-access     arn:aws:iam::aws:policy/AdministratorAccess
create_role poweruser-access arn:aws:iam::aws:policy/PowerUserAccess

rm -f /tmp/saml-trust.json
echo
echo "위 ROLE_ARN 문자열을 Keycloak 유저 attribute 'Role' 에 그대로 넣어라."
echo "  admin\$P  -> admin-access 줄"
echo "  dev\$P    -> poweruser-access 줄"
