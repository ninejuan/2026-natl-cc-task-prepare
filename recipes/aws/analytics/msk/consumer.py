"""
MSK IAM 인증 Consumer. VPC 내부 EC2 에서 실행.
  pip3 install kafka-python-ng botocore
  export BOOTSTRAP=boot-xxxx...:9098 TOPIC=orders AWS_REGION=ap-northeast-2
  python3 consumer.py

kafka-python-ng 2.2+ 내장 AWS_MSK_IAM 메커니즘 사용.
"""
import os
import json
from kafka import KafkaConsumer


def main():
    consumer = KafkaConsumer(
        os.environ.get("TOPIC", "orders"),
        bootstrap_servers=os.environ["BOOTSTRAP"],
        security_protocol="SASL_SSL",
        sasl_mechanism="AWS_MSK_IAM",
        group_id="lab-consumer",
        auto_offset_reset="earliest",
        value_deserializer=lambda v: json.loads(v.decode()),
        consumer_timeout_ms=30000,
    )
    n = 0
    for msg in consumer:
        n += 1
        print(f"partition={msg.partition} offset={msg.offset} value={msg.value}")
    print(f"consumed {n} messages")
    consumer.close()


if __name__ == "__main__":
    main()
