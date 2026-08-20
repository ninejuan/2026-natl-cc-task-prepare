"""
SQS ESM 소비자. ReportBatchItemFailures 로 실패 메시지만 재시도(전체 배치 재처리 방지).
Message Queue 모듈, Spike 트래픽 처리 전형.

ESM 생성 시 --function-response-types ReportBatchItemFailures 필수.
IAM: sqs:ReceiveMessage/DeleteMessage/GetQueueAttributes, (처리 대상 권한)
"""
import json
import os
import boto3

_ddb = boto3.resource("dynamodb")
_table = _ddb.Table(os.environ["TABLE_NAME"]) if os.environ.get("TABLE_NAME") else None


def _process_one(record):
    """실제 처리. 예외를 던지면 그 메시지만 실패로 기록된다."""
    body = json.loads(record["body"])
    # 예: 주문 저장
    if _table:
        _table.put_item(Item={"pk": f"order-{body['order_id']}", "amount": str(body.get("amount", 0))})
    return body


def handler(event, context):
    failures = []
    for record in event.get("Records", []):
        try:
            _process_one(record)
        except Exception as e:  # 개별 메시지 실패 → 그 메시지만 재시도
            print(f"failed messageId={record['messageId']}: {e}")
            failures.append({"itemIdentifier": record["messageId"]})
    # 이 형식으로 반환해야 SQS 가 실패분만 큐에 되돌린다
    return {"batchItemFailures": failures}
