#!/usr/bin/env bash
# 케이스 04 — firewall policy(stateless+stateful reference) + 로깅.
# rule group(케이스 01~03)이 먼저 있어야 한다.
set -euo pipefail
export R=${R:-ap-northeast-2} ACCT=$(aws sts get-caller-identity --query Account --output text)

SL=$(aws network-firewall describe-rule-group --region $R --rule-group-name lab-nfw-stateless --type STATELESS --query 'RuleGroupResponse.RuleGroupArn' --output text)
DENY=$(aws network-firewall describe-rule-group --region $R --rule-group-name lab-nfw-deny --type STATEFUL --query 'RuleGroupResponse.RuleGroupArn' --output text)

# policy: stateless 기본 forward, stateful 은 deny rule group 참조 (DEFAULT_ACTION_ORDER)
cat > /tmp/nfw-policy.json <<JSON
{
  "StatelessDefaultActions": ["aws:forward_to_sfe"],
  "StatelessFragmentDefaultActions": ["aws:forward_to_sfe"],
  "StatelessRuleGroupReferences": [{"Priority": 1, "ResourceArn": "$SL"}],
  "StatefulRuleGroupReferences": [{"ResourceArn": "$DENY"}]
}
JSON
aws network-firewall create-firewall-policy --region $R --firewall-policy-name lab-nfw-policy \
  --firewall-policy file:///tmp/nfw-policy.json \
  --query 'FirewallPolicyResponse.{name:FirewallPolicyName,arn:FirewallPolicyArn}' --output json

# 로깅 설정은 firewall 생성 후(케이스 05)에 put-logging-configuration 으로:
#   ALERT → CloudWatch, FLOW → S3
cat <<'NOTE'
로깅(firewall 생성 후):
  aws network-firewall put-logging-configuration --firewall-name lab-nfw \
    --logging-configuration '{"LogDestinationConfigs":[
      {"LogType":"ALERT","LogDestinationType":"CloudWatchLogs","LogDestination":{"logGroup":"/lab/nfw-alert"}},
      {"LogType":"FLOW","LogDestinationType":"S3","LogDestination":{"bucketName":"lab-nfw-flow-BUCKET"}}]}'
NOTE
