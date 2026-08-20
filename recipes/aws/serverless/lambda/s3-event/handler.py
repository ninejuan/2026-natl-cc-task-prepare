"""
S3 업로드 이벤트 → 객체 읽어 처리 → DynamoDB 저장. Workflow 모듈의 '수집' 단계 전형.
S3 PutObject 알림(직접) 또는 EventBridge S3 이벤트 양쪽을 파싱한다.

환경변수: TABLE_NAME (선택, 저장할 때)
IAM: s3:GetObject, dynamodb:PutItem, (로그)
"""
import json
import os
import urllib.parse
import boto3

_s3 = boto3.client("s3")
_ddb = boto3.resource("dynamodb")
_table = _ddb.Table(os.environ["TABLE_NAME"]) if os.environ.get("TABLE_NAME") else None


def _records(event):
    """S3 직접 알림과 EventBridge 형식 모두에서 (bucket, key) 목록을 뽑는다."""
    out = []
    if "Records" in event:  # S3 직접 알림
        for r in event["Records"]:
            b = r["s3"]["bucket"]["name"]
            k = urllib.parse.unquote_plus(r["s3"]["object"]["key"])
            out.append((b, k))
    elif event.get("detail", {}).get("bucket"):  # EventBridge
        d = event["detail"]
        out.append((d["bucket"]["name"], d["object"]["key"]))
    return out


def handler(event, context):
    results = []
    for bucket, key in _records(event):
        obj = _s3.get_object(Bucket=bucket, Key=key)
        body = obj["Body"].read().decode("utf-8", errors="replace")
        size = obj["ContentLength"]
        # 예: JSON 라인 파일이면 파싱해 저장
        record = {"bucket": bucket, "key": key, "size": size}
        if _table:
            item = {"pk": f"{bucket}/{key}", "size": size}
            try:
                data = json.loads(body)
                if isinstance(data, dict):
                    item.update({k: str(v) for k, v in data.items()})
            except json.JSONDecodeError:
                item["preview"] = body[:200]
            _table.put_item(Item=item)
        results.append(record)
    return {"processed": len(results), "items": results}
