#!/usr/bin/env bash
# 케이스 02 — EC2(INSTANCE) 타깃 + health check. 앱을 EC2 로 요구하는 과제용.
# ⚠️ EC2 시간과금. 검증 후 즉시 teardown. (LAMBDA 타깃보다 무거우니 앱 EC2 필요할 때만)
# INSTANCE 타깃 그룹 문법 + health_check 는 context7/문서 기준. 실검증은 case01(Lambda)로 대체.
set -euo pipefail
export R=${R:-ap-northeast-2}
VPC=${VPC:?전용 VPC id}   # 케이스 01 스타일로 미리 생성 + 서브넷/SG
SUBNET=${SUBNET:?}
SG=${SG:?}   # 80 인바운드 허용(Lattice managed prefix list 또는 VPC CIDR)

# INSTANCE 타깃 그룹 (health check 지원)
TG=$(aws vpc-lattice create-target-group --region $R --name lab-tg-ec2 --type INSTANCE \
  --config "{\"vpcIdentifier\":\"$VPC\",\"port\":80,\"protocol\":\"HTTP\",\"protocolVersion\":\"HTTP1\",
    \"healthCheck\":{\"enabled\":true,\"path\":\"/\",\"protocol\":\"HTTP\",\"port\":80,
      \"healthCheckIntervalSeconds\":30,\"healthCheckTimeoutSeconds\":5,
      \"healthyThresholdCount\":2,\"unhealthyThresholdCount\":2,\"matcher\":{\"httpCode\":\"200\"}}}" \
  --query id --output text)

# nginx EC2 (Amazon Linux 2023, user-data 로 nginx)
AMI=$(aws ssm get-parameter --region $R --name /aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64 --query Parameter.Value --output text)
IID=$(aws ec2 run-instances --region $R --image-id $AMI --instance-type t3.micro \
  --subnet-id $SUBNET --security-group-ids $SG \
  --user-data 'IyEvYmluL2Jhc2gKZG5mIGluc3RhbGwgLXkgbmdpbngKc3lzdGVtY3RsIGVuYWJsZSAtLW5vdyBuZ2lueA==' \
  --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=lab-lattice-ec2}]' \
  --query 'Instances[0].InstanceId' --output text)
aws ec2 wait instance-running --region $R --instance-ids $IID

# 인스턴스 등록 (port 지정 가능)
aws vpc-lattice register-targets --region $R --target-group-identifier $TG --targets "id=$IID,port=80"

echo "TG=$TG IID=$IID"
echo "health(초기 INITIAL → HEALTHY 대기):"
aws vpc-lattice list-targets --region $R --target-group-identifier $TG --query 'items[].{id:id,status:status,reason:reasonCode}' --output json
# 이후 listener/rule 로 이 TG 를 forward (케이스 01/03 참고).
