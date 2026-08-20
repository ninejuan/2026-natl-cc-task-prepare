"""
Kinesis Data Streams 소비자. base64 디코딩 + 집계 후 DynamoDB/S3 저장.
실시간 분석 파이프라인의 소비 단계. ESM 으로 연결(--starting-position LATEST).

IAM: kinesis:GetRecords/GetShardIterator/DescribeStream/ListShards, (대상 권한)
"""
import base64
import json
import os
from collections import Counter

import boto3

_ddb = boto3.resource("dynamodb")
_table = _ddb.Table(os.environ["TABLE_NAME"]) if os.environ.get("TABLE_NAME") else None


def handler(event, context):
    counts = Counter()
    n = 0
    for record in event.get("Records", []):
        payload = base64.b64decode(record["kinesis"]["data"]).decode("utf-8")
        try:
            data = json.loads(payload)
            # 예: event_type 별 집계
            counts[data.get("event_type", "unknown")] += 1
        except json.JSONDecodeError:
            counts["parse_error"] += 1
        n += 1

    # 집계 결과를 DynamoDB 에 upsert
    if _table:
        for etype, c in counts.items():
            _table.update_item(
                Key={"pk": f"agg-{etype}"},
                UpdateExpression="ADD #c :c",
                ExpressionAttributeNames={"#c": "count"},
                ExpressionAttributeValues={":c": c},
            )
    print(json.dumps({"processed": n, "counts": dict(counts)}))
    return {"processed": n, "counts": dict(counts)}
