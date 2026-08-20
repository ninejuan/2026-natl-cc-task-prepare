# Route53

**트리거 문구** — "DNS 위임", "NS 레코드", "내부에서는 172.x, 외부에서는 54.x"(split-view), "라우팅 정책", "헬스체크", "Private Hosted Zone 생성 시 감점"(→ split-view 를 PHZ 없이 풀라는 함정).

**전제**
```bash
export R=ap-northeast-2
```
Route53 은 글로벌 서비스라 `--region` 불필요(단 health check 등 일부는 us-east-1 기준).

---

## ★ 케이스 A — split-view DNS [검증됨]

2024 추가과제 핵심. **같은 이름을 VPC 안에서는 내부 IP, 밖에서는 공인 IP** 로 응답. Public + Private hosted zone 을 같은 도메인으로 만든다.

```bash
ZONE=lab.internal
VPC=<과제 VPC ID>

# Public hosted zone (외부 응답용)
PUB=$(aws route53 create-hosted-zone --name $ZONE --caller-reference "pub-$(date +%s)" \
  --query 'HostedZone.Id' --output text | sed 's|/hostedzone/||')

# Private hosted zone (VPC 연결, 내부 응답용) — 같은 이름
PRIV=$(aws route53 create-hosted-zone --name $ZONE --caller-reference "priv-$(date +%s)" \
  --vpc "VPCRegion=$R,VPCId=$VPC" --query 'HostedZone.Id' --output text | sed 's|/hostedzone/||')

# 같은 레코드, 다른 값
aws route53 change-resource-record-sets --hosted-zone-id $PUB --change-batch '{
  "Changes":[{"Action":"UPSERT","ResourceRecordSet":{"Name":"q1.lab.internal","Type":"A","TTL":60,"ResourceRecords":[{"Value":"54.0.0.10"}]}}]}'
aws route53 change-resource-record-sets --hosted-zone-id $PRIV --change-batch '{
  "Changes":[{"Action":"UPSERT","ResourceRecordSet":{"Name":"q1.lab.internal","Type":"A","TTL":60,"ResourceRecords":[{"Value":"172.16.0.10"}]}}]}'
```
- **VPC 안**(Route53 Resolver 사용)에서 질의 → PHZ 우선 → `172.16.0.10`.
- **VPC 밖**에서 질의 → public 권위서버 → `54.0.0.10`.
- 검증: public 은 권위서버 직접 질의로 확인, private 은 VPC 내 EC2 에서 `nslookup`.

```bash
NS=$(aws route53 get-hosted-zone --id $PUB --query 'DelegationSet.NameServers[0]' --output text)
dig +short @$NS q1.lab.internal A     # 54.0.0.10
# VPC 내 EC2 에서: nslookup q1.lab.internal  →  172.16.0.10
```

> ⚠️ **함정 뒤집기**: 과제가 "Private Hosted Zone 생성 시 감점" 이라고 하면 위 방법이 **금지**다. 그땐 **IP 기반 라우팅(CIDR)** 또는 Resolver 규칙으로 풀어야 한다. 과제 문구를 정확히 읽어라 — 2024 는 PHZ 로 푸는 문제와 PHZ 금지 문제가 **둘 다** 나왔다. PHZ 금지면 아래 케이스 F.

## 케이스 B — NS 하위 위임

상위 도메인에서 하위를 다른 zone 으로 위임. "NS 레코드를 등록" 형.

```bash
# 하위 zone 생성 → NS 확인
SUB=$(aws route53 create-hosted-zone --name sub.lab.internal --caller-reference "sub-$(date +%s)" \
  --query 'HostedZone.Id' --output text | sed 's|/hostedzone/||')
aws route53 get-hosted-zone --id $SUB --query 'DelegationSet.NameServers' --output json

# 상위 zone 에 NS 레코드로 위임
aws route53 change-resource-record-sets --hosted-zone-id $PARENT --change-batch '{
  "Changes":[{"Action":"UPSERT","ResourceRecordSet":{"Name":"sub.lab.internal","Type":"NS","TTL":300,
    "ResourceRecords":[{"Value":"ns-xxx.awsdns-xx.com"},{"Value":"ns-yyy.awsdns-yy.net"}]}}]}'
```
2024 는 상위 계정(`cloudhrdk*.com`)에 NS 를 GitHub Issue 로 등록하면 운영진이 위임하는 형태였다. **잘못된 NS 를 주면 위임 실패** — `get-hosted-zone` 의 NS 4개를 정확히.

