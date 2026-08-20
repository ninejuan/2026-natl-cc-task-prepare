"""
MSK IAM 인증 Consumer. VPC 내부 EC2 에서 실행.
  pip3 install kafka-python-ng aws-msk-iam-sasl-signer-python
  export BOOTSTRAP=boot-xxxx...:9098 TOPIC=orders AWS_REGION=ap-northeast-2
  python3 consumer.py

★ IAM 인증은 aws-msk-iam-sasl-signer + OAUTHBEARER (producer.py 주석 참조 — 실검증).
  sasl_mechanism="AWS_MSK_IAM" 은 kafka-python-ng 2.2.3 에서 타임아웃(안 됨).
"""
import os
import json
from kafka import KafkaConsumer
from aws_msk_iam_sasl_signer import MSKAuthTokenProvider

REGION = os.environ.get("AWS_REGION", os.environ.get("AWS_DEFAULT_REGION", "ap-northeast-2"))


class TokenProvider:
    def token(self):
        token, _ = MSKAuthTokenProvider.generate_auth_token(REGION)
        return token


def main():
    consumer = KafkaConsumer(
        os.environ.get("TOPIC", "orders"),
        bootstrap_servers=os.environ["BOOTSTRAP"],
        security_protocol="SASL_SSL",
        sasl_mechanism="OAUTHBEARER",
        sasl_oauth_token_provider=TokenProvider(),
        api_version=(2, 8, 1),
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
