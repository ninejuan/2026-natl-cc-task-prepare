"""
Book 앱 형: 예약 정보 POST 저장 + GET 조회. API Gateway proxy / ALB / Function URL 모두 대응.
과제지의 대표 형태(2026 task1 Application, REST API Implement 모듈)를 그대로 커버한다.

환경변수:
  TABLE_NAME  (필수)  DynamoDB 테이블. PK=booking_id
  GSI_NAME    (선택)  client_id 조회용 GSI 이름 (예: client-id-created-at-index)

응답 규약:
  POST /v1/book  body {client_id, username, email, concert_name}
    -> 200 {"booking_id": "..."}  + DynamoDB 저장 (created_at 자동 추가)
  GET  /v1/book?booking_id=...            -> 항목 1개
  GET  /v1/book?client_id=...             -> GSI 로 client 의 예약 목록
  GET  /health                            -> 200 OK
"""
import json
import os
import re
import uuid
import datetime
import boto3
from boto3.dynamodb.conditions import Key

_ddb = boto3.resource("dynamodb")
_table = _ddb.Table(os.environ["TABLE_NAME"])
_GSI = os.environ.get("GSI_NAME")


def _resp(status, body):
    return {
        "statusCode": status,
        "headers": {"Content-Type": "application/json"},
        "body": json.dumps(body, ensure_ascii=False, default=str),
    }


def _parse(event):
    """API GW proxy / ALB / Function URL 이벤트에서 method·path·query·body 를 통일해 뽑는다."""
    ctx = event.get("requestContext", {})
    method = (
        event.get("httpMethod")
        or ctx.get("http", {}).get("method")
        or ctx.get("httpMethod")
        or "GET"
    )
    path = event.get("path") or event.get("rawPath") or ctx.get("http", {}).get("path") or "/"
    qs = event.get("queryStringParameters") or {}
    raw = event.get("body") or "{}"
    if event.get("isBase64Encoded"):
        import base64
        raw = base64.b64decode(raw).decode()
    try:
        body = json.loads(raw) if raw else {}
    except json.JSONDecodeError:
        body = {}
    return method, path, qs, body


_EMAIL = re.compile(r"^[^@\s]+@[^@\s]+\.[^@\s]+$")


def handler(event, context):
    method, path, qs, body = _parse(event)

    if path.endswith("/health"):
        return _resp(200, {"status": "ok"})

    if method == "POST":
        # 필수 필드 검증 — 신뢰 경계다. 빠뜨리면 채점 데이터가 깨진다.
        required = ["client_id", "username", "email", "concert_name"]
        missing = [k for k in required if not body.get(k)]
        if missing:
            return _resp(400, {"error": "missing", "fields": missing})
        if not _EMAIL.match(str(body["email"])):
            return _resp(400, {"error": "invalid email"})

        booking_id = "C" + uuid.uuid4().hex[:6].upper()
        item = {
            "booking_id": booking_id,
            "client_id": body["client_id"],
            "username": body["username"],
            "email": body["email"],
            "concert_name": body["concert_name"],
            "created_at": datetime.datetime.now(datetime.timezone.utc)
            .strftime("%Y-%m-%dT%H:%M:%SZ"),
        }
        _table.put_item(Item=item)
        return _resp(200, {"booking_id": booking_id})

    if method == "GET":
        bid = qs.get("booking_id")
        if bid:
            r = _table.get_item(Key={"booking_id": bid})
            it = r.get("Item")
            return _resp(200, it) if it else _resp(404, {"error": "not found"})

        cid = qs.get("client_id")
        if cid and _GSI:
            r = _table.query(
                IndexName=_GSI,
                KeyConditionExpression=Key("client_id").eq(cid),
            )
            return _resp(200, r.get("Items", []))

        return _resp(400, {"error": "booking_id or client_id required"})

    return _resp(405, {"error": "method not allowed"})
