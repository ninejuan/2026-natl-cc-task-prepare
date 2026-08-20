#!/usr/bin/env bash
# 케이스 04 — 가중 라우팅(카나리/블루그린). 하나의 rule 이 여러 TG 에 weight 분배.
# 전제: 케이스 01 인프라 + TG_BLUE, TG_GREEN 두 개.
set -euo pipefail
export R=${R:-ap-northeast-2}
SVC=${SVC:?} LID=${LID:?} TG_BLUE=${TG_BLUE:?} TG_GREEN=${TG_GREEN:?}

# 90:10 카나리 — default action 을 가중으로 바꾸거나 별도 rule 로
aws vpc-lattice create-rule --region $R --service-identifier $SVC --listener-identifier $LID \
  --name canary --priority 50 \
  --match '{"httpMatch":{"pathMatch":{"match":{"prefix":"/"}}}}' \
  --action "{\"forward\":{\"targetGroups\":[
    {\"targetGroupIdentifier\":\"$TG_BLUE\",\"weight\":90},
    {\"targetGroupIdentifier\":\"$TG_GREEN\",\"weight\":10}]}}"

echo "가중 rule 생성됨:"
aws vpc-lattice get-rule --region $R --service-identifier $SVC --listener-identifier $LID \
  --rule-identifier "$(aws vpc-lattice list-rules --region $R --service-identifier $SVC --listener-identifier $LID --query "items[?name=='canary'].id" --output text)" \
  --query 'action.forward.targetGroups' --output json
# 검증: 반복 curl 시 ~90%는 blue, ~10%는 green 응답
