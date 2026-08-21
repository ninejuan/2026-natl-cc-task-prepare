# 케이스 04 — split-tunnel + DNS (PHZ 해석, 2024 추가과제 핵심) — ✅ live 검증

2024 추가과제: VPN 연결 후 로컬에서 `db.day2.local`(Private Hosted Zone)이 **private IP 로 해석**되고 그 DB 에 `psql` 접속. VPN 끊으면 전부 실패해야 함.

`verify.sh` 가 케이스 03(SAML)까지 함께 만들고 검증하고 지운다(ap-southeast-1). 아래는 그 실측 결과.

## split-tunnel

```bash
# endpoint 생성 시 --split-tunnel (VPC 향만 VPN, 나머지는 로컬 인터넷)
aws ec2 create-client-vpn-endpoint --region $R --description lab-cvpn-split \
  --server-certificate-arn $SC --client-cidr-block 172.31.240.0/22 \
  --authentication-options "Type=certificate-authentication,MutualAuthentication={ClientRootCertificateChainArn=$SC}" \
  --connection-log-options Enabled=false \
  --split-tunnel --dns-servers 10.40.0.2
```
실측 `describe-client-vpn-endpoints`:
```json
{"status":"pending-associate","cidr":"172.31.240.0/22","split":true,
 "dns":["10.40.0.2"],"auth":"certificate-authentication"}
```
서브넷 association 후 `Status.Code` = **`available`**, 라우트/인가는:
```
routes:  10.40.0.0/16   Nat        active      ← association 이 자동 생성
authz:   10.40.0.0/16   AccessAll=True  authorizing
```

## DNS (PHZ 해석의 핵심) — ★ 실측 정정

```bash
aws ec2 modify-client-vpn-endpoint --region $R --client-vpn-endpoint-id $EP \
  --dns-servers "CustomDnsServers=10.40.0.2"   # VPC CIDR 의 .2 (Route53 Resolver)
```
- **VPC .2 리졸버**를 줘야 그 VPC 에 연결된 PHZ 레코드를 해석한다. 실측: VPC 안 EC2 에서
  `dig +short db.day2.local @10.40.0.2` → **`10.40.1.99`** (기본 리졸버로도 동일).
- **★ `export-client-vpn-client-configuration` 로 받은 `.ovpn` 에는 `dhcp-option DNS` 가 들어 있지 않다**(실측).
  DNS 서버는 **연결 시 서버가 push** 한다. 파일만 열어보고 "DNS 설정이 빠졌다"고 오해하지 말 것.
  `.ovpn` 에 실제로 들어 있는 것: `remote <endpoint>.prod.clientvpn.<R>.amazonaws.com 443`,
  `cipher AES-256-GCM`, **`verify-x509-name server.lab-cvpn.example.com name`**.
- ↑ 마지막 줄이 **서버 인증서 CN 을 FQDN 으로 만들어야 하는 이유**다. 클라이언트가 CN 을 검증한다.
- PHZ 는 이 VPC 에 associate 돼 있어야(`create-hosted-zone --vpc VPCRegion=..,VPCId=..`).

## 2024 재현 검증 흐름 (반칙검사 포함)

```
[VPN 끊긴 상태] nslookup db.day2.local → 실패 / ping → 호스트 못찾음 / netstat 5432 → 없음   (전부 실패해야 정상)
[VPN 연결]     nslookup db.day2.local → 10.40.1.99 (private IP)
               psql -U root -d db -h db.day2.local → 접속 성공
```
> 터널 자체(로컬 AWS VPN Client 연결)는 GUI 클라이언트가 필요해 CLI 로 자동화 불가.
> 대신 **VPN 클라가 받게 될 DNS 서버(.2 리졸버)가 PHZ 를 실제로 푸는지**를 VPC 내부에서 증명했다.

## 함정 (실측 반영)

- **client_cidr 겹침**(가이드 명시) — VPN 클라 IP 풀이 VPC/로컬과 겹치면 라우팅 붕괴. /22 이상.
- **DNS 서버 미지정 → PHZ 해석 불가** — 가장 흔한 2024 감점.
- **`.ovpn` 에 DNS 는 안 보인다** — 위 참조. 확인은 `describe-client-vpn-endpoints … DnsServers`.
- **서버 인증서 CN 은 FQDN** — `.ovpn` 의 `verify-x509-name` 이 CN 을 검증. CN 이 호스트명이 아니면 ACM DomainName 이 null 이 되어 endpoint 생성부터 거부된다.
- **association 은 시간과금**(~$0.10/h) + association/disassociation 각각 수 분. 검증 후 즉시 해제.
- **split-tunnel off 인데 route/authz 부족** → 인터넷·대상 접근 안 됨.
- 로컬 PC 에 로컬 DB 설치·hosts 변조 = 반칙(2024 채점이 명시적으로 잡음).
