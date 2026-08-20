"""
MSK 토픽 관리 (VPC 내부 EC2 에서). Serverless 는 자동생성이 기본이지만
파티션 수·설정을 지정하려면 명시 생성이 필요하다.

  pip3 install kafka-python-ng aws-msk-iam-sasl-signer-python
  export BOOTSTRAP=boot-xxxx...:9098 AWS_REGION=ap-northeast-2
  python3 admin.py create orders 6      # 토픽 orders, 파티션 6
  python3 admin.py list
  python3 admin.py delete orders

★ 실검증(MSK Serverless): IAM 인증은 aws-msk-iam-sasl-signer 토큰을 OAUTHBEARER 로.
  sasl_mechanism='AWS_MSK_IAM'(kafka-python-ng 내장) 은 실제로는 metadata 타임아웃으로 실패했다.
  이 admin.py 의 OAUTHBEARER 방식으로 create/list/produce/consume 왕복까지 검증됨.
  ★ Serverless 는 replication_factor=3 강제(1 로 만들면 거부).
"""
import os
import sys
from kafka.admin import KafkaAdminClient, NewTopic
from aws_msk_iam_sasl_signer import MSKAuthTokenProvider

REGION = os.environ.get("AWS_REGION", os.environ.get("AWS_DEFAULT_REGION", "ap-northeast-2"))


class TokenProvider:
    def token(self):
        token, _ = MSKAuthTokenProvider.generate_auth_token(REGION)
        return token


COMMON = dict(
    bootstrap_servers=os.environ["BOOTSTRAP"],
    security_protocol="SASL_SSL",
    sasl_mechanism="OAUTHBEARER",
    sasl_oauth_token_provider=TokenProvider(),
    api_version=(2, 8, 1),
)


def main():
    cmd = sys.argv[1] if len(sys.argv) > 1 else "list"
    a = KafkaAdminClient(**COMMON)
    if cmd == "create":
        topic = sys.argv[2]
        parts = int(sys.argv[3]) if len(sys.argv) > 3 else 3
        a.create_topics([NewTopic(name=topic, num_partitions=parts, replication_factor=3)])
        print(f"created {topic} ({parts} partitions)")
    elif cmd == "list":
        print("\n".join(sorted(a.list_topics())))
    elif cmd == "delete":
        a.delete_topics([sys.argv[2]])
        print(f"deleted {sys.argv[2]}")
    a.close()


if __name__ == "__main__":
    main()
