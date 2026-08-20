"""
DynamoDB 조회 전용 API (2026 task1 Lambda 항목: '저장한 데이터를 조회하는 GET 호출').
optional 필터(email, concert_name)를 받아 FilterExpression 으로 좁힌다.
GSI 쿼리 우선, 없으면 scan+filter.

환경변수: TABLE_NAME, GSI_NAME
IAM: dynamodb:Query, dynamodb:GetItem, dynamodb:Scan
"""
import json
import os
import boto3
from boto3.dynamodb.conditions import Key, Attr

_ddb = boto3.resource("dynamodb")
_table = _ddb.Table(os.environ["TABLE_NAME"])
_GSI = os.environ.get("GSI_NAME")


def _resp(s, b):
    return {"statusCode": s, "headers": {"Content-Type": "application/json"},
            "body": json.dumps(b, default=str, ensure_ascii=False)}


def handler(event, context):
    qs = event.get("queryStringParameters") or {}
    bid = qs.get("booking_id")

    # optional 필터 조합
    filt = None
    for k in ("email", "concert_name"):
        if qs.get(k):
            cond = Attr(k).eq(qs[k])
            filt = cond if filt is None else filt & cond

    if bid:
        # PK 직접 조회 후 optional 필터를 코드에서 적용
        item = _table.get_item(Key={"booking_id": bid}).get("Item")
        if not item:
            return _resp(404, {"error": "not found"})
        for k in ("email", "concert_name"):
            if qs.get(k) and item.get(k) != qs[k]:
                return _resp(404, {"error": "not found (filter mismatch)"})
        return _resp(200, item)

    cid = qs.get("client_id")
    if cid and _GSI:
        kwargs = {"IndexName": _GSI, "KeyConditionExpression": Key("client_id").eq(cid)}
        if filt is not None:
            kwargs["FilterExpression"] = filt
        r = _table.query(**kwargs)
        return _resp(200, {"count": r["Count"], "items": r["Items"]})

    # 최후: scan (대회에선 데이터 적으니 허용, 실무는 지양)
    kwargs = {}
    if filt is not None:
        kwargs["FilterExpression"] = filt
    r = _table.scan(**kwargs)
    return _resp(200, {"count": r["Count"], "items": r["Items"]})
