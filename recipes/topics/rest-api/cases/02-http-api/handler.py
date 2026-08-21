"""HTTP API(apigatewayv2) + Lambda + DynamoDB CRUD. 실검증됨(POST→GET 왕복).
★ 이벤트 형태 (실측):
   - method: event["requestContext"]["http"]["method"]  (REST proxy 는 event["httpMethod"])
   - query : event["queryStringParameters"]
   - body  : HTTP API 는 isBase64Encoded=true 로 body 를 base64 인코딩해 보낼 수 있다 →
             그대로 json.loads 하면 JSONDecodeError. 반드시 디코드 후 파싱(실측 함정).
_parse 가 REST/HTTP API 둘 다 + base64 를 흡수(같은 핸들러 재사용).
"""
import os
import json
import base64
import boto3

table = boto3.resource("dynamodb", region_name=os.environ.get("AWS_REGION", "ap-northeast-2")).Table(os.environ.get("TABLE", "lab-items"))


def _parse(event):
    ctx = event.get("requestContext", {})
    method = event.get("httpMethod") or ctx.get("http", {}).get("method")   # REST | HTTP API v2
    qs = event.get("queryStringParameters") or {}
    body = event.get("body")
    if event.get("isBase64Encoded") and body:        # ★ HTTP API 가 base64 로 줄 수 있음
        body = base64.b64decode(body).decode()
    return method, qs, body


def handler(event, context):
    method, qs, body = _parse(event)
    if method == "POST":
        item = json.loads(body)
        table.put_item(Item=item)
        return {"statusCode": 201, "body": json.dumps({"id": item["id"]})}
    if method == "GET":
        r = table.get_item(Key={"id": qs["id"]})
        return {"statusCode": 200, "body": json.dumps(r.get("Item", {}))}
    return {"statusCode": 405, "body": json.dumps({"error": "method not allowed"})}
