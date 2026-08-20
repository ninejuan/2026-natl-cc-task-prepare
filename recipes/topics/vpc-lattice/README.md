# VPC Lattice 플레이북 (2과제 모듈)

**가이드 원문(2025 #14 / 2026 #5)** — "애플리케이션 서비스 및 리소스 연결·보호·모니터링을 일괄 수행하는 완전관리형 애플리케이션 네트워킹 서비스 VPC Lattice 를 구성. Python 기반 앱을 배포파일로 제공. **VPC Lattice 구성과 무관한 리소스 사용 금지.**"
- 필수: VPC  / 선택: EC2, ELB, DynamoDB(2026)

**트리거 문구** — "서비스 간 통신을 Lattice 로", "service network", "여러 VPC 서비스 연결", "IAM 으로 서비스 접근 제어", "가중 라우팅".

**리전 격리** — 이 모듈 전용 VPC. 다른 모듈 리소스 재사용 금지(가이드 독립성 규칙). 예시는 `ap-northeast-2`.

**전제**
```bash
export R=ap-northeast-2 ACCT=$(aws sts get-caller-identity --query Account --output text)
```

---

## 개념 (5분 정리)

```
Service Network ──(association)── VPC          ← 이 VPC 안 클라이언트가 서비스에 접근 가능
       │
       └──(association)── Service ── Listener ── Rule ── Target Group ── Target
                             │                                            (Lambda/IP/EC2/ALB)
                             └─ auth_type=AWS_IAM → auth policy 로 SigV4 접근제어
```
- **Service Network**: 서비스들의 논리적 경계. VPC 를 associate 하면 그 VPC 클라이언트가 네트워크 내 서비스에 접근.
- **Service**: 실제 애플리케이션. listener(HTTP/HTTPS/TLS) + rule 로 라우팅. 고유 DNS 이름 자동 발급.
- **Target Group 타입**: `LAMBDA`(config 없음) / `IP` / `INSTANCE`(EC2) / `ALB`(health check 없음).
- **접근제어**: service network·service 각각 `auth_type=AWS_IAM` → auth policy(리소스 정책, SigV4 서명 필요).

## 케이스 인덱스

| # | 케이스 | 타깃 | 검증 |
|---|---|---|---|
| 01 | `cases/01-lambda-service/` | Lambda 타깃 서비스(최단 경로) | ✅ live |
| 02 | `cases/02-ec2-instance-target/` | EC2(INSTANCE) 타깃 + health check | 경로(고가 EC2) |
| 03 | `cases/03-path-header-routing/` | 경로·헤더 기반 rule 라우팅 | ✅ live(rule) |
| 04 | `cases/04-weighted/` | 가중 라우팅(카나리) | ✅ live(rule) |
| 05 | `cases/05-auth-policy/` | AWS_IAM auth policy(SigV4) | ✅ live |

가장 흔한 출제는 **01(Lambda 서비스로 최단 구성) + 03/04(라우팅) + 05(IAM 접근제어)** 조합. EC2 타깃(02)은 앱을 EC2 로 요구할 때.

## 검증 (채점자 문체)

```bash
# 서비스/네트워크 식별 (이름으로)
aws vpc-lattice list-services --region $R --query "items[?name=='lab-lattice-svc'].{id:id,dns:dnsEntry.domainName,auth:authType}" --output json
aws vpc-lattice list-service-networks --region $R --query "items[?name=='lab-lattice-net'].id" --output text
# 타깃 그룹 헬스
aws vpc-lattice list-target-groups --region $R --query "items[?name=='lab-tg-lambda'].id" --output text
# 실제 호출: associate 된 VPC 안 EC2 에서 서비스 DNS 로 curl
#   curl -s http://<service-dns-name>/    → 200 + Lambda 응답
```

## 반칙 자가검사

```bash
# "Lattice 구성과 무관한 리소스 금지" → 이 VPC 에 VPN/Peering/TGW/불필요 ALB 없어야
aws ec2 describe-vpc-peering-connections --region $R --query 'VpcPeeringConnections[].VpcPeeringConnectionId' --output text  # 없음
aws ec2 describe-transit-gateways --region $R --query 'TransitGateways[].TransitGatewayId' --output text                    # 없음
# 클라이언트→서비스 접근이 Lattice 경유인지 (VPC association 존재)
aws vpc-lattice list-service-network-vpc-associations --region $R --query 'items[].vpcId' --output text
```

## 함정

- **VPC association 없으면 서비스가 안 보인다** — service network 에 서비스 + VPC 둘 다 associate 필수.
- **Lambda 타깃은 권한** — Lattice 가 Lambda 를 호출하려면 `lambda add-permission --principal vpc-lattice.amazonaws.com`.
- **HTTPS listener 는 ACM 인증서** + 서비스 custom domain 필요. HTTP 는 인증서 불필요(검증 편함).
- **auth_type=AWS_IAM 이면 SigV4 서명 없는 요청은 403** — 검증 curl 도 SigV4 서명하거나, auth policy 에서 anonymous 허용해야 열림.
- **타깃 그룹 타입별 config 차이** — LAMBDA 는 config 블록 없음, ALB 는 health_check 없음, IP/INSTANCE 는 vpc_identifier+port+protocol 필수.
- **Lambda 타깃은 항상 `status: UNAVAILABLE`(reasonCode `HealthCheckNotSupported`)** — 이게 **정상**이다(실측). Lattice 는 Lambda 를 헬스체크하지 않는다. 타깃 그룹 자체가 `ACTIVE` 면 동작함. UNAVAILABLE 보고 당황 말 것.
- **service network 삭제 순서** — association(service·vpc) 먼저 삭제 → **VPC association 은 Lattice-managed ENI 회수까지 ~60-90s** → 그 뒤 service network. 안 기다리면 `ConflictException`(network), `DependencyViolation`(vpc 삭제). teardown.sh 가 폴링+재시도로 처리.
- **rule priority 는 1~2000**(실측) — 초과 시 ValidationException. `default` rule 은 예외(99999).
- **fixedResponse 는 statusCode 404·500 만**(실측) — 403/401/503 은 "not supported". 403 차단은 auth policy(케이스 05)로.
- **VPC Lattice API 는 throttle 이 빡세다**(실측 — 연속 create 시 ThrottlingException 빈발). 스크립트에 create 사이 sleep + 재시도를 넣어라. 채점 3분 제약 안에서 여러 리소스 만들면 특히 주의.

## context7 참고 (최신 문법 확인)

- `aws_vpclattice_service_network`·`_service`·`_listener`·`_listener_rule`·`_target_group`·`_auth_policy` (Terraform AWS provider v6)
- VPC Lattice 개발자 가이드: https://docs.aws.amazon.com/vpc-lattice/latest/ug/
