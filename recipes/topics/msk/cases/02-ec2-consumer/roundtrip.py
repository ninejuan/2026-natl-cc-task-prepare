#!/usr/bin/env python3
"""MSK Serverless produce→consume 왕복 (VPC 내부 EC2). IAM 인증(OAUTHBEARER + signer).
실검증됨(eu-west-1): topic 생성 → produce → consume "msk-ec2-roundtrip-final" 수신.

  pip3 install kafka-python-ng aws-msk-iam-sasl-signer-python
  export BOOTSTRAP=boot-xxxx...:9098 AWS_DEFAULT_REGION=ap-northeast-2 TOPIC=lab-topic
  python3 roundtrip.py

★ sasl_mechanism="AWS_MSK_IAM"(kafka-python-ng 내장)은 metadata 타임아웃으로 실패.
  반드시 signer 토큰을 OAUTHBEARER 로. (../../../aws/analytics/msk/ 참조)
"""
import os
import json
from kafka import KafkaProducer, KafkaConsumer
from kafka.admin import KafkaAdminClient, NewTopic
from aws_msk_iam_sasl_signer import MSKAuthTokenProvider

REGION = os.environ.get("AWS_DEFAULT_REGION", "ap-northeast-2")
BOOTSTRAP = os.environ["BOOTSTRAP"]
TOPIC = os.environ.get("TOPIC", "lab-topic")


class TokenProvider:
    def token(self):
        t, _ = MSKAuthTokenProvider.generate_auth_token(REGION)
        return t


AUTH = dict(security_protocol="SASL_SSL", sasl_mechanism="OAUTHBEARER",
            sasl_oauth_token_provider=TokenProvider(), api_version=(2, 8, 1))


def main():
    admin = KafkaAdminClient(bootstrap_servers=BOOTSTRAP, **AUTH)
    try:
        # ★ Serverless 는 replication_factor=3 강제
        admin.create_topics([NewTopic(name=TOPIC, num_partitions=1, replication_factor=3)])
        print("topic created")
    except Exception as e:
        print("topic:", type(e).__name__)

    p = KafkaProducer(bootstrap_servers=BOOTSTRAP, value_serializer=lambda v: json.dumps(v).encode(), **AUTH)
    p.send(TOPIC, {"msg": "msk-ec2-roundtrip-final"})
    p.flush()
    print("PRODUCED")

    c = KafkaConsumer(TOPIC, bootstrap_servers=BOOTSTRAP, auto_offset_reset="earliest",
                      consumer_timeout_ms=25000, group_id="lab-rt", **AUTH)
    for m in c:
        print("CONSUMED:", m.value.decode())
        break


if __name__ == "__main__":
    main()
