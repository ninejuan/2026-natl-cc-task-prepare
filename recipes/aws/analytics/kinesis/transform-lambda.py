"""
Firehose 변환 Lambda. 레코드를 가공/필터/보강 후 Firehose 로 돌려준다.
S3 적재 전 정제·포맷 통일에 쓴다.

Firehose ProcessingConfiguration 의 Processor Type=Lambda 로 연결.
반환 형식이 정해져 있다: recordId + result(Ok/Dropped/ProcessingFailed) + data(base64).
"""
import base64
import json


def handler(event, context):
    output = []
    for record in event["records"]:
        payload = base64.b64decode(record["data"]).decode("utf-8")
        try:
            data = json.loads(payload)
            # 보강: 파티션용 dt 추가, 필드 정규화
            data["event_type"] = str(data.get("event_type", "unknown")).lower()
            if "event_time" in data and "dt" not in data:
                data["dt"] = data["event_time"][:10]
            # 필터: value 가 없으면 드롭
            if data.get("value") is None:
                output.append({"recordId": record["recordId"], "result": "Dropped"})
                continue
            # 개행 추가(S3 JSONL 로 저장되게)
            out = (json.dumps(data) + "\n").encode("utf-8")
            output.append({
                "recordId": record["recordId"],
                "result": "Ok",
                "data": base64.b64encode(out).decode("utf-8"),
            })
        except Exception:
            output.append({"recordId": record["recordId"], "result": "ProcessingFailed"})
    return {"records": output}
