# Network Firewall 플레이북 (2과제 Secure networking 모듈)

**가이드 원문(2025 #1)** — "Network Firewall 로 VPC 의 Ingress/Egress 트래픽을 제어·검사. **DNS Query Filtering, Threat Hunting, Egress Web Filtering** 등을 예로 들 수 있음. 단, Network Firewall 을 단순 트래픽 전달(transparently)로 쓰고 별도 3rd-party tool 을 쓰는 것은 금지."
- 필수: VPC, Network Firewall / 선택: EC2(검증용), Route53

**트리거 문구** — "Egress 필터링", "특정 도메인만 허용", "악성 트래픽 차단", "Suricata 규칙", "DNS 필터링", "네트워크 트래픽 검사".

**리전 격리** — 이 모듈 전용 VPC. 예시 `ap-northeast-2`.

**전제**
```bash
export R=ap-northeast-2 ACCT=$(aws sts get-caller-identity --query Account --output text)
```

> 💸 **비용 경고**: Firewall **엔드포인트는 시간당 과금**(~$0.395/h) + 처리 GB. rule group·policy 생성은 무료. 검증 시 rule group/policy 는 실제로 만들되, **firewall 엔드포인트(케이스 05)는 만들면 즉시 삭제**.

---

## 개념 (5분 정리)

```
                    ┌─ stateless rule group  (5-tuple, 빠른 pass/drop/forward)
Firewall Policy ────┤
                    └─ stateful rule group   (Suricata, 도메인/프로토콜/세션 인지)
        │
    Firewall (VPC + 각 AZ inspection subnet 의 endpoint)
        │
    라우팅: IGW→firewall subnet→protected subnet (inspection 경유 강제)
```
- **stateless**(5-tuple): source/dest IP·port·protocol 로 즉시 pass/drop, 또는 stateful 로 forward.
- **stateful**(Suricata): 도메인·프로토콜·세션 상태 인지. `rules_source_list`(도메인 allow/deny) 또는 `rules_string`(Suricata 원문) 또는 `stateful_rule`(구조화).
- **rule_order**: `DEFAULT_ACTION_ORDER`(action 우선) vs `STRICT_ORDER`(priority 순서, 명시적).
- **로깅**: ALERT / FLOW / TLS 로그를 CloudWatch·S3·Firehose 로.

## 케이스 인덱스

| # | 케이스 | 내용 | 검증 |
|---|---|---|---|
| 01 | `cases/01-stateless-5tuple/` | stateless 5-tuple pass/drop | ✅ live(rule group) |
| 02 | `cases/02-stateful-suricata/` | Suricata 원문 규칙(Threat Hunting) | ✅ live(rule group) |
| 03 | `cases/03-domain-filtering/` | 도메인 allow/deny (Egress Web Filtering) | ✅ live(rule group) |
| 04 | `cases/04-policy-logging/` | firewall policy + 로깅 설정 | ✅ live(policy) |
| 05 | `cases/05-firewall-deploy/` | firewall 엔드포인트 + 라우팅(inspection VPC) | ✅ live(READY, 즉시 삭제) |

가장 흔한 출제: **03(도메인 egress 필터링)** 또는 **02(Suricata threat)** + **04 policy** + **05 배포**.

## 검증 (채점자 문체)

```bash
# rule group 식별 + capacity/type
aws network-firewall describe-rule-group --region $R --rule-group-name lab-nfw-domain --type STATEFUL \
  --query 'RuleGroup.RulesSource.RulesSourceList' --output json
# policy 구성
aws network-firewall describe-firewall-policy --region $R --firewall-policy-name lab-nfw-policy \
  --query 'FirewallPolicy.{stateless:StatelessDefaultActions,statefulRefs:StatefulRuleGroupReferences[].ResourceArn}' --output json
# firewall 상태
aws network-firewall describe-firewall --region $R --firewall-name lab-nfw \
  --query 'Firewall.FirewallStatus.Status' --output text  # READY
# 기능 검증: protected subnet EC2 에서 curl
#   curl -m 5 https://allowed.example.com   → 200
#   curl -m 5 https://blocked.example.com   → 타임아웃/차단
```

## 반칙 자가검사

```bash
# "transparently 전달 + 3rd-party 금지" → NFW 가 실제로 규칙을 갖고 검사하는지
aws network-firewall describe-firewall-policy --region $R --firewall-policy-name lab-nfw-policy \
  --query 'FirewallPolicy.StatefulRuleGroupReferences | length(@)' --output text  # >0 이어야
# 라우팅이 실제로 firewall 경유인지(inspection subnet 경유)
aws ec2 describe-route-tables --region $R --filters Name=vpc-id,Values=$VPC \
  --query 'RouteTables[].Routes[?GatewayId!=`local`].[DestinationCidrBlock,GatewayId,VpcEndpointId]' --output text
```

## 함정

- **capacity 는 생성 시 고정** — rule group 예상 규칙 수를 넉넉히(도메인 리스트는 도메인당 소비). 부족하면 규칙 추가 불가 → 재생성.
- **STRICT_ORDER 면 stateful reference 에 priority 필수**, DEFAULT_ACTION_ORDER 면 priority 불가.
- **도메인 필터링은 HTTP Host / TLS SNI 기반** — `target_types`: `HTTP_HOST`, `TLS_SNI`. HTTPS 도메인 차단하려면 TLS_SNI 도.
- **라우팅이 핵심** — firewall 만들고 IGW/subnet 라우트를 inspection endpoint 로 안 바꾸면 트래픽이 검사를 안 거친다("transparently" 반칙과 반대로, 아예 검사 안 됨).
- **endpoint 는 AZ 마다** — protected subnet 이 있는 AZ 마다 firewall subnet + endpoint.
- **firewall 삭제 전 라우트 원복** — endpoint 참조 라우트가 남으면 삭제 실패.
- 로그 그룹/버킷은 firewall 과 같은 리전.
- **firewall 생성/삭제가 느리다(실측 각 수 분)** — PROVISIONING→READY, DELETING 이 5~10분. 채점 3분 제약과 안 맞으니 firewall 자체는 **미리 만들어져 있어야**(과제가 firewall 생성을 요구하면 시간 배분 주의).
- **삭제 의존성 순서(실측)**: ① firewall endpoint 참조 라우트 삭제 → ② firewall 삭제(수 분) → ③ firewall policy 삭제 → ④ rule group 삭제. 역순이면 "related VPC endpoint still exist"·"still referenced" 에러.
- **★ `create-route --vpc-endpoint-id` 로 만든 firewall 라우트는 describe 시 endpoint 가 `GatewayId` 필드에 뜬다**(VpcEndpointId 아님, 실측). 그래서 삭제는 destination cidr 로. 이걸 모르면 "route 못 찾음 → firewall 삭제 실패" 무한루프.

## context7 참고

- `aws_networkfirewall_rule_group`·`_firewall_policy`·`_firewall`·`_logging_configuration` (TF AWS v6)
- Network Firewall 개발자 가이드: https://docs.aws.amazon.com/network-firewall/latest/developerguide/
- Suricata 규칙 형식: https://docs.aws.amazon.com/network-firewall/latest/developerguide/suricata-rule-evaluation-order.html
