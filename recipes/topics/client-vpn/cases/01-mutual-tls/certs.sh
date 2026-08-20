#!/usr/bin/env bash
# 케이스 01 — mutual TLS 인증서(easy-rsa) 생성 → ACM import. Client VPN cert-auth 준비.
# 지급 PC/CloudShell 에서. easy-rsa 3.x.
set -euo pipefail
export R=${R:-ap-northeast-2}

# easy-rsa 준비 (Amazon Linux: git clone). 실검증: certs 생성→ACM import→endpoint 생성 성공.
[ -d easy-rsa ] || git clone -q --depth 1 https://github.com/OpenVPN/easy-rsa.git
cd easy-rsa/easyrsa3
./easyrsa init-pki
echo -e "\n" | ./easyrsa build-ca nopass
# ★ 서버 인증서 CN 은 FQDN 이어야 한다(실측). CN=server 처럼 도메인 없으면
#   ACM 이 DomainName=null 로 import → create-client-vpn-endpoint 가
#   "Certificate does not have a domain" 로 거부. vpn.lab.internal 같은 FQDN 사용.
./easyrsa --batch build-server-full vpn.lab.internal nopass
./easyrsa --batch build-client-full client1.domain.tld nopass

# ACM 에 서버 인증서(+CA 체인) import — Client VPN 이 참조
SERVER_ARN=$(aws acm import-certificate --region $R \
  --certificate fileb://pki/issued/vpn.lab.internal.crt \
  --private-key fileb://pki/private/vpn.lab.internal.key \
  --certificate-chain fileb://pki/ca.crt \
  --query CertificateArn --output text)
echo "SERVER_CERT_ARN=$SERVER_ARN"
# 확인: DomainName 이 채워져야 함(null 이면 endpoint 생성 거부)
aws acm describe-certificate --region $R --certificate-arn $SERVER_ARN --query 'Certificate.DomainName' --output text

# cert-auth 는 root_certificate_chain 에 CA(=서버와 같은 CA면 서버 ARN 재사용 가능).
# 별도 클라 CA 쓰면 클라 CA 를 따로 import.
echo "클라이언트 인증서/키(.ovpn 삽입용):"
echo "  cert: pki/issued/client1.domain.tld.crt"
echo "  key:  pki/private/client1.domain.tld.key"
