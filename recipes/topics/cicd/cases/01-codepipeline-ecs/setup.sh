#!/usr/bin/env bash
# CodePipeline: CodeCommit → CodeBuild → ECS 3-스테이지. 실검증됨(전 스테이지 Succeeded, ECS 롤링 :1→:2).
# 전제: 전용 VPC + public 서브넷(SUB) + SG. ECS 배포 타깃.
set -euo pipefail
export R=${R:-ap-northeast-2} ACCT=$(aws sts get-caller-identity --query Account --output text)
SUB=${SUB:?public subnet} SG=${SG:?}
HERE=$(cd "$(dirname "$0")" && pwd)

# ── 1. CodeCommit repo + 소스 시드(git 없이 put-file) ──
aws codecommit create-repository --region $R --repository-name lab-cc >/dev/null
C1=$(aws codecommit put-file --region $R --repository-name lab-cc --branch-name main \
  --file-content fileb://$HERE/Dockerfile --file-path Dockerfile --commit-message init \
  --query commitId --output text)
aws codecommit put-file --region $R --repository-name lab-cc --branch-name main \
  --file-content fileb://$HERE/buildspec.yml --file-path buildspec.yml --commit-message spec \
  --parent-commit-id "$C1" >/dev/null

# ── 2. ECR + ECS 배포 타깃 ──
aws ecr create-repository --region $R --repository-name lab-pipe >/dev/null
aws ecs create-cluster --region $R --cluster-name lab-pipe-ecs >/dev/null
aws iam create-role --role-name lab-pipe-exec --assume-role-policy-document \
  '{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":"ecs-tasks.amazonaws.com"},"Action":"sts:AssumeRole"}]}' >/dev/null 2>&1 || true
aws iam attach-role-policy --role-name lab-pipe-exec --policy-arn arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy 2>/dev/null || true
sleep 8
aws ecs register-task-definition --region $R --family lab-pipe --network-mode awsvpc \
  --requires-compatibilities FARGATE --cpu 256 --memory 512 \
  --execution-role-arn arn:aws:iam::${ACCT}:role/lab-pipe-exec \
  --container-definitions '[{"name":"app","image":"public.ecr.aws/docker/library/busybox:latest","essential":true,"command":["sh","-c","while true; do echo alive; sleep 30; done"]}]' >/dev/null
aws ecs create-service --region $R --cluster lab-pipe-ecs --service-name lab-pipe-svc \
  --task-definition lab-pipe --desired-count 1 --launch-type FARGATE \
  --network-configuration "awsvpcConfiguration={subnets=[$SUB],securityGroups=[$SG],assignPublicIp=ENABLED}" >/dev/null

# ── 3. CodeBuild(CODEPIPELINE source) ──
ART=lab-pipe-art-$ACCT
aws s3api create-bucket --region $R --bucket $ART --create-bucket-configuration LocationConstraint=$R >/dev/null 2>&1 || true
aws iam create-role --role-name lab-pipe-cb --assume-role-policy-document \
  '{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":"codebuild.amazonaws.com"},"Action":"sts:AssumeRole"}]}' >/dev/null 2>&1 || true
aws iam put-role-policy --role-name lab-pipe-cb --policy-name p --policy-document \
  '{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Action":["logs:*","ecr:*"],"Resource":"*"},{"Effect":"Allow","Action":["s3:GetObject","s3:PutObject","s3:GetBucketAcl","s3:GetBucketLocation"],"Resource":["arn:aws:s3:::'$ART'","arn:aws:s3:::'$ART'/*"]}]}' 2>/dev/null || true
sleep 8
aws codebuild create-project --region $R --name lab-pipe-build \
  --source '{"type":"CODEPIPELINE"}' --artifacts '{"type":"CODEPIPELINE"}' \
  --environment "type=LINUX_CONTAINER,image=aws/codebuild/amazonlinux2-x86_64-standard:5.0,computeType=BUILD_GENERAL1_SMALL,privilegedMode=true,environmentVariables=[{name=AWS_DEFAULT_REGION,value=$R},{name=ECR_URI,value=$ACCT.dkr.ecr.$R.amazonaws.com}]" \
  --service-role "$(aws iam get-role --role-name lab-pipe-cb --query Role.Arn --output text)" >/dev/null

# ── 4. CodePipeline role + 파이프라인 ──
aws iam create-role --role-name lab-pipe-role --assume-role-policy-document \
  '{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":"codepipeline.amazonaws.com"},"Action":"sts:AssumeRole"}]}' >/dev/null 2>&1 || true
aws iam put-role-policy --role-name lab-pipe-role --policy-name p --policy-document \
  '{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Action":["s3:*"],"Resource":["arn:aws:s3:::'$ART'","arn:aws:s3:::'$ART'/*"]},{"Effect":"Allow","Action":["codecommit:GetBranch","codecommit:GetCommit","codecommit:GetRepository","codecommit:UploadArchive","codecommit:GetUploadArchiveStatus","codecommit:CancelUploadArchive","codecommit:GitPull"],"Resource":"*"},{"Effect":"Allow","Action":["codebuild:StartBuild","codebuild:BatchGetBuilds"],"Resource":"*"},{"Effect":"Allow","Action":["ecs:*","iam:PassRole"],"Resource":"*"}]}' 2>/dev/null || true
sleep 10
sed "s|ROLE_ARN|$(aws iam get-role --role-name lab-pipe-role --query Role.Arn --output text)|; s|ARTIFACT_BUCKET|$ART|" \
  $HERE/pipeline.json > /tmp/pipeline-filled.json
aws codepipeline create-pipeline --region $R --cli-input-json file:///tmp/pipeline-filled.json >/dev/null

echo "파이프라인 생성됨(자동 실행). 검증:"
echo "  aws codepipeline get-pipeline-state --region $R --name lab-pipeline --query 'stageStates[].[stageName,latestExecution.status]' --output text"
echo "  → Source/Build/Deploy 전부 Succeeded, ECS 서비스 taskdef revision 증가"