> 📎 **레코드 셋 예시 모음**: `route53/record-sets.md` — A/AAAA/CNAME/MX/TXT/NS/Alias(ALB·CloudFront) 기본 레코드 + weighted/failover/latency/geolocation/multivalue/geoproximity 정책 레코드를 그대로 `--change-batch` 에 넣는 JSON 으로.

## 케이스 C~ — 라우팅 정책 (전종 검증됨)

같은 이름 + 다른 `SetIdentifier` 로 정책 레코드를 만든다.

```bash
# weighted (가중 분산) — 80:20
aws route53 change-resource-record-sets --hosted-zone-id $PUB --change-batch '{
  "Changes":[
    {"Action":"UPSERT","ResourceRecordSet":{"Name":"web.lab.internal","Type":"A","SetIdentifier":"blue","Weight":80,"TTL":60,"ResourceRecords":[{"Value":"10.0.0.1"}]}},
    {"Action":"UPSERT","ResourceRecordSet":{"Name":"web.lab.internal","Type":"A","SetIdentifier":"green","Weight":20,"TTL":60,"ResourceRecords":[{"Value":"10.0.0.2"}]}}]}'

# failover (primary/secondary + health check)
HC=$(aws route53 create-health-check --caller-reference "hc-$(date +%s)" \
  --health-check-config '{"Type":"HTTP","ResourcePath":"/health","FullyQualifiedDomainName":"example.com","Port":80,"RequestInterval":30,"FailureThreshold":3}' \
  --query 'HealthCheck.Id' --output text)
# PRIMARY 에 HealthCheckId, SECONDARY 는 폴백
#   Failover:PRIMARY + HealthCheckId:$HC / Failover:SECONDARY

# latency (Region 별)
#   Region: ap-northeast-2 / ap-northeast-1

# geolocation (국가별)
#   GeoLocation:{CountryCode:KR} / GeoLocation:{CountryCode:*}  (default 필수)

# multivalue (여러 IP 중 랜덤, 각각 health check)
#   MultiValueAnswer:true + SetIdentifier + HealthCheckId
```

| 정책 | 핵심 필드 | 용도 |
|---|---|---|
| simple | (없음) | 단일 값 |
| weighted | `Weight` | 가중 분산·카나리 |
| failover | `Failover` + `HealthCheckId` | 액티브-스탠바이 |
| latency | `Region` | 가장 가까운 리전 |
| geolocation | `GeoLocation.CountryCode` (`*` default 필수) | 국가별 |
| geoproximity | `GeoProximityLocation` | 지리 근접+bias |
| multivalue | `MultiValueAnswer` | 여러 답 랜덤 |

**geolocation 은 `*`(default) 가 없으면** 매칭 안 되는 위치에 응답이 없다 — 반드시 default.

## 케이스 D — alias (AWS 리소스로)

```bash
# ALB/CloudFront/S3 로. TTL 없고 HostedZoneId 필요.
aws route53 change-resource-record-sets --hosted-zone-id $PUB --change-batch '{
  "Changes":[{"Action":"UPSERT","ResourceRecordSet":{"Name":"app.lab.internal","Type":"A",
    "AliasTarget":{"HostedZoneId":"<ALB zone id>","DNSName":"<alb dns>","EvaluateTargetHealth":true}}}]}'
```
CloudFront alias 의 HostedZoneId 는 항상 `Z2FDTNDATAQYW2`(고정).

## 케이스 E — Resolver (하이브리드 DNS)

```bash
# inbound endpoint: 온프렘 → VPC DNS 질의
# outbound endpoint + rule: VPC → 특정 도메인을 온프렘/외부로 포워딩
aws route53resolver create-resolver-endpoint --direction OUTBOUND ...
aws route53resolver create-resolver-rule --rule-type FORWARD --domain-name corp.example.com ...
```
Client VPN + 온프렘 DNS 연동, 또는 특정 도메인만 다른 리졸버로 보낼 때.

## 케이스 F — PHZ 없이 split-view (PHZ 금지 시)

PHZ 를 금지한 과제라면:
- **Resolver rule** 로 특정 도메인 질의를 내부 리졸버로 포워딩.
- 또는 **IP 기반 라우팅**: `create-cidr-collection` + `CidrRoutingConfig` 로 소스 IP 대역별 응답. VPC NAT 공인 IP 대역을 한 컬렉션에 넣어 내부/외부를 가른다.

