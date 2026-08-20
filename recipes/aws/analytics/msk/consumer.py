"""
MSK IAM 인증 Consumer. VPC 내부 EC2 에서 실행.
의존성: pip install kafka-python-ng aws-msk-iam-sasl-signer-python

  export BOOTSTRAP=boot-xxxx...:9098 TOPIC=lab-topic
  python3 consumer.py
"""
import os
import json
from kafka import KafkaConsumer
from kafka.sasl.oauth import AbstractTokenProvider
from aws_msk_iam_sasl_signer import MSKAuthTokenProvider


class MSKTokenProvider(AbstractTokenProvider):
    def token(self):
        token, _ = MSKAuthTokenProvider.generate_auth_token(os.environ.get("AWS_REGION", "ap-northeast-2"))
        return token


def main():
    consumer = KafkaConsumer(
        os.environ.get("TOPIC", "lab-topic"),
        bootstrap_servers=os.environ["BOOTSTRAP"],
        security_protocol="SASL_SSL",
        sasl_mechanism="OAUTHBEARER",
        sasl_oauth_token_provider=MSKTokenProvider(),
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
