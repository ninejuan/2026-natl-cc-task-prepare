# WAF (WAFv2)

**트리거 문구** — "WAF 로 공격 차단", "rate limit", "managed rule", "SQL injection/XSS 차단", "403 Request blocked", "IP 차단", "geo 차단".

**전제**
```bash
export R=ap-northeast-2
```
> ★ **scope 2가지**: `REGIONAL`(ALB/APIGW/AppSync, 해당 리전) vs `CLOUDFRONT`(CloudFront, **us-east-1 고정**). CloudFront 에 붙일 거면 `--scope CLOUDFRONT --region us-east-1`.

---

## ★ 케이스 A — managed rule + rate limit + custom 403 [검증됨]

2026 task1 WAF 요구("Common+KnownBadInputs, rate limit 60초 50건, 403 커스텀 body") 대응.

```bash
cat > rules.json <<'JSON'
[
  {"Name":"common","Priority":1,"OverrideAction":{"None":{}},
   "Statement":{"ManagedRuleGroupStatement":{"VendorName":"AWS","Name":"AWSManagedRulesCommonRuleSet"}},
   "VisibilityConfig":{"SampledRequestsEnabled":true,"CloudWatchMetricsEnabled":true,"MetricName":"common"}},
  {"Name":"badinputs","Priority":2,"OverrideAction":{"None":{}},
   "Statement":{"ManagedRuleGroupStatement":{"VendorName":"AWS","Name":"AWSManagedRulesKnownBadInputsRuleSet"}},
   "VisibilityConfig":{"SampledRequestsEnabled":true,"CloudWatchMetricsEnabled":true,"MetricName":"badinputs"}},
  {"Name":"ratelimit","Priority":3,
   "Action":{"Block":{"CustomResponse":{"ResponseCode":403,"CustomResponseBodyKey":"blocked"}}},
   "Statement":{"RateBasedStatement":{"Limit":100,"EvaluationWindowSec":60,"AggregateKeyType":"IP"}},
   "VisibilityConfig":{"SampledRequestsEnabled":true,"CloudWatchMetricsEnabled":true,"MetricName":"ratelimit"}}
]
JSON
ACL=$(aws wafv2 create-web-acl --region $R --name lab-waf --scope REGIONAL \
  --default-action Allow={} \
  --rules file://rules.json \
  --custom-response-bodies '{"blocked":{"ContentType":"TEXT_PLAIN","Content":"Request blocked by Skills WAF"}}' \
  --visibility-config "SampledRequestsEnabled=true,CloudWatchMetricsEnabled=true,MetricName=lab-waf" \
  --query 'Summary.Id' --output text)
```
- **managed rule 은 `OverrideAction`**(None=룰대로 적용, Count=탐지만), custom 룰은 `Action`(Block/Allow/Count). 둘을 헷갈리면 스키마 에러.
- **rate limit**: `Limit`(최소 10) + `EvaluationWindowSec`(60/120/300/600) + `AggregateKeyType`(IP/FORWARDED_IP/...).
- **custom 403 body**: `--custom-response-bodies` 로 key 정의 → 룰에서 `CustomResponseBodyKey` 참조. Rate-based statement 예제의 `Limit` 는 과제지 값(예 50)으로.

## 케이스 B — 리소스 연결 [검증됨: topics/waf]

```bash
# ALB (REGIONAL)
aws wafv2 associate-web-acl --region $R \
  --web-acl-arn "$(aws wafv2 get-web-acl --region $R --name lab-waf --scope REGIONAL --id $ACL --query WebACL.ARN --output text)" \
  --resource-arn "$ALB_ARN"
# CloudFront: associate 대신 distribution config 의 WebACLId 에 ACL ARN. us-east-1 scope.
```

> 📎 **rule statement 12종 모음**: `waf/rule-statements.json` — managed(Common/SQLi/BadInputs/오버라이드), rate limit(IP/경로별), IP set, geo(허용/차단), 헤더매칭, AND 조합, size 제약까지 전부 실제 create-web-acl 로 검증. **CLI 주의**: ByteMatch `SearchString` 은 base64 인코딩 필수(콘솔·TF 는 평문).

## 케이스 C — IP set / geo match [검증됨: topics/waf 03 — ipset+3rules]

```bash
# IP set (차단/허용 목록)
IPSET=$(aws wafv2 create-ip-set --region $R --name lab-block --scope REGIONAL \
  --ip-address-version IPV4 --addresses "1.2.3.0/24" "5.6.7.8/32" --query 'Summary.Id' --output text)
# 룰: {"Statement":{"IPSetReferenceStatement":{"ARN":"<ipset-arn>"}},"Action":{"Block":{}}}

# geo match (특정 국가만 허용/차단)
# {"Statement":{"GeoMatchStatement":{"CountryCodes":["KR","JP"]}},...}
# "KR 외 차단": NotStatement + GeoMatchStatement
```

## 케이스 D — 로깅 [검증됨: topics/waf 05 — 12rule ACL + CW 로그그룹 연결]

