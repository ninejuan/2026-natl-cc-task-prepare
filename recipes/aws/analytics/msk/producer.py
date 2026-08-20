"""
MSK IAM 인증 Producer. VPC 내부 EC2 에서 실행(부트스트랩이 private).
의존성: pip install kafka-python-ng aws-msk-iam-sasl-signer-python

  export BOOTSTRAP=boot-xxxx.c2.kafka-serverless.ap-northeast-2.amazonaws.com:9098
  export TOPIC=lab-topic
  python3 producer.py
"""
import os
import json
import socket
from kafka import KafkaProducer
from kafka.sasl.oauth import AbstractTokenProvider
from aws_msk_iam_sasl_signer import MSKAuthTokenProvider


class MSKTokenProvider(AbstractTokenProvider):
    def token(self):
        token, _ = MSKAuthTokenProvider.generate_auth_token(os.environ.get("AWS_REGION", "ap-northeast-2"))
        return token


def main():
    bootstrap = os.environ["BOOTSTRAP"]
    topic = os.environ.get("TOPIC", "lab-topic")
    producer = KafkaProducer(
        bootstrap_servers=bootstrap,
        security_protocol="SASL_SSL",
        sasl_mechanism="OAUTHBEARER",
        sasl_oauth_token_provider=MSKTokenProvider(),
        client_id=socket.gethostname(),
        value_serializer=lambda v: json.dumps(v).encode(),
    )
    for i in range(10):
        producer.send(topic, {"order_id": i, "amount": i * 100})
        print(f"sent order_id={i}")
    producer.flush()
    producer.close()
    print("done")


if __name__ == "__main__":
    main()
