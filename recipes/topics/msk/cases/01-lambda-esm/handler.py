"""MSK ESM consumer: base64 디코드 후 레코드를 topic-partition 별로 로깅.

Lambda 가 VPC 밖에서도 MSK ESM 을 자동 폴링한다(Lambda 서비스가 클러스터
서브넷/SG 로 연결). SG self-inbound 9098 이 있어야 폴러가 붙는다.
실제 처리 로직(DDB put 등)은 여기서 확장.
"""
import base64


def handler(event, context):
    total = 0
    for tp, records in event.get("records", {}).items():
        for r in records:
            payload = base64.b64decode(r["value"]).decode() if r.get("value") else ""
            print(f"{tp} offset={r['offset']} value={payload}")
            total += 1
    print(f"processed {total} records")
    return {"processed": total}
