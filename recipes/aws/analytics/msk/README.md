# Amazon MSK (Managed Kafka)

**트리거 문구** — "이벤트 스트리밍 파이프라인", "MSK 토픽으로 메시지 발행", "Producer/Consumer", "Kafka".

**전제**
```bash
export R=ap-northeast-2 ACCT=$(aws sts get-caller-identity --query Account --output text)
```
> ⚠️ ARN 조립은 `${R}:${ACCT}:...`. (zsh 함정)

**MSK 는 VPC 내부 서비스다.** 부트스트랩 브로커가 private 이라 **클라이언트(producer/consumer)도 같은 VPC 안 EC2** 에서 돌려야 한다. CloudShell(VPC 밖)로는 topic 조작·produce 가 안 된다.

`producer.py`·`consumer.py`·`admin.py`(토픽 CRUD) 가 IAM 인증 클라이언트(kafka-python-ng + aws-msk-iam-sasl-signer).

---

## ★ Serverless 클러스터 [검증됨: ACTIVE 확인]

**Serverless 를 써라.** provisioned(브로커 수·타입 지정)는 생성 25~35분인데, Serverless 는 훨씬 빠르고(실측 ~15분 내 ACTIVE) 용량 관리가 없다. 가이드가 브로커 수를 강제하지 않으면 Serverless.

```bash
# VPC 서브넷 2개 + SG 필요 (기존 VPC 재사용 가능)
VPC=$(aws ec2 describe-vpcs --region $R --filters Name=tag:Name,Values=<vpc> --query 'Vpcs[0].VpcId' --output text)
SUBS=$(aws ec2 describe-subnets --region $R --filters Name=vpc-id,Values=$VPC "Name=tag:Name,Values=*private*" --query 'Subnets[].SubnetId' --output text)
SG=$(aws ec2 describe-security-groups --region $R --filters Name=vpc-id,Values=$VPC Name=group-name,Values=default --query 'SecurityGroups[0].GroupId' --output text)
S1=$(echo $SUBS | awk '{print $1}'); S2=$(echo $SUBS | awk '{print $2}')

cat > msk.json <<JSON
{
  "ClusterName": "lab-msk",
  "Serverless": {
    "VpcConfigs": [{"SubnetIds": ["$S1","$S2"], "SecurityGroupIds": ["$SG"]}],
    "ClientAuthentication": {"Sasl": {"Iam": {"Enabled": true}}}
  }
}
JSON
aws kafka create-cluster-v2 --region $R --cli-input-json file://msk.json

# ACTIVE 대기
CA=$(aws kafka list-clusters-v2 --region $R --query "ClusterInfoList[?ClusterName=='lab-msk'].ClusterArn" --output text)
aws kafka describe-cluster-v2 --region $R --cluster-arn "$CA" --query 'ClusterInfo.State' --output text  # ACTIVE
```

## 부트스트랩 + IAM 인증 [검증됨]

```bash
aws kafka get-bootstrap-brokers --region $R --cluster-arn "$CA" \
  --query 'BootstrapBrokerStringSaslIam' --output text
# boot-xxxx.c2.kafka-serverless.ap-northeast-2.amazonaws.com:9098  ← IAM SASL 포트 9098
```

- **포트 9098 = IAM SASL**. 9092(plaintext)·9094(TLS)·9096(SCRAM)와 구분.
- **SG self-inbound 9098 필요**: 클라이언트 EC2 와 MSK 가 같은 SG 를 쓰거나, MSK SG 가 클라이언트 SG 로부터 9098 을 허용해야 한다. **이걸 빠뜨리면 연결 타임아웃** — 가장 흔한 MSK 실패.

## Producer / Consumer (VPC 내 EC2)

```bash
# EC2 에서
sudo dnf install -y python3-pip java-11
pip install kafka-python-ng aws-msk-iam-sasl-signer-python
export BOOTSTRAP="boot-xxxx...:9098" TOPIC=lab-topic AWS_REGION=ap-northeast-2
python3 producer.py    # 10건 발행
python3 consumer.py    # earliest 부터 소비
```
EC2 instance profile 에 MSK IAM 권한 필요:
```json
{"Effect":"Allow","Action":["kafka-cluster:Connect","kafka-cluster:*Topic*","kafka-cluster:WriteData","kafka-cluster:ReadData","kafka-cluster:AlterGroup","kafka-cluster:DescribeGroup"],"Resource":"*"}
```
Serverless 는 **토픽 자동 생성 활성**이 기본이라 producer 가 첫 발행 시 토픽을 만든다. provisioned 는 `kafka-topics.sh --create` 로 미리.

## 소비 측: Lambda ESM / EC2 Consumer

- **Lambda ESM**: `../../serverless/lambda.md` ESM. `--event-source-arn <MSK ARN> --topics lab-topic`. Lambda 가 VPC 안에서 자동 소비.
- **EC2 Consumer**: `consumer.py` → DynamoDB/S3 저장.

## 검증

```bash
aws kafka describe-cluster-v2 --region $R --cluster-arn "$CA" \
  --query 'ClusterInfo.[ClusterName,State,ClusterType,Serverless.ClientAuthentication.Sasl.Iam.Enabled]' --output text
aws kafka get-bootstrap-brokers --region $R --cluster-arn "$CA" --query 'BootstrapBrokerStringSaslIam' --output text
# 실제 produce/consume 은 VPC 내 EC2 에서 producer.py/consumer.py 로.
```

## 함정

- **VPC 내부 전용** — CloudShell(VPC 밖) 로 topic·produce 불가. 클라이언트 EC2 를 VPC 안에.
- **SG self-inbound 9098** — 없으면 연결 타임아웃. MSK 실패의 대부분.
- **포트 9098 = IAM**. 다른 인증(SCRAM 9096, TLS 9094)과 헷갈리지 마라.
- **EC2 instance profile 에 kafka-cluster:* 권한** 필요.
- Serverless 는 **partition/처리량 자동**, provisioned 는 브로커·EBS 관리. 가이드가 브로커 수 지정 안 하면 Serverless.
- **삭제도 시간 걸린다**(DELETING). 다음 작업 전 확인.

## 정리
```bash
aws kafka delete-cluster --region $R --cluster-arn "$CA"
```
