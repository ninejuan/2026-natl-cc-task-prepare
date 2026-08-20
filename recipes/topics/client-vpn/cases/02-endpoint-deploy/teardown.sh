#!/usr/bin/env bash
# 케이스 02 정리. route → authz → association(ENI 회수 대기) → endpoint → ACM.
set -uo pipefail
export R=${R:-ap-northeast-2}
EP=$(aws ec2 describe-client-vpn-endpoints --region $R --query "ClientVpnEndpoints[?Description=='lab-cvpn'].ClientVpnEndpointId" --output text)
[ -z "$EP" ] && { echo "endpoint 없음"; exit 0; }

# routes (auto 제외)
for r in $(aws ec2 describe-client-vpn-routes --region $R --client-vpn-endpoint-id $EP --query "Routes[?Type!='Nat'].[DestinationCidr,TargetSubnet]" --output text 2>/dev/null | awk '{print $1"|"$2}'); do
  cidr=${r%%|*}; sub=${r##*|}
  aws ec2 delete-client-vpn-route --region $R --client-vpn-endpoint-id $EP --destination-cidr-block "$cidr" --target-vpc-subnet-id "$sub" 2>/dev/null || true
done
# authorization
for c in $(aws ec2 describe-client-vpn-authorization-rules --region $R --client-vpn-endpoint-id $EP --query 'AuthorizationRules[].DestinationCidr' --output text); do
  aws ec2 revoke-client-vpn-ingress --region $R --client-vpn-endpoint-id $EP --target-network-cidr $c --revoke-all-groups 2>/dev/null || true
done
# associations (ENI 회수 필요)
for a in $(aws ec2 describe-client-vpn-target-networks --region $R --client-vpn-endpoint-id $EP --query 'ClientVpnTargetNetworks[].AssociationId' --output text); do
  aws ec2 disassociate-client-vpn-target-network --region $R --client-vpn-endpoint-id $EP --association-id $a
done
echo "association 해제 대기(ENI 회수)..."
until [ "$(aws ec2 describe-client-vpn-target-networks --region $R --client-vpn-endpoint-id $EP --query 'length(ClientVpnTargetNetworks)' --output text)" = 0 ]; do sleep 10; done
aws ec2 delete-client-vpn-endpoint --region $R --client-vpn-endpoint-id $EP
aws logs delete-log-group --region $R --log-group-name /lab/cvpn 2>/dev/null || true
echo "endpoint 삭제됨 (ACM 인증서는 케이스 01 정리에서)"
