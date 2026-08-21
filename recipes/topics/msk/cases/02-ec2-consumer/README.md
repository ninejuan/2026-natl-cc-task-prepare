# MSK EC2 Consumer 왕복 (live 검증됨)

MSK Serverless 부트스트랩은 private(9098, IAM SASL)이라 **VPC 내부 EC2**에서만 접속된다.
`roundtrip.py` 로 topic 생성 → produce → consume 왕복. 실검증(eu-west-1): `msk-ec2-roundtrip-final` 수신.

## 실행 (bastion/EC2 에서, SSM 또는 SSH)

```bash
sudo dnf install -y python3-pip
pip3 install kafka-python-ng aws-msk-iam-sasl-signer-python
export AWS_DEFAULT_REGION=ap-northeast-2 TOPIC=lab-topic
export BOOTSTRAP="$(aws kafka get-bootstrap-brokers --cluster-arn <arn> --query BootstrapBrokerStringSaslIam --output text)"
python3 roundtrip.py     # PRODUCED → CONSUMED: {"msg":"msk-ec2-roundtrip-final"}
```

## 전제 (실측 함정)

- EC2 instance profile 에 `kafka-cluster:*`(또는 Connect/DescribeCluster/ReadData/WriteData/CreateTopic).
- **VPC DNS hostnames 활성** — 안 하면 클러스터 생성부터 거부.
- SG self-inbound 9098.
- **IAM 인증 = signer + OAUTHBEARER** (내장 AWS_MSK_IAM 은 metadata 타임아웃, 실측). `../../../aws/analytics/msk/`.
- Serverless topic 은 **replication_factor=3** 강제.

Lambda ESM 경로(케이스 01)와 달리 EC2 컨슈머는 이 스크립트로 직접 소비 → S3/DDB 적재 로직을 붙인다.
