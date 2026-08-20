#!/usr/bin/env bash
# CodePipeline 스택 정리. (VPC/서브넷/SG 는 이 케이스가 안 만들었으면 별도)
set -uo pipefail
export R=${R:-ap-northeast-2} ACCT=$(aws sts get-caller-identity --query Account --output text)
aws codepipeline delete-pipeline --region $R --name lab-pipeline 2>/dev/null
aws codebuild delete-project --region $R --name lab-pipe-build 2>/dev/null
aws codecommit delete-repository --region $R --repository-name lab-cc >/dev/null 2>&1
aws s3 rb s3://lab-pipe-art-$ACCT --force 2>/dev/null
aws ecs update-service --region $R --cluster lab-pipe-ecs --service lab-pipe-svc --desired-count 0 >/dev/null 2>&1
aws ecs delete-service --region $R --cluster lab-pipe-ecs --service lab-pipe-svc --force >/dev/null 2>&1
for i in $(seq 1 12); do [ "$(aws ecs list-tasks --region $R --cluster lab-pipe-ecs --query 'length(taskArns)' --output text 2>/dev/null)" = 0 ] && break; sleep 10; done
aws ecs delete-cluster --region $R --cluster lab-pipe-ecs 2>/dev/null
aws ecr delete-repository --region $R --repository-name lab-pipe --force >/dev/null 2>&1
for role in lab-pipe-exec lab-pipe-cb lab-pipe-role; do
  for p in $(aws iam list-role-policies --role-name $role --query 'PolicyNames' --output text 2>/dev/null); do aws iam delete-role-policy --role-name $role --policy-name $p 2>/dev/null; done
  for a in $(aws iam list-attached-role-policies --role-name $role --query 'AttachedPolicies[].PolicyArn' --output text 2>/dev/null); do aws iam detach-role-policy --role-name $role --policy-arn $a 2>/dev/null; done
  aws iam delete-role --role-name $role 2>/dev/null
done
echo "codepipeline 스택 정리 완료"
