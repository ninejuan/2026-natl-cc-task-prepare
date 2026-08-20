#!/usr/bin/env bash
# 정책 + rule group 정리. ★ firewall(케이스 05)이 먼저 삭제돼 있어야 policy 삭제 가능,
#   policy 가 먼저 삭제돼야 rule group 삭제 가능(참조 의존성).
set -uo pipefail
export R=${R:-ap-northeast-2}
retry() { for i in $(seq 1 8); do "$@" 2>/dev/null && return 0; sleep 8; done; echo "  (여전히 참조 중일 수 있음: $*)"; }

retry aws network-firewall delete-firewall-policy --region $R --firewall-policy-name lab-nfw-policy
for rg in lab-nfw-deny lab-nfw-allow lab-nfw-suricata; do
  retry aws network-firewall delete-rule-group --region $R --rule-group-name $rg --type STATEFUL
done
retry aws network-firewall delete-rule-group --region $R --rule-group-name lab-nfw-stateless --type STATELESS
echo "policy/rule group teardown done"
