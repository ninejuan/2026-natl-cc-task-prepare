"""
MSK IAM 인증 Producer. VPC 내부 EC2 에서 실행(부트스트랩이 private).
  pip3 install kafka-python-ng aws-msk-iam-sasl-signer-python
  export BOOTSTRAP=boot-xxxx...:9098 TOPIC=orders AWS_REGION=ap-northeast-2
  python3 producer.py

★ 실검증(2026-08, MSK Serverless eu-west-1): sasl_mechanism="AWS_MSK_IAM" 은 kafka-python-ng
  2.2.3 에서 **동작하지 않는다**(metadata 갱신 60초 타임아웃). TCP 9098 은 열려 있어도 SASL 핸드셰이크가
  안 끝남. 실제로 되는 방법은 aws-msk-iam-sasl-signer-python 의 토큰을 OAUTHBEARER 로 넘기는 것.
  (admin/produce/consume 왕복까지 이 방식으로 검증 완료)
"""
import os
import json
import socket
from kafka import KafkaProducer
from aws_msk_iam_sasl_signer import MSKAuthTokenProvider

REGION = os.environ.get("AWS_REGION", os.environ.get("AWS_DEFAULT_REGION", "ap-northeast-2"))


class TokenProvider:
    """kafka-python-ng 의 sasl_oauth_token_provider 인터페이스(.token())."""
    def token(self):
        token, _expiry = MSKAuthTokenProvider.generate_auth_token(REGION)
        return token


def iam_auth():
    return dict(
        security_protocol="SASL_SSL",
        sasl_mechanism="OAUTHBEARER",
        sasl_oauth_token_provider=TokenProvider(),
        api_version=(2, 8, 1),   # Serverless 는 명시 권장(자동탐지가 SASL 전에 실패할 수 있음)
    )


def main():
    producer = KafkaProducer(
        bootstrap_servers=os.environ["BOOTSTRAP"],
        client_id=socket.gethostname(),
        value_serializer=lambda v: json.dumps(v).encode(),
        **iam_auth(),
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
