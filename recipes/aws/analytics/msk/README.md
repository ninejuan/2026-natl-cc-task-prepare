# Amazon MSK (Managed Kafka)

**트리거 문구** — "이벤트 스트리밍 파이프라인", "MSK 토픽으로 메시지 발행", "Producer/Consumer", "Kafka".

**전제**
```bash
export R=ap-northeast-2 ACCT=$(aws sts get-caller-identity --query Account --output text)
```
> ⚠️ ARN 조립은 `${R}:${ACCT}:...`. (zsh 함정)

**MSK 는 VPC 내부 서비스다.** 부트스트랩 브로커가 private 이라 **클라이언트(producer/consumer)도 같은 VPC 안 EC2** 에서 돌려야 한다. CloudShell(VPC 밖)로는 topic 조작·produce 가 안 된다.

`producer.py`·`consumer.py`·`admin.py`(토픽 CRUD) 가 IAM 인증 클라이언트(kafka-python-ng 2.2+ 내장 AWS_MSK_IAM + botocore).

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

## Producer / Consumer / Admin (VPC 내 EC2) [검증됨: admin→produce→consume 왕복]

```bash
# EC2 에서 (SSM Session Manager 로 접속)
sudo dnf install -y python3-pip
pip3 install kafka-python-ng botocore    # ★ botocore 가 IAM 인증에 필수 (서명 라이브러리는 불필요)
export BOOTSTRAP="boot-xxxx...:9098" TOPIC=orders
export AWS_REGION=ap-northeast-2 AWS_DEFAULT_REGION=ap-northeast-2   # ★ 둘 다 (아래 함정)
python3 admin.py create orders 6   # 토픽 6파티션
python3 producer.py                # 10건 발행
python3 consumer.py                # earliest 부터 10건 소비
```
EC2 instance profile 에 MSK IAM 권한 필요:
```json
{"Effect":"Allow","Action":["kafka-cluster:Connect","kafka-cluster:*Topic*","kafka-cluster:WriteData","kafka-cluster:ReadData","kafka-cluster:AlterGroup","kafka-cluster:DescribeGroup"],"Resource":"*"}
```
Serverless 는 **토픽 자동 생성 활성**이 기본이라 producer 가 첫 발행 시 토픽을 만든다. 파티션 수를 지정하려면 `admin.py create`.

> ### ★ IAM 인증 함정 2가지 (실검증 중 발견)
> 1. **`kafka-python-ng 2.2+` 는 `sasl_mechanism="AWS_MSK_IAM"` 을 내장**(`kafka/sasl/msk.py`). 예전 블로그의 `aws-msk-iam-sasl-signer` + `AbstractTokenProvider`/`sasl_oauth_token_provider` 방식은 이 버전에서 **import 부터 실패**(`No module named 'kafka.sasl.oauth'`). botocore 만 있으면 된다.
> 2. **botocore 가 리전을 못 찾으면 `NoBrokersAvailable`** 로 죽는다(TCP 는 되는데 IAM 서명이 리전 없이 안 됨). instance profile 이 있어도 `region: None` 이면 실패 — `AWS_DEFAULT_REGION` 을 명시하라. `AWS_REGION` 만으론 botocore 가 못 읽는 경우가 있다.

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

## Terraform

```hcl
resource "aws_msk_serverless_cluster" "c" {
  cluster_name = "lab-msk"
  vpc_config {
    subnet_ids         = [var.subnet_a, var.subnet_b]
    security_group_ids = [var.sg]
  }
  client_authentication {
    sasl { iam { enabled = true } }
  }
}
# provisioned 는 aws_msk_cluster (broker 수/타입/EBS 지정)
```
Serverless 는 `aws_msk_serverless_cluster`, provisioned 는 `aws_msk_cluster`. 생성 ~15분(Serverless)이라 apply 대기 김.

## Console 팁

- **클러스터 생성 마법사**: Serverless/Provisioned 선택, VPC·서브넷·인증(IAM/SASL/TLS)을 폼으로. 부트스트랩·SG self-inbound 안내가 나와 실수 감소.
- **클라이언트 정보 보기**: 클러스터 콘솔의 "View client information" 이 부트스트랩 문자열(포트별)을 전부 보여준다.
- **MSK Connect**: 커넥터(S3 sink 등)를 콘솔 폼으로. Kafka Connect 를 직접 운영 안 함.
- 토픽·소비는 **VPC 내 EC2 필수**(콘솔로 토픽 조작 불가) — README 상단 admin.py.

## 참고 문서

- MSK 개발자 가이드: https://docs.aws.amazon.com/msk/latest/developerguide/
- IAM 액세스 제어: https://docs.aws.amazon.com/msk/latest/developerguide/iam-access-control.html
- Serverless: https://docs.aws.amazon.com/msk/latest/developerguide/serverless.html
- Terraform `aws_msk_serverless_cluster`: https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/msk_serverless_cluster

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
