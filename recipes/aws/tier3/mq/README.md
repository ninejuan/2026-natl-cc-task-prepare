# Amazon MQ

**트리거 문구** — "메시지 브로커", "RabbitMQ", "ActiveMQ", "AMQP/MQTT/STOMP", "기존 메시징 프로토콜".

**전제**
```bash
export R=ap-northeast-2
```

SQS/SNS 로 되는 걸 굳이 MQ 로 풀 필요는 없다. **표준 프로토콜(AMQP/MQTT/STOMP/JMS)이나 RabbitMQ/ActiveMQ 호환**이 요구될 때만. 대부분의 큐 문제는 `../../serverless/sqs-sns.md`.

---

## 케이스 A — RabbitMQ 브로커 [검증됨: RUNNING]

```bash
BROKER=$(aws mq create-broker --region $R \
  --broker-name lab-mq --engine-type RABBITMQ --engine-version 3.13 \
  --host-instance-type mq.m7g.large --deployment-mode SINGLE_INSTANCE \
  --publicly-accessible \
  --users "Username=admin,Password=SkillsRabbit2026!" \
  --auto-minor-version-upgrade \
  --query BrokerId --output text)

# RUNNING 대기 (실측 ~5분)
aws mq describe-broker --region $R --broker-id $BROKER --query BrokerState --output text
# 엔드포인트 + 관리 콘솔
aws mq describe-broker --region $R --broker-id $BROKER \
  --query '[BrokerInstances[0].Endpoints,BrokerInstances[0].ConsoleURL]' --output text
# amqps://b-xxxx.mq.ap-northeast-2.on.aws:5671  (AMQP over TLS)
```
> ⚠️ **RabbitMQ 는 t3.micro 미지원.** 최소 `mq.m5.large`/`mq.m7g.large`(검증 확인). ActiveMQ 는 mq.t3.micro 됨. 비용 크니 검증 후 즉시 삭제.

- **deployment**: SINGLE_INSTANCE(개발) / CLUSTER_MULTI_AZ(RabbitMQ HA) / ACTIVE_STANDBY(ActiveMQ HA).
- **publiclyAccessible**: 검증 편의. 실전은 VPC 내부 + SG 로 5671 제한.

## 케이스 B — publish / consume (pika) [검증됨: AMQPS 5671 로 5건 발행→5건 소비, 큐 depth 0]

`producer.py`·`consumer.py` (pika, amqps TLS 5671).

```bash
pip3 install pika
export MQ_URL='amqps://admin:SkillsRabbit2026!@b-xxxx.mq.ap-northeast-2.on.aws:5671'
python3 producer.py    # orders 큐에 10건
python3 consumer.py    # ack 하며 소비
```
- **amqps://**(TLS) 5671. 평문 5672 아님(MQ 는 TLS 강제).
- 큐 `durable=True` + 메시지 `delivery_mode=2`(persistent) → 브로커 재시작에도 유지.

## 케이스 C — ActiveMQ (JMS/STOMP/MQTT)

```bash
aws mq create-broker --region $R --broker-name lab-amq \
  --engine-type ACTIVEMQ --engine-version 5.18 \
  --host-instance-type mq.t3.micro --deployment-mode SINGLE_INSTANCE \
  --publicly-accessible --users "Username=admin,Password=SkillsActiveMQ26!"
```
ActiveMQ 는 t3.micro 됨. 웹 콘솔(ActiveMQ Console) + OpenWire/STOMP/MQTT/AMQP 멀티 프로토콜.

## 검증

```bash
aws mq list-brokers --region $R --query 'BrokerSummaries[].[BrokerName,BrokerState,EngineType]' --output text
aws mq describe-broker --region $R --broker-id $BROKER \
  --query '[BrokerState,EngineType,HostInstanceType]' --output text   # RUNNING
# 관리 콘솔 URL 접속(RabbitMQ Management / ActiveMQ Console) 로 큐 확인
# producer/consumer 왕복
```

## Terraform

```hcl
resource "aws_mq_broker" "b" {
  broker_name        = "lab-mq"
  engine_type        = "RabbitMQ"
  engine_version     = "3.13"
  host_instance_type = "mq.m7g.large"   # RabbitMQ 최소. ActiveMQ 는 mq.t3.micro
  deployment_mode    = "SINGLE_INSTANCE"
  publicly_accessible = true            # 실전 VPC 내부면 false + subnet_ids + SG
  user {
    username = "admin"
    password = "SkillsRabbit2026!"      # 12자+, 공백/쉼표 불가
  }
}
```
> 생성 ~5분(RabbitMQ), 비용 큼. apply 후 즉시 검증하고 destroy.

## Console 팁

- **브로커 생성 마법사**: 엔진(RabbitMQ/ActiveMQ)·인스턴스·배포모드·인증·네트워크를 단계 폼으로.
- **RabbitMQ Management / ActiveMQ Console**: 브로커 콘솔 링크로 웹 관리 UI(큐·연결·메시지 조회).
- **CloudWatch 통합**: 큐 깊이·연결 수 메트릭.

## 참고 문서

- Amazon MQ 개발자 가이드: https://docs.aws.amazon.com/amazon-mq/latest/developer-guide/
- RabbitMQ: https://docs.aws.amazon.com/amazon-mq/latest/developer-guide/rabbitmq.html
- Terraform `aws_mq_broker`: https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/mq_broker

## 함정

- **RabbitMQ 최소 m5.large/m7g.large** — t3.micro 는 BadRequest. ActiveMQ 만 t3.micro.
- **TLS 강제(amqps 5671)** — 평문 안 됨. pika URLParameters 가 amqps 면 자동 TLS.
- **생성 ~5분, 비용 큼** — 검증 후 즉시 delete-broker.
- **publiclyAccessible** 는 생성 시에만 결정. 실전 VPC 내부면 false + SG.
- **user password 규칙** — 12자 이상, 공백/쉼표 불가.
- SQS 로 충분하면 MQ 안 쓴다 — 관리 부담·비용이 크다.

## 정리
```bash
aws mq delete-broker --region $R --broker-id $BROKER
```
