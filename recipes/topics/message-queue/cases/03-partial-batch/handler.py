"""부분 배치 실패 핸들러 (ReportBatchItemFailures).
ESM 설정: --function-response-types ReportBatchItemFailures
이걸 반환 안 하면 배치 중 1건만 실패해도 배치 "전체"가 재처리된다(성공분 중복 처리).
실패한 messageId 만 batchItemFailures 로 돌려주면 그것만 재시도.
"""
import json


def process(body: str):
    # 예: 짝수 order 만 성공, 홀수는 실패로 가정 (실제론 비즈니스 로직)
    data = json.loads(body) if body.strip().startswith("{") else {"raw": body}
    if "fail" in body:
        raise ValueError(f"cannot process: {body}")
    return data


def handler(event, context):
    failures = []
    for rec in event["Records"]:
        try:
            process(rec["body"])
        except Exception as e:
            print(f"failed {rec['messageId']}: {e}")
            failures.append({"itemIdentifier": rec["messageId"]})
    # 성공분은 자동 삭제, 실패분만 재시도 (핵심)
    return {"batchItemFailures": failures}
