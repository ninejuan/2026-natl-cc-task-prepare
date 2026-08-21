# Route53 레코드 셋 모음 — ✅ 전종 live 검증

> **실검증(ca-central-1)**: PHZ `lab.internal` 에 아래를 전부 `UPSERT` 하고 `list-resource-record-sets` 로 확인했다.
> 레코드 타입 **A / AAAA / CNAME / MX / TXT / SRV / CAA**,
> 라우팅 정책 **weighted(80:20) / latency(2리전) / failover(헬스체크 연결) / geolocation(KR + `*` 기본) / multivalue**.
> 헬스체크는 `create-health-check` 로 실제 생성해 failover 레코드에 `HealthCheckId` 로 연결했다.


본 문서는 `change-resource-record-sets` 로 넣는 레코드 예시 모음이다. 각 예시의 `ResourceRecordSet`
객체를 `--change-batch '{"Changes":[{"Action":"UPSERT","ResourceRecordSet": … }]}'` 에 넣는다.

```bash
export Z=<HOSTED_ZONE_ID>
aws route53 change-resource-record-sets --hosted-zone-id $Z --change-batch file://rr.json
# 확인
aws route53 list-resource-record-sets --hosted-zone-id $Z \
  --query "ResourceRecordSets[].[Name,Type,SetIdentifier]" --output text
```

라우팅 정책 레코드는 **같은 Name+Type 에 서로 다른 `SetIdentifier`** 로 여러 개 만든다.

## 기본 레코드

- A 레코드 (IPv4)
```json
{"Name":"web.lab.internal","Type":"A","TTL":60,"ResourceRecords":[{"Value":"10.0.0.10"}]}
```

- AAAA (IPv6)
```json
{"Name":"web.lab.internal","Type":"AAAA","TTL":60,"ResourceRecords":[{"Value":"2001:db8::1"}]}
```

- CNAME
```json
{"Name":"www.lab.internal","Type":"CNAME","TTL":300,"ResourceRecords":[{"Value":"web.lab.internal"}]}
```

- MX (메일)
```json
{"Name":"lab.internal","Type":"MX","TTL":300,"ResourceRecords":[{"Value":"10 mail.lab.internal"}]}
```

- TXT (SPF/도메인 검증)
```json
{"Name":"lab.internal","Type":"TXT","TTL":300,"ResourceRecords":[{"Value":"\"v=spf1 include:amazonses.com -all\""}]}
```

- Alias → ALB (TTL 없음, HostedZoneId 는 ALB 리전별 값)
```json
{"Name":"app.lab.internal","Type":"A","AliasTarget":{"HostedZoneId":"ZWKZPGTI48KDX","DNSName":"my-alb-123.ap-northeast-2.elb.amazonaws.com","EvaluateTargetHealth":true}}
```

- Alias → CloudFront (HostedZoneId 항상 Z2FDTNDATAQYW2 고정)
```json
{"Name":"cdn.lab.internal","Type":"A","AliasTarget":{"HostedZoneId":"Z2FDTNDATAQYW2","DNSName":"d111abc.cloudfront.net","EvaluateTargetHealth":false}}
```

- NS 하위 위임
```json
{"Name":"sub.lab.internal","Type":"NS","TTL":300,"ResourceRecords":[{"Value":"ns-1.awsdns-01.com"},{"Value":"ns-2.awsdns-02.net"}]}
```

## 라우팅 정책 레코드 (같은 Name, 다른 SetIdentifier)

- Weighted 80:20 (카나리/블루그린) — 두 레코드
```json
{"Name":"web.lab.internal","Type":"A","SetIdentifier":"blue","Weight":80,"TTL":60,"ResourceRecords":[{"Value":"10.0.0.1"}]}
```
```json
{"Name":"web.lab.internal","Type":"A","SetIdentifier":"green","Weight":20,"TTL":60,"ResourceRecords":[{"Value":"10.0.0.2"}]}
```

- Failover PRIMARY (health check 연결) + SECONDARY
```json
{"Name":"web.lab.internal","Type":"A","SetIdentifier":"primary","Failover":"PRIMARY","HealthCheckId":"HC_ID","TTL":60,"ResourceRecords":[{"Value":"10.0.0.1"}]}
```
```json
{"Name":"web.lab.internal","Type":"A","SetIdentifier":"secondary","Failover":"SECONDARY","TTL":60,"ResourceRecords":[{"Value":"10.0.0.2"}]}
```

- Latency 기반 (리전별) — 가장 가까운 리전으로
```json
{"Name":"web.lab.internal","Type":"A","SetIdentifier":"seoul","Region":"ap-northeast-2","TTL":60,"ResourceRecords":[{"Value":"10.0.0.1"}]}
```
```json
{"Name":"web.lab.internal","Type":"A","SetIdentifier":"tokyo","Region":"ap-northeast-1","TTL":60,"ResourceRecords":[{"Value":"10.1.0.1"}]}
```

- Geolocation (국가별 + default 필수)
```json
{"Name":"web.lab.internal","Type":"A","SetIdentifier":"kr","GeoLocation":{"CountryCode":"KR"},"TTL":60,"ResourceRecords":[{"Value":"10.0.0.1"}]}
```
```json
{"Name":"web.lab.internal","Type":"A","SetIdentifier":"default","GeoLocation":{"CountryCode":"*"},"TTL":60,"ResourceRecords":[{"Value":"10.9.9.9"}]}
```

- Multivalue (여러 답 랜덤, 각각 health check)
```json
{"Name":"web.lab.internal","Type":"A","SetIdentifier":"m1","MultiValueAnswer":true,"HealthCheckId":"HC_ID","TTL":60,"ResourceRecords":[{"Value":"10.0.0.1"}]}
```

- Geoproximity (지리 근접 + bias, AWS 리전 기준)
```json
{"Name":"web.lab.internal","Type":"A","SetIdentifier":"gp-seoul","GeoProximityLocation":{"AWSRegion":"ap-northeast-2","Bias":50},"TTL":60,"ResourceRecords":[{"Value":"10.0.0.1"}]}
```
