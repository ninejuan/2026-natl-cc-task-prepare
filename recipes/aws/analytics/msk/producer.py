"""
MSK IAM 인증 Producer. VPC 내부 EC2 에서 실행(부트스트랩이 private).
  pip3 install kafka-python-ng botocore
  export BOOTSTRAP=boot-xxxx...:9098 TOPIC=orders AWS_REGION=ap-northeast-2
  python3 producer.py

kafka-python-ng 2.2+ 내장 AWS_MSK_IAM 메커니즘 사용. 서명 라이브러리 불필요.
"""
import os
import json
import socket
from kafka import KafkaProducer


def main():
    producer = KafkaProducer(
        bootstrap_servers=os.environ["BOOTSTRAP"],
        security_protocol="SASL_SSL",
        sasl_mechanism="AWS_MSK_IAM",
        client_id=socket.gethostname(),
        value_serializer=lambda v: json.dumps(v).encode(),
    )
    topic = os.environ.get("TOPIC", "orders")
    for i in range(10):
        producer.send(topic, {"order_id": i, "amount": i * 100})
        print(f"sent order_id={i}")
    producer.flush()
    producer.close()
    print("done")


if __name__ == "__main__":
    main()
