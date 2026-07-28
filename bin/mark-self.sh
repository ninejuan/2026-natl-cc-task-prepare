#!/usr/bin/env bash
# 자가채점. 카드의 "## 검증" 블록을 그대로 실행한다.
#
#   ./mark-self.sh recipes/aws/s3.md ...   지정 카드의 검증 블록 실행
#   ./mark-self.sh                         recipes/ 전체
#   ./mark-self.sh --foul                  금지 조항 위반 여부만 검사
#   ./mark-self.sh --dry recipes/...       실행 대신 명령만 출력
set -uo pipefail
export AWS_PAGER=""
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

foul() {
  echo "== 금지 조항 위반 검사 (region=${R:-ap-northeast-2})"
  local r="${R:-ap-northeast-2}"
  chk() { printf '%-34s %s\n' "$1" "$2"; }

  chk "Lambda 함수"        "$(aws --region "$r" lambda list-functions --query 'length(Functions)' --output text 2>/dev/null)"
  chk "EC2 인스턴스(running)" "$(aws --region "$r" ec2 describe-instances --filters Name=instance-state-name,Values=running --query 'length(Reservations[].Instances[])' --output text 2>/dev/null)"
  chk "ECS 클러스터"        "$(aws --region "$r" ecs list-clusters --query 'length(clusterArns)' --output text 2>/dev/null)"
  chk "Private Hosted Zone" "$(aws route53 list-hosted-zones --query 'length(HostedZones[?Config.PrivateZone==`true`])' --output text 2>/dev/null)"
  chk "VPC Peering"        "$(aws --region "$r" ec2 describe-vpc-peering-connections --query 'length(VpcPeeringConnections[?Status.Code==`active`])' --output text 2>/dev/null)"
  chk "Transit Gateway"    "$(aws --region "$r" ec2 describe-transit-gateways --query 'length(TransitGateways[?State==`available`])' --output text 2>/dev/null)"

  # 과제지 조항은 Action / Principal 의 "*" 를 금지한다. Resource:"*" 는 ec2:Describe* 처럼 불가피한 경우가 많아 보지 않는다.
  echo
  echo "-- Action 또는 Principal 이 \"*\" 인 고객 관리형 IAM 정책"
  aws iam list-policies --scope Local --query 'Policies[].[Arn,DefaultVersionId]' --output text 2>/dev/null |
  xargs -P 8 -n 2 bash -c '
    aws iam get-policy-version --policy-arn "$0" --version-id "$1" --query PolicyVersion.Document --output json 2>/dev/null |
      grep -qE "\"(Action|Principal)\"[[:space:]]*:[[:space:]]*\"\*\"" && echo "  WARN $0"
  ' || true

  echo
  echo "-- /etc/hosts 수동 항목"
  grep -vE '^\s*(#|$)|localhost|::1|127\.0\.0\.1' /etc/hosts 2>/dev/null || echo "  (없음)"

  echo
  echo "숫자는 '있음/없음' 판단용이다. 과제지가 금지한 항목이 0이 아니면 그 항목은 통째로 0점이 된다."
}

# 카드에서 "## 검증" 아래 ```bash 블록만 뽑는다
extract() {
  awk '
    /^## /     { insec = ($0 ~ /^## +검증/) }
    insec && /^```/ { fence = !fence; next }
    insec && fence  { print }
  ' "$1"
}

DRY=0
case "${1:-}" in
  --foul) foul; exit 0 ;;
  --dry)  DRY=1; shift ;;
esac

CARDS=("$@")
if [ $# -eq 0 ]; then
  while IFS= read -r line; do CARDS+=("$line"); done < <(find "$ROOT/recipes" -name '*.md' | sort)
fi
if [ ${#CARDS[@]} -eq 0 ]; then echo "실행할 카드가 없다"; exit 0; fi

for card in "${CARDS[@]}"; do
  body=$(extract "$card")
  [ -z "$body" ] && continue
  echo
  echo "===== ${card#$ROOT/}"
  if [ "$DRY" = 1 ]; then echo "$body"; else bash -c "$body"; fi
done
