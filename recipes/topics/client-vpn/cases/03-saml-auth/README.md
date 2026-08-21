# 케이스 03 — SAML federated 인증 Client VPN — ✅ live 검증

인증서 대신 **SAML IdP(Keycloak / IAM Identity Center)** 로 로그인 → 유저·**그룹별 접근제어**. `saml.sh` 가 절차, `../04-split-tunnel-dns/verify.sh` 가 03+04 를 한 번에 실제 생성·검증·삭제한다(ap-southeast-1).

## 순서

```bash
# 1) IdP 의 SAML metadata XML 로 IAM SAML provider
SAML=$(aws iam create-saml-provider --name lab-cvpn-idp \
  --saml-metadata-document file://idp-metadata.xml --query SAMLProviderArn --output text)

# 2) endpoint 를 federated-authentication 으로 (서버 인증서는 SAML 이어도 필요)
aws ec2 create-client-vpn-endpoint --region $R --description lab-cvpn-saml \
  --server-certificate-arn $SC --client-cidr-block 172.31.244.0/22 \
  --authentication-options "Type=federated-authentication,FederatedAuthentication={SAMLProviderArn=$SAML}" \
  --connection-log-options Enabled=false --split-tunnel

# 3) ★ 그룹별 인가 — authorize-all-groups 대신 --access-group-id <SAML 그룹>
aws ec2 authorize-client-vpn-ingress --region $R --client-vpn-endpoint-id $EP \
  --target-network-cidr 10.40.1.0/24 --access-group-id developers --description "dev group only"
```

## 실측 결과

```json
{"status":"pending-associate","auth":"federated-authentication",
 "saml":"arn:aws:iam::…:saml-provider/lab-cvpn-idp",
 "self":"https://self-service.clientvpn.amazonaws.com/endpoints/cvpn-endpoint-0ea9f9e…"}
```
```
authz:  10.40.1.0/24   GroupId=developers   AccessAll=False   authorizing
```
- **`SelfServicePortalUrl` 이 자동으로 붙는다** — SAML 인증 endpoint 는 선수/사용자가 이 포털에서 로그인해 `.ovpn` 을 내려받는다(인증서 방식과 다른 배포 경로). 채점이 "사용자가 직접 프로필을 받는다"고 하면 이 URL.
- 그룹 인가 규칙은 `AccessAll=False` + `GroupId` 로 남는다 → `describe-client-vpn-authorization-rules` 로 관찰 가능.

## IdP metadata XML (Keycloak 형태)

`create-saml-provider` 는 **SAML 2.0 metadata 구조를 검증**한다. 최소 형태:
```xml
<EntityDescriptor xmlns="urn:oasis:names:tc:SAML:2.0:metadata" entityID="https://keycloak.example.com/realms/lab">
  <IDPSSODescriptor WantAuthnRequestsSigned="false" protocolSupportEnumeration="urn:oasis:names:tc:SAML:2.0:protocol">
    <KeyDescriptor use="signing"><KeyInfo xmlns="http://www.w3.org/2000/09/xmldsig#">
      <X509Data><X509Certificate>…base64 DER…</X509Certificate></X509Data></KeyInfo></KeyDescriptor>
    <NameIDFormat>urn:oasis:names:tc:SAML:2.0:nameid-format:persistent</NameIDFormat>
    <SingleSignOnService Binding="urn:oasis:names:tc:SAML:2.0:bindings:HTTP-POST"
      Location="https://keycloak.example.com/realms/lab/protocol/saml"/>
  </IDPSSODescriptor>
</EntityDescriptor>
```
실전에선 Keycloak 의 `realms/<realm>/protocol/saml/descriptor` 를 그대로 받아 쓴다.

## 함정

- **SAML 이어도 서버 인증서(ACM)는 필요**하다 — TLS 종단용. CN 은 FQDN.
- Keycloak SAML 클라이언트의 **ACS URL 은 `http://127.0.0.1:35001`**(AWS VPN Client 가 로컬에서 콜백 받음) + self-service 포털용 URL. 이걸 빠뜨리면 로그인 후 리다이렉트 실패.
- 그룹 인가는 SAML assertion 의 **그룹 attribute 값**과 `--access-group-id` 가 정확히 같아야 한다.
- 실제 로그인 왕복은 IdP + GUI 클라이언트가 필요해 CLI 로는 자동화 불가(여기까지가 API 로 검증 가능한 전부).
- 검증 후 `delete-saml-provider` + endpoint 삭제. SAML provider 는 글로벌(IAM) 리소스라 리전 격리와 무관하게 남는다.
