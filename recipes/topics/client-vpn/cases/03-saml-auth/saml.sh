#!/usr/bin/env bash
# 케이스 03 — SAML federated 인증 Client VPN. Keycloak/IAM Identity Center 를 IdP 로.
# 인증서 대신 SAML → 유저별/그룹별 접근제어(authorization rule 을 SAML 그룹에).
set -euo pipefail
export R=${R:-ap-northeast-2}
SERVER_CERT=${SERVER_CERT_ARN:?서버 인증서(TLS용, SAML 이어도 서버 cert 필요)}

# 1) IdP 의 SAML metadata 로 IAM SAML provider 생성 (federated-authentication 이 참조)
#    Keycloak: client(SAML) → SP metadata 를 AWS 형식으로. IdC: 외부 IdP 앱.
SAML_ARN=$(aws iam create-saml-provider --name lab-cvpn-idp \
  --saml-metadata-document file://idp-metadata.xml --query SAMLProviderArn --output text)

# 2) endpoint 를 federated-authentication 으로
EP=$(aws ec2 create-client-vpn-endpoint --region $R --description lab-cvpn-saml \
  --server-certificate-arn "$SERVER_CERT" \
  --client-cidr-block 172.31.240.0/22 \
  --authentication-options "Type=federated-authentication,FederatedAuthentication={SAMLProviderArn=$SAML_ARN}" \
  --connection-log-options "Enabled=false" \
  --split-tunnel --query ClientVpnEndpointId --output text)
echo "EP=$EP SAML=$SAML_ARN"

# 3) 그룹별 authorization — SAML assertion 의 그룹으로 접근 CIDR 제한
#    (authorize-all-groups 대신 --access-group-id <SAML group>)
# aws ec2 authorize-client-vpn-ingress --client-vpn-endpoint-id $EP \
#   --target-network-cidr 10.40.1.0/24 --access-group-id "developers"
echo "→ SAML 그룹 'developers' 만 특정 서브넷 접근 등 그룹별 제어 가능."
