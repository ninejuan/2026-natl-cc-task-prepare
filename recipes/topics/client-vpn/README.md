# Client VPN 플레이북 (2026 #9, 2024 추가과제 원형)

**가이드 원문(2026 #9)** — "AWS Client VPN 으로 로컬에서 VPC 내부 서버에 접근. 로컬과 AWS 환경 IP 가 겹치거나 네트워크 문제 없도록 유의."
- 필수: Client VPN, VPC, EC2 / 선택: X

**2024 추가과제 실제 출제**: Client VPN 연결 후 로컬 PC 에서 private 서브넷의 Aurora PostgreSQL 에 `psql` 접속 + `day2.local` PHZ 레코드 해석. **반칙 자가검사가 강력**(VPN 끊고 nslookup/ping/netstat 실패 확인 → 하나라도 되면 0점).

**트리거 문구** — "로컬에서 VPC 내부 접근", "Client VPN", "VPN 연결 후 DB 접속", "mutual TLS", "SAML VPN".

**리전 격리** — 전용 VPC. 예시 `ap-northeast-2`.

> 💸 **비용 경고**: Client VPN **endpoint association 은 시간당 과금**(~$0.10/h/association) + 연결시간. 검증 후 즉시 association 해제 + endpoint 삭제.

**전제**
```bash
export R=ap-northeast-2 ACCT=$(aws sts get-caller-identity --query Account --output text)
```

---

## 구성 흐름 (개념)

```
로컬 PC (AWS VPN Client) ──암호화──> Client VPN Endpoint
                                        │ (client_cidr_block = VPN 클라 IP 풀, VPC/로컬과 겹치면 안 됨)
                                        ├─ authentication: mutual-TLS(인증서) 또는 SAML(federated) 또는 AD
                                        ├─ network association: VPC 서브넷 연결 (→ ENI 생성)
                                        ├─ authorization rule: 어떤 CIDR 접근 허용 (authorize-all 또는 그룹별)
                                        └─ route: VPN → target 서브넷/인터넷
```
- **client_cidr_block**: VPN 클라이언트에 줄 IP 풀. **VPC CIDR·로컬 네트워크와 겹치면 안 됨**(가이드 명시 함정). /22 이상.
- **인증**: `certificate-authentication`(mutual TLS, easy-rsa) / `federated-authentication`(SAML) / `directory-service-authentication`(AD).
- **DNS**: endpoint 에 `dns-servers` 지정 → VPN 클라가 그 리졸버 사용(VPC .2 리졸버 주면 PHZ 해석 가능).
- **split-tunnel**: on 이면 VPC 향 트래픽만 VPN, 나머지는 로컬. off 면 전체 VPN.

## 케이스 인덱스

| # | 케이스 | 인증 | 검증 |
|---|---|---|---|
| 01 | `cases/01-mutual-tls/` | 서버/클라 인증서(easy-rsa) → ACM import | ✅ live(cert→ACM→endpoint 성공) |
| 02 | `cases/02-endpoint-deploy/` | endpoint+association+authz+route | ✅ live(endpoint 생성+.ovpn export, 즉시 삭제) |
| 03 | `cases/03-saml-auth/` | SAML federated(Keycloak/IdC) | 스크립트 |
| 04 | `cases/04-split-tunnel-dns/` | split-tunnel + DNS 서버(PHZ 해석) | 스크립트 |

## 검증 (채점자 문체 + 2024 반칙검사)

```bash
# endpoint 상태 + 설정
aws ec2 describe-client-vpn-endpoints --region $R \
  --query "ClientVpnEndpoints[?Description=='lab-cvpn'].{status:Status.Code,cidr:ClientCidrBlock,split:SplitTunnel,auth:AuthenticationOptions[0].Type,dns:DnsServers}" --output json
# association / authorization / route
aws ec2 describe-client-vpn-target-networks --region $R --client-vpn-endpoint-id $EP --query 'ClientVpnTargetNetworks[].Status.Code' --output text
aws ec2 describe-client-vpn-authorization-rules --region $R --client-vpn-endpoint-id $EP --query 'AuthorizationRules[].{cidr:DestinationCidr,status:Status.Code}' --output json
```
2024 반칙 자가검사(로컬 PC, VPN **끊긴** 상태에서 전부 실패해야):
```bash
nslookup db.day2.local      # 실패해야 (VPN 없이 PHZ 해석 불가)
ping db.day2.local          # 호스트 못 찾음
netstat -an | findstr 5432  # 로컬 listen 없어야 (로컬 DB 우회 금지)
# VPN 연결 후: nslookup 이 172.x private IP 반환 + psql 접속 성공
```

## 함정

- **client_cidr_block 겹침 금지**(가이드 핵심) — VPC CIDR·로컬 IP 와 안 겹치게. 겹치면 라우팅 깨짐.
- **mutual-TLS 는 easy-rsa 로 CA/서버/클라 인증서** 생성 → 서버·CA 를 ACM import → 클라 인증서+키를 .ovpn 에 삽입.
- **★ 서버 인증서 CN 은 FQDN 이어야**(실측) — `build-server-full server` 처럼 CN=server 면 ACM DomainName=null → endpoint 생성이 "Certificate does not have a domain" 로 거부. `vpn.lab.internal` 같은 FQDN 으로.
- **endpoint 삭제 후 ACM 인증서 삭제는 지연**(실측 ~1분) — endpoint 가 cert 참조를 놓을 때까지 "in use". 재시도.
- **association 하면 ENI + 시간과금 시작** — 검증 끝나면 즉시 disassociate.
- **authorization rule 없으면 연결돼도 트래픽 0** — target CIDR 허용 필수(authorize-all-groups 또는 SAML 그룹).
- **DNS 안 주면 PHZ 해석 불가** — endpoint `dns-servers` 에 VPC .2 리졸버(예: 10.x.0.2) 지정해야 `db.xxx.local` 해석.
- **split-tunnel off + 0.0.0.0/0 route 없으면** 인터넷 끊김. 목적에 맞게.
- **삭제 순서**: route → authorization rule → network association(→ ENI 회수 대기) → endpoint → ACM 인증서.
- **.ovpn 파일**: `export-client-vpn-client-configuration` + 클라 인증서/키 삽입. AWS VPN Client 로 import.

## context7 참고

- `aws_ec2_client_vpn_endpoint`·`_network_association`·`_authorization_rule`·`_route` (TF AWS v6)
- Client VPN 관리자 가이드: https://docs.aws.amazon.com/vpn/latest/clientvpn-admin/
- 상호 인증(mutual): https://docs.aws.amazon.com/vpn/latest/clientvpn-admin/authentication-authorization.html
