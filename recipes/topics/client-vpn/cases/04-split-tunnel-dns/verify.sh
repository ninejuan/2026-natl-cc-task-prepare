#!/bin/bash
# client-vpn 03(SAML federated) + 04(split-tunnel + DNS/PHZ) 라이브 검증 (ap-southeast-1)
set -x
R=ap-southeast-1
A=156041424727
D="$(cd "$(dirname "$0")" && pwd)"; cd "$D"
rm -rf cvpn && mkdir cvpn && cd cvpn

########## 0) 서버 인증서(CN=FQDN 필수) → ACM ##########
openssl genrsa -out ca.key 2048 2>/dev/null
openssl req -x509 -new -nodes -key ca.key -sha256 -days 3650 -subj "/CN=lab-cvpn-ca" -out ca.crt
openssl genrsa -out server.key 2048 2>/dev/null
openssl req -new -key server.key -subj "/CN=server.lab-cvpn.example.com" -out server.csr
openssl x509 -req -in server.csr -CA ca.crt -CAkey ca.key -CAcreateserial -days 825 -sha256 -out server.crt
SC=$(aws acm import-certificate --region $R --certificate fileb://server.crt --private-key fileb://server.key \
     --certificate-chain fileb://ca.crt --query CertificateArn --output text)
echo "SERVER_CERT=$SC"

########## 1) VPC + 퍼블릭 서브넷 + SSM 용 EC2 ##########
VPC=$(aws ec2 create-vpc --region $R --cidr-block 10.40.0.0/16 --query Vpc.VpcId --output text)
aws ec2 create-tags --region $R --resources $VPC --tags Key=Name,Value=lab-cvpn-vpc
aws ec2 modify-vpc-attribute --region $R --vpc-id $VPC --enable-dns-hostnames
IGW=$(aws ec2 create-internet-gateway --region $R --query InternetGateway.InternetGatewayId --output text)
aws ec2 attach-internet-gateway --region $R --vpc-id $VPC --internet-gateway-id $IGW
SUB=$(aws ec2 create-subnet --region $R --vpc-id $VPC --cidr-block 10.40.1.0/24 --availability-zone ${R}a --query Subnet.SubnetId --output text)
aws ec2 modify-subnet-attribute --region $R --subnet-id $SUB --map-public-ip-on-launch
RT=$(aws ec2 create-route-table --region $R --vpc-id $VPC --query RouteTable.RouteTableId --output text)
aws ec2 create-route --region $R --route-table-id $RT --destination-cidr-block 0.0.0.0/0 --gateway-id $IGW >/dev/null
aws ec2 associate-route-table --region $R --route-table-id $RT --subnet-id $SUB >/dev/null
SG=$(aws ec2 describe-security-groups --region $R --filters Name=vpc-id,Values=$VPC Name=group-name,Values=default --query 'SecurityGroups[0].GroupId' --output text)

cat > ec2-trust.json <<'EOF'
{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":"ec2.amazonaws.com"},"Action":"sts:AssumeRole"}]}
EOF
aws iam create-role --role-name lab-cvpn-ssm --assume-role-policy-document file://ec2-trust.json >/dev/null
aws iam attach-role-policy --role-name lab-cvpn-ssm --policy-arn arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore
aws iam create-instance-profile --instance-profile-name lab-cvpn-ssm >/dev/null
aws iam add-role-to-instance-profile --instance-profile-name lab-cvpn-ssm --role-name lab-cvpn-ssm
sleep 15
AMI=$(aws ssm get-parameter --region $R --name /aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64 --query Parameter.Value --output text)
EC2=$(aws ec2 run-instances --region $R --image-id $AMI --instance-type t3.micro --subnet-id $SUB \
  --security-group-ids $SG --iam-instance-profile Name=lab-cvpn-ssm \
  --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=lab-cvpn-bastion}]' \
  --query 'Instances[0].InstanceId' --output text)
echo "VPC=$VPC SUB=$SUB EC2=$EC2"

########## 2) Private Hosted Zone day2.local + 레코드 ##########
HZ=$(aws route53 create-hosted-zone --name day2.local --vpc VPCRegion=$R,VPCId=$VPC \
  --hosted-zone-config PrivateZone=true --caller-reference "lab-$(date +%s)" \
  --query HostedZone.Id --output text | sed 's#/hostedzone/##')
aws route53 change-resource-record-sets --hosted-zone-id $HZ --change-batch \
  '{"Changes":[{"Action":"UPSERT","ResourceRecordSet":{"Name":"db.day2.local","Type":"A","TTL":60,"ResourceRecords":[{"Value":"10.40.1.99"}]}}]}' \
  --query ChangeInfo.Status --output text
echo "HZ=$HZ"

########## 3) [케이스 04] split-tunnel + dns-servers 로 endpoint ##########
EP=$(aws ec2 create-client-vpn-endpoint --region $R --description lab-cvpn-split \
  --server-certificate-arn $SC --client-cidr-block 172.31.240.0/22 \
  --authentication-options "Type=certificate-authentication,MutualAuthentication={ClientRootCertificateChainArn=$SC}" \
  --connection-log-options Enabled=false \
  --split-tunnel --dns-servers 10.40.0.2 \
  --query ClientVpnEndpointId --output text)
echo "EP04=$EP"
aws ec2 describe-client-vpn-endpoints --region $R --client-vpn-endpoint-ids $EP \
  --query 'ClientVpnEndpoints[0].{status:Status.Code,cidr:ClientCidrBlock,split:SplitTunnel,dns:DnsServers,auth:AuthenticationOptions[0].Type}' --output json

echo "===== .ovpn 에 DNS 지시자가 실제로 들어가는가(2024 핵심) ====="
aws ec2 export-client-vpn-client-configuration --region $R --client-vpn-endpoint-id $EP --output text > client.ovpn
grep -iE 'dhcp-option|remote |verify-x509|cipher' client.ovpn | head

echo "===== 서브넷 association + authorization ====="
AS=$(aws ec2 associate-client-vpn-target-network --region $R --client-vpn-endpoint-id $EP --subnet-id $SUB --query AssociationId --output text)
aws ec2 authorize-client-vpn-ingress --region $R --client-vpn-endpoint-id $EP \
  --target-network-cidr 10.40.0.0/16 --authorize-all-groups --query Status.Code --output text
until [ "$(aws ec2 describe-client-vpn-target-networks --region $R --client-vpn-endpoint-id $EP --query 'ClientVpnTargetNetworks[0].Status.Code' --output text)" = "associated" ]; do sleep 20; done
echo "--- association 완료 후 endpoint/route/authz ---"
aws ec2 describe-client-vpn-endpoints --region $R --client-vpn-endpoint-ids $EP --query 'ClientVpnEndpoints[0].Status.Code' --output text
aws ec2 describe-client-vpn-routes --region $R --client-vpn-endpoint-id $EP --query 'Routes[].[DestinationCidr,Type,Status.Code]' --output text
aws ec2 describe-client-vpn-authorization-rules --region $R --client-vpn-endpoint-id $EP --query 'AuthorizationRules[].[DestinationCidr,AccessAll,Status.Code]' --output text

echo "===== VPC .2 리졸버가 PHZ 를 푸는가 (VPN 클라가 받는 DNS 서버) ====="
CID=$(aws ssm send-command --region $R --instance-ids $EC2 --document-name AWS-RunShellScript \
  --parameters 'commands=["dig +short db.day2.local @10.40.0.2","echo ---","dig +short db.day2.local"]' \
  --query Command.CommandId --output text)
sleep 12
aws ssm get-command-invocation --region $R --command-id $CID --instance-id $EC2 --query '[Status,StandardOutputContent]' --output text

########## 4) [케이스 03] SAML federated endpoint ##########
CERT_B64=$(openssl x509 -in ca.crt -outform DER | base64 | tr -d '\n')
cat > idp-metadata.xml <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<EntityDescriptor xmlns="urn:oasis:names:tc:SAML:2.0:metadata" entityID="https://keycloak.example.com/realms/lab">
  <IDPSSODescriptor WantAuthnRequestsSigned="false" protocolSupportEnumeration="urn:oasis:names:tc:SAML:2.0:protocol">
    <KeyDescriptor use="signing">
      <KeyInfo xmlns="http://www.w3.org/2000/09/xmldsig#">
        <X509Data><X509Certificate>$CERT_B64</X509Certificate></X509Data>
      </KeyInfo>
    </KeyDescriptor>
    <NameIDFormat>urn:oasis:names:tc:SAML:2.0:nameid-format:persistent</NameIDFormat>
    <SingleSignOnService Binding="urn:oasis:names:tc:SAML:2.0:bindings:HTTP-POST" Location="https://keycloak.example.com/realms/lab/protocol/saml"/>
    <SingleSignOnService Binding="urn:oasis:names:tc:SAML:2.0:bindings:HTTP-Redirect" Location="https://keycloak.example.com/realms/lab/protocol/saml"/>
  </IDPSSODescriptor>
</EntityDescriptor>
EOF
SAML=$(aws iam create-saml-provider --name lab-cvpn-idp --saml-metadata-document file://idp-metadata.xml --query SAMLProviderArn --output text)
echo "SAML=$SAML"
EP3=$(aws ec2 create-client-vpn-endpoint --region $R --description lab-cvpn-saml \
  --server-certificate-arn $SC --client-cidr-block 172.31.244.0/22 \
  --authentication-options "Type=federated-authentication,FederatedAuthentication={SAMLProviderArn=$SAML}" \
  --connection-log-options Enabled=false --split-tunnel \
  --query ClientVpnEndpointId --output text)
echo "EP03=$EP3"
aws ec2 describe-client-vpn-endpoints --region $R --client-vpn-endpoint-ids $EP3 \
  --query 'ClientVpnEndpoints[0].{status:Status.Code,auth:AuthenticationOptions[0].Type,saml:AuthenticationOptions[0].FederatedAuthentication.SamlProviderArn,self:SelfServicePortalUrl}' --output json
echo "===== SAML 그룹별 authorization (--access-group-id) ====="
aws ec2 authorize-client-vpn-ingress --region $R --client-vpn-endpoint-id $EP3 \
  --target-network-cidr 10.40.1.0/24 --access-group-id developers --description "dev group only" \
  --query Status.Code --output text
aws ec2 describe-client-vpn-authorization-rules --region $R --client-vpn-endpoint-id $EP3 \
  --query 'AuthorizationRules[].[DestinationCidr,GroupId,AccessAll,Status.Code]' --output text

########## 5) teardown ##########
echo "===== teardown ====="
aws ec2 delete-client-vpn-endpoint --region $R --client-vpn-endpoint-id $EP3 >/dev/null
aws iam delete-saml-provider --saml-provider-arn $SAML
aws ec2 disassociate-client-vpn-target-network --region $R --client-vpn-endpoint-id $EP --association-id $AS >/dev/null
until [ "$(aws ec2 describe-client-vpn-target-networks --region $R --client-vpn-endpoint-id $EP --query 'length(ClientVpnTargetNetworks)' --output text)" = "0" ]; do sleep 20; done
aws ec2 delete-client-vpn-endpoint --region $R --client-vpn-endpoint-id $EP >/dev/null
aws ec2 terminate-instances --region $R --instance-ids $EC2 >/dev/null
aws route53 change-resource-record-sets --hosted-zone-id $HZ --change-batch \
  '{"Changes":[{"Action":"DELETE","ResourceRecordSet":{"Name":"db.day2.local","Type":"A","TTL":60,"ResourceRecords":[{"Value":"10.40.1.99"}]}}]}' >/dev/null
aws route53 delete-hosted-zone --id $HZ >/dev/null
aws acm delete-certificate --region $R --certificate-arn $SC
aws ec2 wait instance-terminated --region $R --instance-ids $EC2
aws iam remove-role-from-instance-profile --instance-profile-name lab-cvpn-ssm --role-name lab-cvpn-ssm
aws iam delete-instance-profile --instance-profile-name lab-cvpn-ssm
aws iam detach-role-policy --role-name lab-cvpn-ssm --policy-arn arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore
aws iam delete-role --role-name lab-cvpn-ssm
aws ec2 delete-subnet --region $R --subnet-id $SUB
aws ec2 delete-route-table --region $R --route-table-id $RT
aws ec2 detach-internet-gateway --region $R --vpc-id $VPC --internet-gateway-id $IGW
aws ec2 delete-internet-gateway --region $R --internet-gateway-id $IGW
aws ec2 delete-vpc --region $R --vpc-id $VPC
echo DONE