## 검증

```bash
aws route53 list-hosted-zones --query "HostedZones[].[Name,Id,Config.PrivateZone]" --output text
aws route53 list-resource-record-sets --hosted-zone-id $PUB \
  --query "ResourceRecordSets[?Type=='A'].[Name,SetIdentifier,ResourceRecords[0].Value]" --output text
NS=$(aws route53 get-hosted-zone --id $PUB --query 'DelegationSet.NameServers[0]' --output text)
dig +short @$NS q1.lab.internal A
# 채점: VPC 내 EC2 nslookup(172) vs 외부 nslookup(54) 비교
```

## Terraform [검증됨: apply→dig 54.0.0.10 + weighted→destroy]

`terraform-route53/main.tf` — split-view(public+private zone, 같은 이름) + weighted. `vpc_id` 변수 필요.

```bash
cd terraform-route53
terraform apply -auto-approve -var "vpc_id=$(aws ec2 describe-vpcs --filters Name=tag:Name,Values=<vpc> --query 'Vpcs[0].VpcId' --output text)"
NS=$(terraform output -json public_ns | python3 -c 'import sys,json;print(json.load(sys.stdin)[0])')
dig +short @$NS q1.lab-tf.internal A   # 54.0.0.10
terraform destroy -auto-approve -var "vpc_id=..."
```
핵심:
```hcl
resource "aws_route53_zone" "pub"  { name = var.zone }
resource "aws_route53_zone" "priv" { name = var.zone
  vpc { vpc_id = var.vpc_id } }          # 같은 이름 + VPC 연결 = private view
resource "aws_route53_record" "w_blue" {
  set_identifier = "blue"
  weighted_routing_policy { weight = 80 }   # 정책별 전용 블록
}
```
- 라우팅 정책마다 전용 블록: `weighted_routing_policy`·`failover_routing_policy`·`latency_routing_policy`·`geolocation_routing_policy`·`multivalue_answer_routing_policy`.
- alias 는 `alias { name, zone_id, evaluate_target_health }` 블록(ttl/records 대신).

## Console 팁

- **라우팅 정책 마법사**: 레코드 생성 시 정책을 드롭다운으로. failover 는 health check 를 폼에서 연결. geolocation 지도 UI.
- **Traffic flow**(고급): 정책을 시각적 트리로 조합(비용 있음). 복잡한 다단계 라우팅에.
- **Resolver**: inbound/outbound endpoint·규칙을 폼으로. 하이브리드 DNS.
- **테스트 레코드**: 레코드 콘솔의 "Test record" 로 정책 결과를 시뮬레이션(위치·클라이언트 IP 지정).

## 참고 문서

- Route53 개발자 가이드: https://docs.aws.amazon.com/Route53/latest/DeveloperGuide/
- 라우팅 정책: https://docs.aws.amazon.com/Route53/latest/DeveloperGuide/routing-policy.html
- split-view(private+public): https://docs.aws.amazon.com/Route53/latest/DeveloperGuide/hosted-zones-private-considerations.html
- Terraform `aws_route53_record`: https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route53_record

## 함정

- **PHZ 금지 문구**를 놓치면 split-view 를 PHZ 로 풀어서 통째로 0점. 문구 정독.
- **NS 위임은 정확한 4개** — `get-hosted-zone` 의 NameServers 를 그대로.
- **geolocation default(`*`) 누락** — 매칭 안 되는 위치 무응답.
- **TTL 캐싱** — 값 바꿔도 TTL 동안 옛 답. 검증 시 TTL 짧게(60) + 권위서버 직접 질의(`@NS`)로 캐시 우회.
- **PHZ 는 VPC 연결 필수** — 연결 안 하면 어디서도 안 보인다. 여러 VPC 는 `associate-vpc-with-hosted-zone`.
- **alias 는 TTL 없음** — TTL 넣으면 에러. HostedZoneId 필수.
- health check 는 **글로벌**(us-east-1 기준 생성). 리전 무관.
- **macOS dig 가 빈 결과** 낼 때 있음 — `nslookup <name> <NS>` 로 교차 확인.

## 정리
```bash
# 레코드 먼저 삭제(zone 은 레코드 있으면 삭제 불가, SOA/NS 제외)
# health check 삭제 후 zone 삭제
aws route53 delete-health-check --health-check-id $HC
aws route53 delete-hosted-zone --id $PUB
aws route53 delete-hosted-zone --id $PRIV
```
