# MSK Serverless vs Provisioned
| | Serverless | Provisioned |
|--|--|--|
| 인증 | IAM SASL 강제(9098) | IAM/SCRAM/TLS 선택 |
| 용량 | 자동 | 브로커 수·타입 지정 |
| replication_factor | 3 강제 | 설정 가능 |
| 생성시간 | ~15분 | ~15-25분 |
| 용도 | 가변 트래픽, 관리 최소 | 정상상태 고처리량, 세밀 튜닝 |
```bash
# Serverless (실검증)
aws kafka create-cluster-v2 --cluster-name c --serverless 'VpcConfigs=[{SubnetIds=[..],SecurityGroupIds=[..]}],ClientAuthentication={Sasl={Iam={Enabled=true}}}'
# Provisioned
aws kafka create-cluster --cluster-name c --kafka-version 3.6.0 --number-of-broker-nodes 3 --broker-node-group-info ...
```
★ 둘 다 VPC DNS hostnames 활성 필수(실측). 기반: ../../../../aws/analytics/msk/.
