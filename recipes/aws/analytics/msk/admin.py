"""
MSK 토픽 관리 (VPC 내부 EC2 에서). Serverless 는 자동생성이 기본이지만
파티션 수·설정을 지정하려면 명시 생성이 필요하다.

  pip install kafka-python-ng aws-msk-iam-sasl-signer-python
  export BOOTSTRAP=boot-xxxx...:9098 AWS_REGION=ap-northeast-2
  python3 admin.py create orders 6      # 토픽 orders, 파티션 6
  python3 admin.py list
  python3 admin.py delete orders
"""
import os
import sys
from kafka.admin import KafkaAdminClient, NewTopic
from kafka.sasl.oauth import AbstractTokenProvider
from aws_msk_iam_sasl_signer import MSKAuthTokenProvider


class MSKTokenProvider(AbstractTokenProvider):
    def token(self):
        token, _ = MSKAuthTokenProvider.generate_auth_token(os.environ.get("AWS_REGION", "ap-northeast-2"))
        return token


def admin():
    return KafkaAdminClient(
        bootstrap_servers=os.environ["BOOTSTRAP"],
        security_protocol="SASL_SSL",
        sasl_mechanism="OAUTHBEARER",
        sasl_oauth_token_provider=MSKTokenProvider(),
    )


def main():
    cmd = sys.argv[1] if len(sys.argv) > 1 else "list"
    a = admin()
    if cmd == "create":
        topic, parts = sys.argv[2], int(sys.argv[3]) if len(sys.argv) > 3 else 3
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
