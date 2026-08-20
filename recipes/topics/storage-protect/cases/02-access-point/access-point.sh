#!/usr/bin/env bash
# 케이스 02 — S3 Access Point 로 접근 분리. VPC 전용 AP + prefix 격리 정책.
set -euo pipefail
export R=${R:-ap-northeast-2} ACCT=$(aws sts get-caller-identity --query Account --output text)
B=lab-protect-$ACCT

aws s3api create-bucket --region $R --bucket $B --create-bucket-configuration LocationConstraint=$R 2>/dev/null || true

# 인터넷 AP (기본) — prefix 별 접근 정책
AP=$(aws s3control create-access-point --account-id $ACCT --name lab-ap-internet --bucket $B \
  --query AccessPointArn --output text)
# AP 정책: /reports/* 만 GetObject 허용
aws s3control put-access-point-policy --account-id $ACCT --name lab-ap-internet --policy '{
  "Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"AWS":"arn:aws:iam::'$ACCT':root"},
    "Action":"s3:GetObject","Resource":"'$AP'/object/reports/*"}]}'

# VPC 전용 AP (NetworkOrigin=VPC) — 그 VPC 안에서만
# VPCID=<전용 vpc>
# aws s3control create-access-point --account-id $ACCT --name lab-ap-vpc --bucket $B \
#   --vpc-configuration VpcId=$VPCID

echo "Access Point 목록:"
aws s3control list-access-points --account-id $ACCT --bucket $B \
  --query 'AccessPointList[].[Name,NetworkOrigin]' --output text
# 정리: aws s3control delete-access-point --account-id $ACCT --name lab-ap-internet; aws s3 rb s3://$B --force