```bash
# WAF 로그 → CloudWatch Logs (로그 그룹명은 aws-waf-logs- 접두어 필수)
aws logs create-log-group --region $R --log-group-name aws-waf-logs-lab
aws wafv2 put-logging-configuration --region $R --logging-configuration \
  "ResourceArn=<acl-arn>,LogDestinationConfigs=[arn:aws:logs:$R:$ACCT:log-group:aws-waf-logs-lab]"
```
로그 그룹 이름이 **`aws-waf-logs-` 로 시작**해야 한다(강제).

## 검증

```bash
aws wafv2 get-web-acl --region $R --name lab-waf --scope REGIONAL --id $ACL \
  --query 'WebACL.Rules[].[Name,Priority]' --output text
# rate limit 트리거 (연결된 엔드포인트에 폭주 → 403)
for i in $(seq 1 200); do curl -s -o /dev/null "https://$CF_OR_ALB/"; done
curl -s -o /dev/null -w '%{http_code}\n' "https://$CF_OR_ALB/"   # 403
# SQLi 시도 (Common rule 차단)
curl -s -o /dev/null -w '%{http_code}\n' "https://$CF_OR_ALB/?q=1'%20OR%201=1--"  # 403
```
채점(2026 task1 mark.sh): `list-web-acls` → `get-web-acl` 로 rate limit `Limit` 값 확인, 실제 curl 폭주로 403 유도.

## Terraform [검증됨: WebACL(managed+rate+custom403) apply→destroy]

`terraform-waf/main.tf` — WebACL + managed rule + rate limit + custom 403 body.

```hcl
resource "aws_wafv2_web_acl" "acl" {
  scope = "REGIONAL"   # CloudFront 면 CLOUDFRONT + provider us-east-1
  default_action {
    allow {}
  }
  custom_response_body {
    key          = "blocked"
    content      = "Request blocked by Skills WAF"
    content_type = "TEXT_PLAIN"
  }
  rule {
    name     = "common"
    priority = 1
    override_action {   # managed rule = override_action
      none {}
    }
    statement {
      managed_rule_group_statement {
        vendor_name = "AWS"
        name        = "AWSManagedRulesCommonRuleSet"
      }
    }
    visibility_config { sampled_requests_enabled = true, cloudwatch_metrics_enabled = true, metric_name = "common" }
  }
  rule {
    name     = "ratelimit"
    priority = 2
    action {   # custom rule = action
      block {
        custom_response { response_code = 403, custom_response_body_key = "blocked" }
      }
    }
    statement {
      rate_based_statement { limit = 100, aggregate_key_type = "IP" }
    }
    visibility_config { ... }
  }
  visibility_config { ... }
}
# 연결: aws_wafv2_web_acl_association { resource_arn = <alb>, web_acl_arn = ... }
# CloudFront: distribution 의 web_acl_id 에 ACL ARN
```
> **TF 검수**: `default_action`/`override_action { none {} }`/`action { block {} }` 은 **여러 줄 블록**이어야 한다(단일 라인 `{ allow {} }` 는 파싱 에러 — 실제로 밟음). managed=`override_action`, custom=`action` 구분은 CLI 와 동일.

## Console 팁

- **WebACL 마법사**: managed rule group 을 카탈로그에서 골라 추가(Common/KnownBadInputs/SQLi/IP reputation 등). rate limit·custom response 를 폼으로.
- **연결 대상**: 생성 중 ALB/APIGW/CloudFront 를 선택해 바로 연결.
- **Sampled requests / 로그**: 실시간 샘플로 어떤 룰이 무엇을 차단하는지. 룰 튜닝에 필수.
- **Rule 순서**: 콘솔에서 드래그로 priority 조정.

## 참고 문서

- WAF 개발자 가이드: https://docs.aws.amazon.com/waf/latest/developerguide/
- Managed rule groups: https://docs.aws.amazon.com/waf/latest/developerguide/aws-managed-rule-groups-list.html
- Rate-based rule: https://docs.aws.amazon.com/waf/latest/developerguide/waf-rule-statement-type-rate-based.html
- Terraform `aws_wafv2_web_acl`: https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/wafv2_web_acl

## 함정

- **scope 2개** — CloudFront 는 반드시 `--scope CLOUDFRONT --region us-east-1`. ALB/APIGW 는 REGIONAL.
- **managed=OverrideAction, custom=Action** — 스키마가 다르다. managed rule 에 Action 쓰면 에러.
- **로그 그룹 `aws-waf-logs-` 접두어 강제**.
- **채점 시 기존 차단 기록** — 2026 가이드가 "채점 전 기존 기록 클리어" 를 명시. rate limit 는 시간창이라 이전 트래픽이 남으면 불이익. WebACL 재생성 또는 창 만료 대기.
- **연결 전엔 아무 효과 없음** — WebACL 만 만들고 associate 안 하면 트래픽을 안 본다.
- CloudFront 연결은 associate-web-acl 이 아니라 **distribution 의 WebACLId** 필드.

## 정리
```bash
aws wafv2 delete-web-acl --region $R --name lab-waf --scope REGIONAL --id $ACL \
  --lock-token "$(aws wafv2 get-web-acl --region $R --name lab-waf --scope REGIONAL --id $ACL --query LockToken --output text)"
```
