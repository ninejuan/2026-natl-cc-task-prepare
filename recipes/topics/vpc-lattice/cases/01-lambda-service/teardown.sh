#!/usr/bin/env bash
# 케이스 01 정리. association → service/network → target group → lambda → VPC 순서.
set -uo pipefail
export R=${R:-ap-northeast-2}
ACCT=$(aws sts get-caller-identity --query Account --output text)

NET=$(aws vpc-lattice list-service-networks --region $R --query "items[?name=='lab-lattice-net'].id" --output text)
SVC=$(aws vpc-lattice list-services --region $R --query "items[?name=='lab-lattice-svc'].id" --output text)
TG=$(aws vpc-lattice list-target-groups --region $R --query "items[?name=='lab-tg-lambda'].id" --output text)

# association 먼저
for a in $(aws vpc-lattice list-service-network-service-associations --region $R --service-network-identifier "$NET" --query 'items[].id' --output text 2>/dev/null); do
  aws vpc-lattice delete-service-network-service-association --region $R --service-network-service-association-identifier $a; done
for a in $(aws vpc-lattice list-service-network-vpc-associations --region $R --service-network-identifier "$NET" --query 'items[].id' --output text 2>/dev/null); do
  aws vpc-lattice delete-service-network-vpc-association --region $R --service-network-vpc-association-identifier $a; done
# ★ VPC association 삭제는 Lattice-managed ENI 회수까지 시간이 걸린다(실측 ~60-90s).
#   충분히 안 기다리면 delete-service-network 가 ConflictException, delete-vpc 가 DependencyViolation.
echo "waiting for vpc/service associations to drain..."
for i in $(seq 1 15); do
  n=$(aws vpc-lattice list-service-network-vpc-associations --region $R --service-network-identifier "$NET" --query 'length(items)' --output text 2>/dev/null || echo 0)
  [ "$n" = "0" ] && break; sleep 8
done

# listener 는 service 삭제 시 함께. target 등록 해제 후 TG 삭제.
[ -n "$TG" ] && for t in $(aws vpc-lattice list-targets --region $R --target-group-identifier $TG --query 'items[].id' --output text 2>/dev/null); do
  aws vpc-lattice deregister-targets --region $R --target-group-identifier $TG --targets id=$t; done
[ -n "$SVC" ] && aws vpc-lattice delete-service --region $R --service-identifier $SVC
sleep 5
[ -n "$TG" ] && aws vpc-lattice delete-target-group --region $R --target-group-identifier $TG
[ -n "$NET" ] && aws vpc-lattice delete-service-network --region $R --service-network-identifier $NET

aws lambda delete-function --region $R --function-name lab-lattice-fn 2>/dev/null
aws iam detach-role-policy --role-name lab-lattice-fn-role --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole 2>/dev/null
aws iam delete-role --role-name lab-lattice-fn-role 2>/dev/null

VPC=$(aws ec2 describe-vpcs --region $R --filters Name=tag:Name,Values=lab-lattice-vpc --query 'Vpcs[0].VpcId' --output text 2>/dev/null)
# Lattice ENI 회수가 끝나야 VPC 삭제됨 — 실패하면 재시도
if [ "$VPC" != "None" ] && [ -n "$VPC" ]; then
  for i in $(seq 1 10); do
    aws ec2 delete-vpc --region $R --vpc-id $VPC 2>/dev/null && { echo "VPC deleted"; break; }
    echo "  VPC busy(Lattice ENI 회수 대기), retry..."; sleep 10
  done
fi
echo "teardown done"
