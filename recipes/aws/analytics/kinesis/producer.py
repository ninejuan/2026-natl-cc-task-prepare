"""
Kinesis Data Streams Producer. 로그/이벤트 생성기(대회 배포파일 형).
put-records 로 배치 발행 (put-record 보다 효율적).

  pip install boto3
  export STREAM=lab-stream AWS_REGION=ap-northeast-2 RATE=10 DURATION=60
  python3 producer.py
"""
import os
import json
import time
import random
import datetime
import boto3

_kinesis = boto3.client("kinesis")
STREAM = os.environ.get("STREAM", "lab-stream")
RATE = int(os.environ.get("RATE", "10"))          # 초당 레코드 수
DURATION = int(os.environ.get("DURATION", "60"))  # 총 발행 시간(초)

EVENT_TYPES = ["click", "view", "purchase", "add_cart"]


def gen_record():
    now = datetime.datetime.now(datetime.timezone.utc)
    return {
        "user_id": f"u{random.randint(1, 100)}",
        "event_type": random.choice(EVENT_TYPES),
        "value": round(random.uniform(1, 1000), 2),
        "event_time": now.strftime("%Y-%m-%dT%H:%M:%SZ"),
        "dt": now.strftime("%Y-%m-%d"),
    }


def main():
    print(f"producing to {STREAM}: {RATE}/s for {DURATION}s")
    end = time.time() + DURATION
    total = 0
    while time.time() < end:
        records = []
        for _ in range(RATE):
            r = gen_record()
            records.append({"Data": json.dumps(r).encode(), "PartitionKey": r["user_id"]})
        resp = _kinesis.put_records(StreamName=STREAM, Records=records)
        failed = resp.get("FailedRecordCount", 0)
        total += len(records) - failed
        if failed:
            print(f"  {failed} failed")
        time.sleep(1)
    print(f"done. sent ~{total}")


if __name__ == "__main__":
    main()
