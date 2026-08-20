"""
DynamoDB Streams 소비자. 테이블 변경(INSERT/MODIFY/REMOVE)을 받아 후처리.
집계·감사로그·검색색인 동기화 전형. ESM starting-position LATEST.

IAM: dynamodb:GetRecords/GetShardIterator/DescribeStream/ListStreams, (대상 권한)
"""
import json
from decimal import Decimal


def _deser(image):
    """DynamoDB Stream 의 {'S':..,'N':..} 형식을 평범한 dict 로."""
    out = {}
    for k, v in (image or {}).items():
        t, val = next(iter(v.items()))
        if t == "N":
            out[k] = int(val) if "." not in val else float(val)
        elif t == "S":
            out[k] = val
        elif t == "BOOL":
            out[k] = val
        else:
            out[k] = val
    return out


def handler(event, context):
    stats = {"INSERT": 0, "MODIFY": 0, "REMOVE": 0}
    for record in event.get("Records", []):
        name = record["eventName"]  # INSERT / MODIFY / REMOVE
        stats[name] = stats.get(name, 0) + 1
        img = record["dynamodb"]
        new = _deser(img.get("NewImage"))
        old = _deser(img.get("OldImage"))
        print(json.dumps({"event": name, "new": new, "old": old}, default=str))
        # 여기서 집계/색인/알림 등 후처리
    return {"stats": stats}
