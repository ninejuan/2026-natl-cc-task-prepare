#!/usr/bin/env bash
# 케이스 01 — EFS 데이터 보안(자격증명·액세스 관리, AWS 레이어만). 실검증됨(ap-northeast-2).
#  전용 VPC + private subnet ×2 + SG(2049 self-inbound)
#  → 암호화 EFS + mount target ×2 + access point(POSIX 1000, root /app)
#  → file-system policy(IAM 마운트 강제: ClientMount/ClientWrite + AccessedViaMountTarget).
# ★ Linux 파일권한/SELinux 등 OS 보안은 넣지 않는다(가이드 감점 항목).
set -euo pipefail
export R=${R:-ap-northeast-2}
ACCT=$(aws sts get-caller-identity --query Account --output text)

# ── 0. 전용 VPC + subnet ×2 (서로 다른 AZ) + SG ──
VPC=$(aws ec2 create-vpc --region $R --cidr-block 10.30.0.0/16 \
  --tag-specifications 'ResourceType=vpc,Tags=[{Key=Name,Value=lab-apne2-efs-vpc}]' \
  --query Vpc.VpcId --output text)
aws ec2 wait vpc-available --region $R --vpc-ids $VPC

SUB1=$(aws ec2 create-subnet --region $R --vpc-id $VPC --cidr-block 10.30.1.0/24 \
  --availability-zone ${R}a --tag-specifications 'ResourceType=subnet,Tags=[{Key=Name,Value=lab-apne2-efs-sub1}]' \
  --query Subnet.SubnetId --output text)
SUB2=$(aws ec2 create-subnet --region $R --vpc-id $VPC --cidr-block 10.30.2.0/24 \
  --availability-zone ${R}c --tag-specifications 'ResourceType=subnet,Tags=[{Key=Name,Value=lab-apne2-efs-sub2}]' \
  --query Subnet.SubnetId --output text)

SG=$(aws ec2 create-security-group --region $R --group-name lab-apne2-efs-sg \
  --description "EFS NFS 2049 self-inbound" --vpc-id $VPC --query GroupId --output text)
# NFS(2049) self-inbound — 같은 SG 멤버(마운트 타깃·클라이언트 EC2)끼리만 허용.
aws ec2 authorize-security-group-ingress --region $R --group-id $SG \
  --protocol tcp --port 2049 --source-group $SG >/dev/null
echo "VPC=$VPC SUB1=$SUB1 SUB2=$SUB2 SG=$SG"

# ── 1. 암호화 EFS ──
FS=$(aws efs create-file-system --region $R --encrypted \
  --performance-mode generalPurpose --throughput-mode bursting \
  --tags Key=Name,Value=lab-apne2-efs --query FileSystemId --output text)
echo "FS=$FS  (available 대기…)"
while [ "$(aws efs describe-file-systems --region $R --file-system-id $FS \
  --query 'FileSystems[0].LifeCycleState' --output text)" != "available" ]; do sleep 3; done

# ── 2. mount target ×2 (각 subnet, SG 부착) ──
MT1=$(aws efs create-mount-target --region $R --file-system-id $FS \
  --subnet-id $SUB1 --security-groups $SG --query MountTargetId --output text)
MT2=$(aws efs create-mount-target --region $R --file-system-id $FS \
  --subnet-id $SUB2 --security-groups $SG --query MountTargetId --output text)
echo "MT1=$MT1 MT2=$MT2  (available 대기…)"
for MT in $MT1 $MT2; do
  while [ "$(aws efs describe-mount-targets --region $R --mount-target-id $MT \
    --query 'MountTargets[0].LifeCycleState' --output text)" != "available" ]; do sleep 5; done
done

# ── 3. access point (POSIX uid/gid 1000 강제 + root dir /app 격리) ──
AP=$(aws efs create-access-point --region $R --file-system-id $FS \
  --posix-user 'Uid=1000,Gid=1000' \
  --root-directory 'Path=/app,CreationInfo={OwnerUid=1000,OwnerGid=1000,Permissions=750}' \
  --tags Key=Name,Value=lab-apne2-efs-ap --query AccessPointId --output text)
while [ "$(aws efs describe-access-points --region $R --access-point-id $AP \
  --query 'AccessPoints[0].LifeCycleState' --output text)" != "available" ]; do sleep 3; done
echo "AP=$AP"

# ── 4. file-system policy — IAM 마운트 강제 ──
#   마운트 타깃 경유 + IAM 자격증명이 있어야만 ClientMount/ClientWrite 허용.
FS_ARN=$(aws efs describe-file-systems --region $R --file-system-id $FS \
  --query 'FileSystems[0].FileSystemArn' --output text)
aws efs put-file-system-policy --region $R --file-system-id $FS --policy '{
  "Version": "2012-10-17",
  "Statement": [{
    "Sid": "enforce-iam-via-mount-target",
    "Effect": "Allow",
    "Principal": {"AWS": "arn:aws:iam::'"$ACCT"':root"},
    "Action": ["elasticfilesystem:ClientMount", "elasticfilesystem:ClientWrite"],
    "Resource": "'"$FS_ARN"'",
    "Condition": {"Bool": {"elasticfilesystem:AccessedViaMountTarget": "true"}}
  }]
}' >/dev/null

# ── 검증 ──
echo "== describe-file-systems (Encrypted, LifeCycleState) =="
aws efs describe-file-systems --region $R --file-system-id $FS \
  --query 'FileSystems[0].[Encrypted,LifeCycleState]' --output text
echo "== describe-access-points (RootDirectory.Path, PosixUser.Uid) =="
aws efs describe-access-points --region $R --file-system-id $FS \
  --query 'AccessPoints[0].[RootDirectory.Path,PosixUser.Uid]' --output text
echo "== describe-mount-targets (LifeCycleState) =="
aws efs describe-mount-targets --region $R --file-system-id $FS \
  --query 'MountTargets[].LifeCycleState' --output text
echo "== describe-file-system-policy =="
aws efs describe-file-system-policy --region $R --file-system-id $FS --query Policy --output text | python3 -m json.tool

echo "FS=$FS AP=$AP MT1=$MT1 MT2=$MT2 SG=$SG SUB1=$SUB1 SUB2=$SUB2 VPC=$VPC"
