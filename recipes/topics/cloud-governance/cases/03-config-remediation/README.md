# Config rule + SSM remediation
실검증됨(recorder recording + rule ACTIVE, 검증 후 원상복구). Config 는 평가 지연(수 분)이라 채점 3분 제약엔 EventBridge+Lambda(01)가 유리.
```bash
# recorder + delivery channel(S3+role) 선행 → managed rule
aws configservice put-config-rule --config-rule '{"ConfigRuleName":"restricted-ssh","Source":{"Owner":"AWS","SourceIdentifier":"INCOMING_SSH_DISABLED"}}'
# remediation: SSM Automation 문서
aws configservice put-remediation-configurations --remediation-configurations '[{"ConfigRuleName":"restricted-ssh","TargetType":"SSM_DOCUMENT","TargetId":"AWS-DisablePublicAccessForSecurityGroup","Automatic":true,"Parameters":{...}}]'
```
★ recorder 는 계정당 1개 — 없으면 role+버킷 셋업(무겁다). 검증 후 recorder 삭제로 원상복구. 기반: ../../../../aws/tier3/config-ssm.md.
