#!/bin/bash
# keycloak-sso 01/02/04 의 AWS 쪽(IAM SAML/OIDC provider + role) 라이브 검증. IAM 은 글로벌.
set -x
D="$(cd "$(dirname "$0")" && pwd)"; cd "$D"
A=$(aws sts get-caller-identity --query Account --output text)

########## 01 — SAML provider + role x2 ##########
openssl req -x509 -newkey rsa:2048 -nodes -keyout kc.key -out kc.crt -days 3650 -subj "/CN=keycloak-lab" 2>/dev/null
CERT=$(openssl x509 -in kc.crt -outform DER | base64 | tr -d '\n')
cat > kc-metadata.xml <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<EntityDescriptor xmlns="urn:oasis:names:tc:SAML:2.0:metadata" entityID="https://keycloak.lab.local/realms/aws">
  <IDPSSODescriptor WantAuthnRequestsSigned="false" protocolSupportEnumeration="urn:oasis:names:tc:SAML:2.0:protocol">
    <KeyDescriptor use="signing"><KeyInfo xmlns="http://www.w3.org/2000/09/xmldsig#">
      <X509Data><X509Certificate>$CERT</X509Certificate></X509Data></KeyInfo></KeyDescriptor>
    <NameIDFormat>urn:oasis:names:tc:SAML:2.0:nameid-format:persistent</NameIDFormat>
    <SingleSignOnService Binding="urn:oasis:names:tc:SAML:2.0:bindings:HTTP-POST" Location="https://keycloak.lab.local/realms/aws/protocol/saml"/>
    <SingleSignOnService Binding="urn:oasis:names:tc:SAML:2.0:bindings:HTTP-Redirect" Location="https://keycloak.lab.local/realms/aws/protocol/saml"/>
  </IDPSSODescriptor>
</EntityDescriptor>
EOF
SAML=$(aws iam create-saml-provider --name lab-kc-idp --saml-metadata-document file://kc-metadata.xml --query SAMLProviderArn --output text)
echo "SAML=$SAML"

mk_saml_trust() {  # $1 = 추가 조건 블록
cat <<EOF
{"Version":"2012-10-17","Statement":[{
  "Effect":"Allow",
  "Principal":{"Federated":"$SAML"},
  "Action":"sts:AssumeRoleWithSAML",
  "Condition":{"StringEquals":{"SAML:aud":"https://signin.aws.amazon.com/saml"$1}}
}]}
EOF
}
mk_saml_trust "" > t-admin.json
mk_saml_trust ',"SAML:sub_type":"persistent"' > t-ro.json
aws iam create-role --role-name lab-kc-Admin --assume-role-policy-document file://t-admin.json --max-session-duration 3600 --query Role.Arn --output text
aws iam attach-role-policy --role-name lab-kc-Admin --policy-arn arn:aws:iam::aws:policy/PowerUserAccess
aws iam create-role --role-name lab-kc-ReadOnly --assume-role-policy-document file://t-ro.json --max-session-duration 3600 --query Role.Arn --output text
aws iam attach-role-policy --role-name lab-kc-ReadOnly --policy-arn arn:aws:iam::aws:policy/ReadOnlyAccess

echo "===== 채점 관점 조회 ====="
aws iam list-saml-providers --query "SAMLProviderList[?contains(Arn,'lab-kc-idp')].[Arn,ValidUntil]" --output text
aws iam get-saml-provider --saml-provider-arn $SAML --query 'SAMLMetadataDocument' --output text | grep -o 'entityID="[^"]*"'
for R in lab-kc-Admin lab-kc-ReadOnly; do
  echo "--- $R ---"
  aws iam get-role --role-name $R --query 'Role.AssumeRolePolicyDocument.Statement[0].[Action,Principal.Federated,Condition]' --output json
  aws iam list-attached-role-policies --role-name $R --query 'AttachedPolicies[].PolicyName' --output text
done

echo "===== 잘못된 aud 로 assume 시도(거부 확인용 — 실제 assertion 없이) ====="
aws sts assume-role-with-saml --role-arn arn:aws:iam::$A:role/lab-kc-Admin --principal-arn $SAML \
  --saml-assertion "$(echo -n '<not-a-real-assertion/>' | base64)" 2>&1 | tail -2

########## 02 — OIDC provider + role ##########
THUMB=$(echo -n "" | openssl dgst -sha1 -hex | sed 's/.*= //')   # 자리표시자(실전은 IdP TLS 인증서 지문)
OIDC=$(aws iam create-open-id-connect-provider --url https://keycloak.lab.local/realms/aws \
  --client-id-list sts.amazonaws.com aws-cli \
  --thumbprint-list 9e99a48a9960b14926bb7f3b02e22da2b0ab7280 --query OpenIDConnectProviderArn --output text)
echo "OIDC=$OIDC"
cat > t-oidc.json <<EOF
{"Version":"2012-10-17","Statement":[{
  "Effect":"Allow","Principal":{"Federated":"$OIDC"},
  "Action":"sts:AssumeRoleWithWebIdentity",
  "Condition":{
    "StringEquals":{"keycloak.lab.local/realms/aws:aud":"sts.amazonaws.com"},
    "StringLike":{"keycloak.lab.local/realms/aws:sub":"service-account-*"}}
}]}
EOF
aws iam create-role --role-name lab-kc-oidc --assume-role-policy-document file://t-oidc.json --query Role.Arn --output text
aws iam get-role --role-name lab-kc-oidc --query 'Role.AssumeRolePolicyDocument.Statement[0].Condition' --output json
aws iam list-open-id-connect-providers --query "OpenIDConnectProviderList[?contains(Arn,'keycloak.lab.local')].Arn" --output text
aws iam get-open-id-connect-provider --open-id-connect-provider-arn $OIDC --query '[Url,ClientIDList,ThumbprintList]' --output json

########## 04 — 그룹별 role 매핑(AWS 쪽은 role 분리 + 조건) ##########
echo "===== 그룹 매핑: Keycloak 이 Role attribute 로 <role-arn>,<idp-arn> 를 넘긴다 ====="
echo "  developers -> arn:aws:iam::$A:role/lab-kc-ReadOnly,$SAML"
echo "  admins     -> arn:aws:iam::$A:role/lab-kc-Admin,$SAML"

########## teardown ##########
echo "===== teardown ====="
aws iam detach-role-policy --role-name lab-kc-Admin --policy-arn arn:aws:iam::aws:policy/PowerUserAccess
aws iam delete-role --role-name lab-kc-Admin
aws iam detach-role-policy --role-name lab-kc-ReadOnly --policy-arn arn:aws:iam::aws:policy/ReadOnlyAccess
aws iam delete-role --role-name lab-kc-ReadOnly
aws iam delete-role --role-name lab-kc-oidc
aws iam delete-saml-provider --saml-provider-arn $SAML
aws iam delete-open-id-connect-provider --open-id-connect-provider-arn $OIDC
aws iam list-saml-providers --query 'SAMLProviderList[].Arn' --output text
aws iam list-open-id-connect-providers --query 'OpenIDConnectProviderList[].Arn' --output text
echo KCDONE
