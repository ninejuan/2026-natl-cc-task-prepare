"""
ALB target Lambda. ALB 이벤트는 API GW proxy 와 형식이 다르다:
  - 요청: httpMethod, path, queryStringParameters, headers, body, isBase64Encoded
  - 응답: statusCode, statusDescription, headers, body, isBase64Encoded 필수
statusDescription 이 없으면 ALB 가 502 를 낼 수 있다.

CloudFront -> ALB -> Lambda 경로(1과제 흔함)에서 GET 라우팅용.
IAM: 대상 리소스 권한 (여기선 DynamoDB 조회 가정)
"""
import json
import os
import boto3

_ddb = boto3.resource("dynamodb")
_table = _ddb.Table(os.environ["TABLE_NAME"]) if os.environ.get("TABLE_NAME") else None


def _resp(status, body, desc="200 OK"):
    return {
        "statusCode": status,
        "statusDescription": desc,  # ALB 는 이게 필요하다
        "headers": {"Content-Type": "application/json"},
        "isBase64Encoded": False,
        "body": json.dumps(body, default=str, ensure_ascii=False),
    }


def handler(event, context):
    path = event.get("path", "/")
    qs = event.get("queryStringParameters") or {}

    if path.endswith("/health"):
        return _resp(200, {"status": "ok"})

    bid = qs.get("booking_id")
    if bid and _table:
        it = _table.get_item(Key={"booking_id": bid}).get("Item")
        return _resp(200, it, "200 OK") if it else _resp(404, {"error": "not found"}, "404 Not Found")

    return _resp(400, {"error": "booking_id required"}, "400 Bad Request")
