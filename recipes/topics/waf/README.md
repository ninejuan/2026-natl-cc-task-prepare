# WAF 플레이북 (2025 #13)

**가이드 원문(2025 #13)** — "AWS WAF 로 웹 공격 차단. **결함 있는 앱 코드 + 테스트 방법 + 공격 설명**을 모두 제시. ★ AWS WAF 아닌 Linux/3rd-party 솔루션 사용 금지."
- 필수: WAF / 선택: EC2, Lambda, ELB

**트리거 문구** — "WAF 로 차단", "SQLi/XSS 방어", "rate limit", "403 커스텀", "봇 차단".

**리전 격리** — 전용(단 CloudFront 붙이면 us-east-1). 예시 `ap-northeast-2`.

**기반 카드**: WAF rule statement 12종 `../../aws/tier2/waf/rule-statements.json`(create-web-acl 실검증), WAF 카드 `../../aws/tier2/waf.md`, Terraform `../../aws/tier2/terraform-waf/`.

---

## 케이스 인덱스 (기반 카드의 12종 rule statement 활용)

| # | 케이스 | rule | 기반 |
|---|---|---|---|
| 01 | managed(Common/SQLi/BadInputs) | managed rule group | `cases/01-managed/rules.json` ✓ |
| 02 | rate limit + custom 403 | RateBasedStatement + CustomResponse | `cases/02-ratelimit/rules.json` ✓ |
| 03 | IP set / geo 차단 | IPSet / GeoMatch | `cases/03-ipset-geo/rules.json` ✓ |
| 04 | 헤더/AND 조합/size | ByteMatch / And / Size | `cases/04-header-and-size/rules.json` ✓ (ByteMatch SearchString CLI 는 base64) |
| 05 | WAF 로깅 | put-logging-configuration | `cases/05-logging/` ✅ live (12 rule ACL + CW 로그그룹 연결 실측) |
| 06 | Bot Control | AWSManagedRulesBotControlRuleSet | ✅ live(create-web-acl 수락) |

## 검증 (채점자 문체 — 2026 task1 mark.sh 방식)

```bash
# ACL 식별 + rate limit 값
aws wafv2 list-web-acls --region $R --scope REGIONAL --query "WebACLs[?Name=='lab-waf'].Id" --output text
aws wafv2 get-web-acl --region $R --scope REGIONAL --name lab-waf --id $ACL \
  --query 'WebACL.Rules[?Statement.RateBasedStatement].Statement.RateBasedStatement.Limit' --output text
# 기능: rate limit 폭주 → 403, SQLi 시도 → 403
for i in $(seq 1 200); do curl -s -o /dev/null "https://$EP/"; done
curl -s -o /dev/null -w '%{http_code}\n' "https://$EP/"                       # 403
curl -s -o /dev/null -w '%{http_code}\n' "https://$EP/?q=1'%20OR%201=1--"    # 403
```

## 결함 앱 + 공격 설명 (가이드 요구)

WAF 모듈은 "결함 있는 앱 코드 + 공격 방법 + 테스트"를 **문제지가** 제공. 선수는 그 공격을 WAF 로 막는다.
- 예: SQLi 취약 엔드포인트 → Common/SQLi managed rule 로 차단.
- 예: 특정 경로 폭주 → rate limit rule.
- **AWS WAF 로만** — nginx deny, iptables, 앱 코드 수정으로 풀면 반칙(가이드 명시).

## 함정

- **CLI ByteMatch SearchString 은 base64**(실측) — 평문이면 "Invalid base64". 콘솔·TF 는 평문.
- **managed=OverrideAction, custom=Action** — 스키마 다름.
- **scope 2개** — CloudFront 는 us-east-1 CLOUDFRONT, ALB/APIGW 는 REGIONAL.
- **rate limit 시간창** — 채점 전 기존 트래픽 남으면 불이익(2026 가이드 "기록 클리어").
- **연결 안 하면 무효** — associate-web-acl(ALB) 또는 distribution WebACLId(CF).
- 로그 그룹은 `aws-waf-logs-` 접두어 강제.

## context7 참고

- `aws_wafv2_web_acl`·`_ip_set`·`_web_acl_logging_configuration` (TF AWS v6)
- Managed rule groups: https://docs.aws.amazon.com/waf/latest/developerguide/aws-managed-rule-groups-list.html
- Bot Control: https://docs.aws.amazon.com/waf/latest/developerguide/aws-managed-rule-groups-bot.html
