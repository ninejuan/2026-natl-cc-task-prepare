#!/usr/bin/env bash
# 케이스 02 — Client VPN endpoint + network association + authorization + route.
# 💸 association 시간과금. 검증 후 즉시 disassociate + delete.
# 전제: 케이스 01 로 SERVER_CERT_ARN 확보, 전용 VPC + private 서브넷(SUB).
set -euo pipefail
export R=${R:-ap-northeast-2}
CERT=${SERVER_CERT_ARN:?ACM 서버 인증서 ARN} VPC=${VPC:?} SUB=${SUB:?private subnet} VPC_CIDR=${VPC_CIDR:-10.40.0.0/16}

# 연결 로그(선택)
aws logs create-log-group --region $R --log-group-name /lab/cvpn 2>/dev/null || true

# endpoint (client_cidr 는 VPC/로컬과 안 겹치게! DNS 는 VPC .2 리졸버)
EP=$(aws ec2 create-client-vpn-endpoint --region $R \
  --description lab-cvpn \
  --server-certificate-arn "$CERT" \
  --client-cidr-block 172.31.240.0/22 \
  --authentication-options "Type=certificate-authentication,MutualAuthentication={ClientRootCertificateChainArn=$CERT}" \
  --connection-log-options "Enabled=true,CloudwatchLogGroup=/lab/cvpn" \
  --dns-servers "$(echo $VPC_CIDR | sed 's|0/16|0.2|')" \
  --split-tunnel \
  --query ClientVpnEndpointId --output text)
echo "EP=$EP"

# 서브넷 association (→ ENI 생성, 과금 시작)
aws ec2 associate-client-vpn-target-network --region $R \
  --client-vpn-endpoint-id $EP --subnet-id $SUB >/dev/null
echo "association 대기(available)..."
until [ "$(aws ec2 describe-client-vpn-target-networks --region $R --client-vpn-endpoint-id $EP --query 'ClientVpnTargetNetworks[0].Status.Code' --output text)" = associated ]; do sleep 10; done

# authorization: VPC CIDR 접근 허용(전 그룹)
aws ec2 authorize-client-vpn-ingress --region $R --client-vpn-endpoint-id $EP \
  --target-network-cidr $VPC_CIDR --authorize-all-groups >/dev/null

# route: VPN → VPC (association 서브넷 경유). 인터넷도 주려면 0.0.0.0/0 route 추가.
# (VPC 로컬 라우트는 자동. 추가 대상 있으면 create-client-vpn-route)

echo "endpoint 상태:"
aws ec2 describe-client-vpn-endpoints --region $R --client-vpn-endpoint-ids $EP \
  --query 'ClientVpnEndpoints[0].{status:Status.Code,cidr:ClientCidrBlock,split:SplitTunnel,dns:DnsServers}' --output json
echo "→ .ovpn: aws ec2 export-client-vpn-client-configuration --client-vpn-endpoint-id $EP"
echo "   + 클라 인증서/키 삽입 후 AWS VPN Client 로 연결."
