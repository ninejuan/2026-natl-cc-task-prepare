# 부분 배치 실패 (ReportBatchItemFailures) — live 검증

`handler.py` + `verify.sh`(eu-west-1). SQS→Lambda ESM 에서 **배치 중 일부만 실패**했을 때 성공분이 중복 처리되지 않게 하는 표준 패턴.

```bash
aws lambda create-event-source-mapping --function-name lab-mq --event-source-arn $QARN \
  --batch-size 10 --maximum-batching-window-in-seconds 5 \
  --function-response-types ReportBatchItemFailures      # ★ 이 플래그가 핵심
```
핸들러는 실패한 `messageId` 만 `{"batchItemFailures":[{"itemIdentifier": ...}]}` 로 돌려준다.

## 실측 결과 (`bash verify.sh`)

3건(`ok-1` / `fail-me` / `ok-3`)을 한 배치로 보내고 `fail-me` 만 실패시켰다. maxReceiveCount=2, visibility 30s.

| 관찰 | 값 |
|---|---|
| DLQ 내용 | `{"id":"fail-me"}` **1건만** |
| DLQ 개수 | `ApproximateNumberOfMessagesNotVisible: 1` |
| 소스 큐 잔량 | 0 (성공 2건은 자동 삭제) |
| `ok-1` 처리 로그 | **1회** |
| `ok-3` 처리 로그 | **1회** |
| `fail-me` 처리 로그 | **2회** (동일 messageId `ed962be5…` 재수신 → maxReceiveCount 초과 → DLQ) |

→ **성공분은 재처리되지 않았다**. 이 플래그가 없으면 배치 전체가 재전달되어 `ok-1`/`ok-3` 도 2회 처리된다(중복 처리 감점 포인트).

## 함정 (실측)

- **`--function-response-types ReportBatchItemFailures` 를 빼면** 핸들러가 `batchItemFailures` 를 돌려줘도 무시된다 → 배치 전체 재처리.
- 핸들러가 **예외를 던지면** 부분 실패 보고 자체가 안 된다. 반드시 try/except 로 잡고 목록으로 반환.
- `aws sqs send-message-batch --entries Id=m1,MessageBody={"id":"x"}` **shorthand 는 JSON body 를 못 넣는다**(중괄호/쉼표 파싱 실패) → `--entries file://entries.json`.
- SQS 큐는 **삭제 후 60초** 안에 같은 이름으로 못 만든다(`QueueDeletedRecently`) — 재실행 시 이름 바꾸거나 대기.
- 실패 메시지는 visibility(30s) 만큼 기다렸다 재수신 → DLQ 이동까지 최소 `visibility × maxReceiveCount` 필요(실측 90초 대기).
