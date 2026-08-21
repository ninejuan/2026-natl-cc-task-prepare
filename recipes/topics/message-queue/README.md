# Message Queue 플레이북 (2025 #10)

**가이드 원문(2025 #10)** — "Message Queue 솔루션 구성. Spike 트래픽 분산 처리 등. 사례를 가정하는 메시지 생성 앱을 Python 으로 만들어 배포파일로 제공."
- 필수: SQS, Lambda / 선택: EC2, EventBridge, CloudWatch

**트리거 문구** — "메시지 큐", "Spike 트래픽 완충", "비동기 처리", "순서 보장", "중복 제거", "실패 메시지 격리(DLQ)".

**리전 격리** — 전용. 예시 `ap-northeast-2`.

**기반 카드**: 큐 기본·DLQ·fan-out 은 `../../aws/serverless/sqs-sns.md`(실검증됨), Lambda ESM 은 `../../aws/serverless/lambda/sqs-batch/handler.py`. 이 플레이북은 그 위에 **순서·중복·부분실패·Pipes** 를 얹는다.

---

## 케이스 인덱스

| # | 케이스 | 핵심 | 검증 |
|---|---|---|---|
| 01 | `cases/01-fifo/` | FIFO 순서 보장 + 콘텐츠 중복제거 | ✅ live |
| 02 | `cases/02-dlq-redrive/` | DLQ + redrive(재처리) | ✅ live (maxReceiveCount=2 초과→DLQ 이동 실측) |
| 03 | `cases/03-partial-batch/` | ReportBatchItemFailures(부분 실패) | ✅ 핸들러 unit test(m2만 재처리) |
| 04 | `cases/04-fanout/` | SNS→여러 SQS 팬아웃 | ✅ live(2큐 각 1건 수신) |
| 05 | `cases/05-pipes/` | EventBridge Pipes(SQS→타깃) | ✅ live(pipe RUNNING) |

## Spike 완충 패턴 (가이드의 "Spike 트래픽 분산")

```
Producer(Python, 배포파일) ──폭주──> SQS 큐 (버퍼)
                                        │ Lambda ESM (batch_size, max_concurrency)
                                        └─> 소비자(느리게 안정 처리)
```
- 큐가 스파이크를 흡수, Lambda 는 `BatchSize`·`MaximumConcurrency`(Scaling)로 소비 속도 제어.
- **가시성 타임아웃 = 처리시간 ×2** 이상. 짧으면 중복 처리, 길면 실패 재시도 지연.

## 검증 (채점자 문체)

```bash
# 큐 존재 + 속성
aws sqs get-queue-attributes --region $R --queue-url $Q \
  --attribute-names All --query 'Attributes.{type:FifoQueue,dlq:RedrivePolicy,vis:VisibilityTimeout}' --output json
# Producer 로 N건 발행 → 소비 관찰 (채점이 실제로 메시지 넣고 처리 확인)
aws sqs send-message-batch ...   # 또는 제공된 producer.py
aws sqs get-queue-attributes --region $R --queue-url $Q --attribute-names ApproximateNumberOfMessages
# DLQ 로 이동했는지
aws sqs get-queue-attributes --region $R --queue-url $DLQ --attribute-names ApproximateNumberOfMessages
```

## 함정

- **FIFO 는 이름이 `.fifo` 로 끝나야** — 아니면 생성 거부. `FifoQueue=true`.
- **FIFO 순서는 MessageGroupId 단위** — 같은 그룹 내에서만 순서 보장. 그룹 다르면 병렬.
- **중복제거**: `ContentBasedDeduplication=true`(본문 해시) 또는 `MessageDeduplicationId` 명시. 5분 dedup 윈도우.
- **DLQ 는 같은 타입**(standard↔standard, FIFO↔FIFO). maxReceiveCount 초과 시 이동.
- **부분 배치 실패**: ESM 에 `ReportBatchItemFailures` + 핸들러가 `batchItemFailures` 반환 안 하면 **배치 전체 재처리**(성공분도 중복). 케이스 03 필수.
- **가시성 타임아웃** 짧으면 처리 중 메시지가 재노출 → 중복.
- ARN 조립 금지(zsh) — `get-queue-attributes QueueArn` 로.

## context7 참고

- `aws_sqs_queue`(fifo_queue, content_based_deduplication, redrive_policy) / `aws_lambda_event_source_mapping`(function_response_types) (TF AWS v6)
- SQS 개발자 가이드: https://docs.aws.amazon.com/AWSSimpleQueueService/latest/SQSDeveloperGuide/
- 부분 배치 응답: https://docs.aws.amazon.com/lambda/latest/dg/services-sqs-errorhandling.html
