# WAF Bot Control

`botcontrol.json` — AWS 관리형 Bot Control 룰그룹. 스크레이퍼/스캐너 등 봇 트래픽 탐지·차단. 실검증됨(create-web-acl 수락).

```bash
aws wafv2 create-web-acl --region ap-northeast-2 --name lab-bot --scope REGIONAL --default-action Allow={} \
  --rules file://botcontrol.json \
  --visibility-config "SampledRequestsEnabled=true,CloudWatchMetricsEnabled=true,MetricName=lab-bot"
```

- **InspectionLevel**: `COMMON`(기본, 저비용) / `TARGETED`(고급 봇, 추가 요금). `ManagedRuleGroupConfigs` 로 지정.
- Bot Control 은 **추가 요금**(요청량 기반) — 과제에서 명시 요구 시에만.
- 개별 봇 카테고리(검색엔진 허용 등)는 `RuleActionOverrides` 로 조정.
- 기반: 다른 managed/custom 룰은 `../../../../aws/tier2/waf/rule-statements.json`(12종).
