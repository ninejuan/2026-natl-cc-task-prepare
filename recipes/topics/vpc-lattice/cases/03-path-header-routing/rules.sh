#!/usr/bin/env bash
# 케이스 03 — 경로·헤더 기반 라우팅. 하나의 listener 에 여러 rule 을 priority 로.
# 전제: 케이스 01 로 service(SVC)+listener(LID)+두 개 이상의 target group(TG_A, TG_B) 존재.
# rule 문법(match http_match: path_match / header_matches / fixedResponse)은 실검증됨.
# ★ rule priority 는 1~2000 (초과 시 ValidationException).
set -euo pipefail
export R=${R:-ap-northeast-2}
SVC=${SVC:?service id 필요}
LID=${LID:?listener id 필요}
TG_A=${TG_A:?target group A}
TG_B=${TG_B:?target group B}

# rule 1 — /api/* 는 TG_A 로 (priority 낮을수록 먼저 평가)
aws vpc-lattice create-rule --region $R --service-identifier $SVC --listener-identifier $LID \
  --name api-path --priority 10 \
  --match '{"httpMatch":{"pathMatch":{"match":{"prefix":"/api"},"caseSensitive":true}}}' \
  --action "{\"forward\":{\"targetGroups\":[{\"targetGroupIdentifier\":\"$TG_A\"}]}}"

# rule 2 — 헤더 x-version: v2 면 TG_B 로
aws vpc-lattice create-rule --region $R --service-identifier $SVC --listener-identifier $LID \
  --name header-v2 --priority 20 \
  --match '{"httpMatch":{"headerMatches":[{"name":"x-version","caseSensitive":false,"match":{"exact":"v2"}}]}}' \
  --action "{\"forward\":{\"targetGroups\":[{\"targetGroupIdentifier\":\"$TG_B\"}]}}"

# rule 3 — /admin 은 고정 404 응답 (fixed-response)
# ★ Lattice fixedResponse 는 statusCode 404·500 만 지원(실측). 403/401/503 은 "not supported" 에러.
#   403 차단이 필요하면 auth policy(케이스 05)로 하거나 404 로 감춘다.
aws vpc-lattice create-rule --region $R --service-identifier $SVC --listener-identifier $LID \
  --name block-admin --priority 5 \
  --match '{"httpMatch":{"pathMatch":{"match":{"prefix":"/admin"}}}}' \
  --action '{"fixedResponse":{"statusCode":404}}'

echo "rules 생성됨. 검증:"
aws vpc-lattice list-rules --region $R --service-identifier $SVC --listener-identifier $LID \
  --query 'items[].{name:name,priority:priority,default:isDefault}' --output table
# 검증 curl(associate 된 VPC 내 EC2에서):
#   curl http://<dns>/api/x     → TG_A
#   curl -H 'x-version: v2' http://<dns>/  → TG_B
#   curl -o /dev/null -w '%{http_code}' http://<dns>/admin  → 403
