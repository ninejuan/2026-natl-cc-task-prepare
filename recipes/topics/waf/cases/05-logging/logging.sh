#!/usr/bin/env bash
# 케이스 05 — WAF 로깅. REGIONAL WebACL(12 rule) + IP set + CloudWatch 로그 그룹 연결.
# 실검증됨(ap-northeast-2).
#  · rule-statements.json 의 12종을 그대로 create-web-acl 에 투입(_desc 제거, ByteMatch base64).
#  · rule 7(ipset)용 IP set 을 먼저 만들어 ARN 주입.
#  · rule 5(custom 403)가 참조하는 CustomResponseBodies["blocked"] 를 ACL 레벨에 정의.
#  · 로그 그룹은 반드시 aws-waf-logs- 접두어 → put-logging-configuration → get-logging-configuration.
set -euo pipefail
export R=${R:-ap-northeast-2}
ACCT=$(aws sts get-caller-identity --query Account --output text)
HERE=$(cd "$(dirname "$0")" && pwd)
SRC="$HERE/../../../../aws/tier2/waf/rule-statements.json"
LG=aws-waf-logs-lab-apne2

# 1. IP set (rule 7 이 참조). REGIONAL.
IPSET_ARN=$(aws wafv2 create-ip-set --region $R --name lab-apne2-block --scope REGIONAL \
  --ip-address-version IPV4 --addresses 192.0.2.0/24 203.0.113.0/24 \
  --query 'Summary.ARN' --output text)
echo "IPSet ARN=$IPSET_ARN"

# 2. rule-statements.json → API 용 rules 배열 (_desc 제거, ByteMatch SearchString base64, ipset ARN 주입).
RULES=$(IPSET_ARN="$IPSET_ARN" python3 - "$SRC" <<'PY'
import json, sys, base64
data = json.load(open(sys.argv[1]))
import os
ipset_arn = os.environ["IPSET_ARN"]

def fix(node):
    if isinstance(node, dict):
        for k, v in list(node.items()):
            if k == "ByteMatchStatement" and isinstance(v, dict) and "SearchString" in v:
                v["SearchString"] = base64.b64encode(v["SearchString"].encode()).decode()
            if k == "IPSetReferenceStatement" and isinstance(v, dict):
                v["ARN"] = ipset_arn
            fix(v)
    elif isinstance(node, list):
        for x in node:
            fix(x)

rules = []
for key, rule in data.items():
    if key.startswith("_"):
        continue
    rule = {k: v for k, v in rule.items() if not k.startswith("_")}
    fix(rule)
    rules.append(rule)
rules.sort(key=lambda r: r["Priority"])
print(json.dumps(rules))
PY
)

# 3. WebACL 생성. rule 5 의 CustomResponseBodyKey="blocked" → CustomResponseBodies 정의 필수.
ACL_ID=$(aws wafv2 create-web-acl --region $R --name lab-apne2-waf --scope REGIONAL \
  --default-action '{"Allow":{}}' \
  --visibility-config 'SampledRequestsEnabled=true,CloudWatchMetricsEnabled=true,MetricName=lab-apne2-waf' \
  --custom-response-bodies '{"blocked":{"ContentType":"TEXT_PLAIN","Content":"blocked by WAF"}}' \
  --rules "$RULES" \
  --query 'Summary.Id' --output text)
echo "WebACL Id=$ACL_ID"

# 4. 검증: 12개 rule + priority.
echo "rule 수 / priority:"
aws wafv2 get-web-acl --region $R --scope REGIONAL --name lab-apne2-waf --id "$ACL_ID" \
  --query '{count: length(WebACL.Rules), priorities: WebACL.Rules[].Priority, names: WebACL.Rules[].Name}' --output json
ACL_ARN=$(aws wafv2 get-web-acl --region $R --scope REGIONAL --name lab-apne2-waf --id "$ACL_ID" \
  --query 'WebACL.ARN' --output text)

# 5. 로깅: CloudWatch 로그 그룹(aws-waf-logs- 접두어) → put-logging-configuration.
aws logs create-log-group --region $R --log-group-name "$LG" 2>/dev/null || true
# 로그 그룹 ARN(뒤 ':*' 제거 — WAF LogDestinationConfigs 는 접미사 없는 ARN).
LG_ARN=$(aws logs describe-log-groups --region $R --log-group-name-prefix "$LG" \
  --query 'logGroups[0].arn' --output text | sed 's/:\*$//')
echo "LogGroup ARN=$LG_ARN"

aws wafv2 put-logging-configuration --region $R --logging-configuration \
  "ResourceArn=$ACL_ARN,LogDestinationConfigs=$LG_ARN" >/dev/null

echo "get-logging-configuration:"
aws wafv2 get-logging-configuration --region $R --resource-arn "$ACL_ARN" \
  --query 'LoggingConfiguration.{resource:ResourceArn,dest:LogDestinationConfigs}' --output json

# ── teardown (역순: 로깅 → WebACL(lock-token) → IP set(lock-token) → 로그 그룹) ──
aws wafv2 delete-logging-configuration --region $R --resource-arn "$ACL_ARN"
LT=$(aws wafv2 get-web-acl --region $R --scope REGIONAL --name lab-apne2-waf --id "$ACL_ID" --query LockToken --output text)
aws wafv2 delete-web-acl --region $R --scope REGIONAL --name lab-apne2-waf --id "$ACL_ID" --lock-token "$LT"
IPSET_ID=$(aws wafv2 list-ip-sets --region $R --scope REGIONAL --query "IPSets[?Name=='lab-apne2-block'].Id" --output text)
ILT=$(aws wafv2 get-ip-set --region $R --scope REGIONAL --name lab-apne2-block --id "$IPSET_ID" --query LockToken --output text)
aws wafv2 delete-ip-set --region $R --scope REGIONAL --name lab-apne2-block --id "$IPSET_ID" --lock-token "$ILT"
aws logs delete-log-group --region $R --log-group-name "$LG"
echo "teardown done"
