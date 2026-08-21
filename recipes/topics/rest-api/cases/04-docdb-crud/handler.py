"""DocumentDB(MongoDB 호환) CRUD Lambda. VPC 연결 필수(DocDB 는 VPC 내부 + TLS).
  pip3 install pymongo  (+ global-bundle.pem 을 배포 패키지에 포함)
  env: DOCDB_URI, DB=lab, COLL=items
DocDB 는 TLS 강제 → tls=true & tlsCAFile=global-bundle.pem.
"""
import os
import json
import base64
from pymongo import MongoClient

_client = None


def _coll():
    global _client
    if _client is None:
        _client = MongoClient(os.environ["DOCDB_URI"], tls=True,
                              tlsCAFile=os.environ.get("CA", "global-bundle.pem"),
                              retryWrites=False)   # DocDB 는 retryWrites 미지원 → false
    return _client[os.environ.get("DB", "lab")][os.environ.get("COLL", "items")]


def handler(event, context):
    ctx = event.get("requestContext", {})
    method = event.get("httpMethod") or ctx.get("http", {}).get("method")
    body = event.get("body")
    if event.get("isBase64Encoded") and body:   # HTTP API base64 함정(rest-api 02 참조)
        body = base64.b64decode(body).decode()
    if method == "POST":
        doc = json.loads(body)
        _coll().insert_one(doc)
        return {"statusCode": 201, "body": json.dumps({"id": doc["id"]})}
    if method == "GET":
        q = (event.get("queryStringParameters") or {})
        d = _coll().find_one({"id": q["id"]}, {"_id": 0})
        return {"statusCode": 200, "body": json.dumps(d or {})}
    return {"statusCode": 405, "body": "{}"}
