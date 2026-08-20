# 케이스 04 — split-tunnel + DNS (PHZ 해석, 2024 추가과제 핵심)

2024 추가과제: VPN 연결 후 로컬에서 `db.day2.local`(Private Hosted Zone CNAME)이 **private IP 로 해석**되고 그 DB 에 `psql` 접속. VPN 끊으면 전부 실패해야 함.

## split-tunnel

```bash
# endpoint 생성 시 --split-tunnel (VPC 향만 VPN, 나머지는 로컬 인터넷)
aws ec2 modify-client-vpn-endpoint --region $R --client-vpn-endpoint-id $EP --split-tunnel
# off (전체 VPN): --no-split-tunnel + 0.0.0.0/0 route + authz
```
- **split-tunnel on**: VPC CIDR + 지정 route 만 VPN 경유. 로컬 인터넷 유지. 대회 검증 편함.
- **off**: 모든 트래픽 VPN. 인터넷 주려면 `create-client-vpn-route 0.0.0.0/0` + authz + NAT.

## DNS (PHZ 해석의 핵심)

```bash
# endpoint 의 dns-servers 를 VPC .2 리졸버로 → VPN 클라가 PHZ 를 해석
aws ec2 modify-client-vpn-endpoint --region $R --client-vpn-endpoint-id $EP \
  --dns-servers "CustomDnsServers=10.40.0.2"   # VPC CIDR 의 .2 (Route53 Resolver)
```
- **VPC .2 리졸버**를 줘야 그 VPC 에 연결된 **Private Hosted Zone** 레코드(`db.day2.local`)를 해석한다.
- 안 주면 로컬 DNS 를 써서 PHZ 를 못 본다 → 2024 채점 실패.
- PHZ 는 이 VPC 에 associate 돼 있어야(`route53 associate-vpc-with-hosted-zone`).

## 2024 재현 검증 흐름 (반칙검사 포함)

```
[VPN 끊긴 상태] nslookup db.day2.local → 실패 / ping → 호스트 못찾음 / netstat 5432 → 없음   (전부 실패해야 정상)
[VPN 연결]     nslookup db.day2.local → 172.x private IP (CNAME rds.amazonaws.com 포함)
               psql -U root -d db -h db.day2.local → 접속 성공
```

## 함정

- **client_cidr 겹침**(가이드 명시) — VPN 클라 IP 풀이 VPC/로컬과 겹치면 라우팅 붕괴.
- **DNS 서버 미지정 → PHZ 해석 불가** — 가장 흔한 2024 감점.
- **PHZ ↔ VPC association 필수** — VPN 붙는 VPC 에 PHZ 가 연결돼 있어야.
- **split-tunnel off 인데 route/authz 부족** → 인터넷·대상 접근 안 됨.
- 로컬 PC 에 로컬 DB 설치·hosts 변조 = 반칙(2024 채점이 명시적으로 잡음).
