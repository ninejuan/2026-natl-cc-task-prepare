#!/usr/bin/env bash
# 케이스 01 정리. ★ 순서: access point → mount target(먼저·ENI 회수 대기) → FS policy → FS → SG → subnet → VPC.
#   mount target 삭제는 Lattice 처럼 ENI 회수에 시간이 걸린다 → SG/subnet 삭제 전 충분히 대기.
set -uo pipefail
export R=${R:-ap-northeast-2}

FS=$(aws efs describe-file-systems --region $R \
  --query 'FileSystems[?Name==`lab-apne2-efs`].FileSystemId | [0]' --output text)
if [ "$FS" = "None" ] || [ -z "$FS" ]; then echo "no lab-apne2-efs FS"; else
  for AP in $(aws efs describe-access-points --region $R --file-system-id $FS --query 'AccessPoints[].AccessPointId' --output text); do
    aws efs delete-access-point --region $R --access-point-id $AP; done
  for MT in $(aws efs describe-mount-targets --region $R --file-system-id $FS --query 'MountTargets[].MountTargetId' --output text); do
    aws efs delete-mount-target --region $R --mount-target-id $MT; done
  echo "mount target 삭제 대기(ENI 회수)…"
  while [ "$(aws efs describe-mount-targets --region $R --file-system-id $FS --query 'length(MountTargets)' --output text 2>/dev/null || echo 0)" != "0" ]; do sleep 5; done
  aws efs delete-file-system-policy --region $R --file-system-id $FS 2>/dev/null || true
  aws efs delete-file-system --region $R --file-system-id $FS
fi

VPC=$(aws ec2 describe-vpcs --region $R --filters Name=tag:Name,Values=lab-apne2-efs-vpc --query 'Vpcs[0].VpcId' --output text 2>/dev/null)
if [ "$VPC" != "None" ] && [ -n "$VPC" ]; then
  SG=$(aws ec2 describe-security-groups --region $R --filters Name=group-name,Values=lab-apne2-efs-sg Name=vpc-id,Values=$VPC --query 'SecurityGroups[0].GroupId' --output text 2>/dev/null)
  # ENI 회수까지 SG 삭제가 DependencyViolation 날 수 있어 재시도.
  if [ "$SG" != "None" ] && [ -n "$SG" ]; then
    for i in $(seq 1 12); do aws ec2 delete-security-group --region $R --group-id $SG 2>/dev/null && break; echo "  SG busy, retry…"; sleep 10; done
  fi
  for SUB in $(aws ec2 describe-subnets --region $R --filters Name=vpc-id,Values=$VPC --query 'Subnets[].SubnetId' --output text); do
    for i in $(seq 1 6); do aws ec2 delete-subnet --region $R --subnet-id $SUB 2>/dev/null && break; sleep 5; done; done
  for i in $(seq 1 6); do aws ec2 delete-vpc --region $R --vpc-id $VPC 2>/dev/null && { echo "VPC deleted"; break; }; echo "  VPC busy, retry…"; sleep 10; done
fi
echo "teardown done"
