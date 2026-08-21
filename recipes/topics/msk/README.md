# MSK 플레이북 (2026 #13)

**가이드 원문(2026 #13)** — "Amazon MSK 이벤트 스트리밍 파이프라인. Producer 앱이 MSK 토픽에 발행, **Lambda 또는 EC2 Consumer** 가 처리해 DynamoDB/S3 저장. Producer/Consumer 코드는 출제자 제공."
- 필수: MSK, VPC / 선택: Lambda, EC2, S3, DynamoDB

**트리거 문구** — "MSK", "Kafka", "이벤트 스트리밍", "토픽 발행/소비", "Lambda ESM 으로 Kafka".

**리전 격리** — 전용. 예시 `ap-northeast-2`.

**기반 카드**: MSK 프로듀서·컨슈머·admin `../../aws/analytics/msk/`(IAM SASL, 실검증), DDB `../../aws/tier2/dynamodb.md`.

---

## 케이스 인덱스

| # | 케이스 | 구조 | 기반 | 상태 |
|---|---|---|---|---|
| 01 | Producer → MSK → Lambda ESM → DDB | Lambda event source mapping | `cases/01-lambda-esm/` | ✅ 실검증(eu-central-1): 클러스터 ACTIVE + ESM Enabled |
| 02 | Producer → MSK → EC2 consumer | kafka-python 컨슈머 | `cases/02-ec2-consumer/` | ✅ live(eu-west-1): 클러스터 ACTIVE→in-VPC EC2 에서 topic 생성+produce+consume 왕복(IAM OAUTHBEARER) |
| 03 | IAM SASL 인증 | OAUTHBEARER+signer | `cases/03-iam-sasl/` | ✅ 실검증(9098) |
| 04 | Serverless vs provisioned | 클러스터 타입 | `cases/04-serverless-vs-provisioned/` | 비교 |

> **실검증 01 (2026-08-20, eu-central-1)**: MSK Serverless `lab-euc1-msk` ACTIVE
> (ClusterType=SERVERLESS, IAM SASL 9098), Lambda ESM `topics=[lab-topic]` **State=Enabled**.
> 재현: `cases/01-lambda-esm/setup.sh` → `teardown.sh`. 실제 produce/consume 은 VPC 내 EC2 필요(아래).

## 인증·연결 (실검증 함정 반영)

- **★ MSK 는 VPC 에 DNS hostnames 활성 필수**(실측) — 안 켜면 create-cluster-v2 가 `BadRequestException: VPC ... doesn't have DNS hostnames enabled`. `aws ec2 modify-vpc-attribute --enable-dns-hostnames '{"Value":true}'` 선행.
- **MSK Serverless 는 IAM SASL 강제**(포트 9098).
- **★ IAM 인증은 `aws-msk-iam-sasl-signer-python` + `OAUTHBEARER`**(실검증 정정). `sasl_mechanism="AWS_MSK_IAM"`(kafka-python-ng 2.2.3 "내장")은 **실제로 metadata 갱신 60초 타임아웃으로 실패**했다(TCP 9098 열려 있어도 SASL 핸드셰이크 안 끝남). 되는 방법: signer 토큰을 `sasl_oauth_token_provider`(`.token()`)로 `OAUTHBEARER` 에 넘긴다. produce/consume/admin 왕복 검증 완료.
- **botocore region=None 이면 NoBrokersAvailable** — `AWS_DEFAULT_REGION` 환경변수 필수(실검증).
- SG self-inbound 9098 필요(브로커 간 + 클라이언트).

## Lambda ESM (MSK → Lambda)

```bash
aws lambda create-event-source-mapping --region $R \
  --function-name lab-consumer \
  --event-source-arn <msk-cluster-arn> \
  --topics lab-topic --starting-position LATEST \
  --amazon-managed-kafka-event-source-config '{"ConsumerGroupId":"lab-cg"}'
# Lambda role: kafka-cluster:Connect/DescribeCluster/ReadData + kafka:DescribeCluster
```

## 검증 (채점자 문체)

```bash
aws kafka list-clusters-v2 --region $R --query "ClusterInfoList[?ClusterName=='lab-msk'].{state:State,type:ClusterType}" --output json
# ESM 활성
aws lambda list-event-source-mappings --region $R --function-name lab-consumer --query 'EventSourceMappings[].State' --output text  # Enabled
# 기능: producer.py 발행 → DDB/S3 에 결과 적재 확인
aws dynamodb scan --region $R --table-name lab-events --select COUNT --query Count --output text
```

## 함정

- **MSK 생성 느림·비용 큼** — Serverless 도 시간과금. provisioned 는 ~15분+. 검증 후 즉시 삭제.
- **IAM SASL 9098** + SG self-inbound. 평문 9092 아님(Serverless).
- **IAM 인증은 signer+OAUTHBEARER**(위 참조, 내장 AWS_MSK_IAM 은 타임아웃). `AWS_DEFAULT_REGION` 필수.
- **Lambda ESM 은 VPC 접근** — Lambda 가 MSK 브로커 서브넷에 닿아야(VPC 연결 or Serverless).
- 토픽 사전 생성(admin.py) — ESM 이 없는 토픽 구독하면 대기.

## context7 참고

- `aws_msk_cluster`·`aws_msk_serverless_cluster`·`aws_lambda_event_source_mapping` (TF AWS v6)
- MSK IAM: https://docs.aws.amazon.com/msk/latest/developerguide/iam-access-control.html
- Lambda MSK ESM: https://docs.aws.amazon.com/lambda/latest/dg/with-msk.html
