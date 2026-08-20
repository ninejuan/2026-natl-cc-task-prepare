"""
MSK 토픽 관리 (VPC 내부 EC2 에서). Serverless 는 자동생성이 기본이지만
파티션 수·설정을 지정하려면 명시 생성이 필요하다.

  pip3 install kafka-python-ng botocore   # botocore 가 IAM 인증에 필요
  export BOOTSTRAP=boot-xxxx...:9098 AWS_REGION=ap-northeast-2
  python3 admin.py create orders 6      # 토픽 orders, 파티션 6
  python3 admin.py list
  python3 admin.py delete orders

kafka-python-ng 2.2+ 는 AWS_MSK_IAM 메커니즘을 내장한다(kafka/sasl/msk.py).
별도 서명 라이브러리 불필요 — sasl_mechanism='AWS_MSK_IAM' + botocore 자격증명만.
"""
import os
import sys
from kafka.admin import KafkaAdminClient, NewTopic

COMMON = dict(
    bootstrap_servers=os.environ["BOOTSTRAP"],
    security_protocol="SASL_SSL",
    sasl_mechanism="AWS_MSK_IAM",   # EC2 instance profile / 환경 자격증명을 자동 사용
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
