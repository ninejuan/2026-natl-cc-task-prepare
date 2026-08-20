# Code 시리즈 (CodeBuild · CodePipeline · CodeDeploy · CodeConnections)

**트리거 문구** — "CI/CD 파이프라인", "코드를 배포", "GitHub 연동 자동 배포", "이미지 빌드" (+ **로컬 Docker 없이 ECR push**).

**전제**
```bash
export R=ap-northeast-2 ACCT=$(aws sts get-caller-identity --query Account --output text)
```

CI/CD 모듈(2025)은 GitHub Actions·ArgoCD 가 필수지만(→ `../../../cncf/argocd/`), **AWS 네이티브 CI/CD** 나 **로컬 Docker 없는 이미지 빌드**가 필요하면 이쪽.

---

## ★ 케이스 A — CodeBuild 로 이미지 빌드→ECR (로컬 Docker 불필요) [검증됨]

지급 PC 에 Docker Desktop(WSL2 재부팅)을 안 깔고 이미지를 만드는 길. CloudShell 1GB 한계도 우회.

```bash
# ECR + CodeBuild role (logs + ECR push + S3 소스 읽기)
aws ecr create-repository --region $R --repository-name lab-cb-app
cat > cbt.json <<'JSON'
{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":"codebuild.amazonaws.com"},"Action":"sts:AssumeRole"}]}
JSON
aws iam create-role --role-name lab-cb-role --assume-role-policy-document file://cbt.json
cat > cbp.json <<JSON
{"Version":"2012-10-17","Statement":[
 {"Effect":"Allow","Action":["logs:CreateLogGroup","logs:CreateLogStream","logs:PutLogEvents"],"Resource":"*"},
 {"Effect":"Allow","Action":["ecr:GetAuthorizationToken","ecr:BatchCheckLayerAvailability","ecr:InitiateLayerUpload","ecr:UploadLayerPart","ecr:CompleteLayerUpload","ecr:PutImage","ecr:BatchGetImage","ecr:GetDownloadUrlForLayer"],"Resource":"*"},
 {"Effect":"Allow","Action":["s3:GetObject"],"Resource":"arn:aws:s3:::lab-cbsrc-$ACCT/*"}]}
JSON
aws iam put-role-policy --role-name lab-cb-role --policy-name p --policy-document file://cbp.json
sleep 10
CBROLE=$(aws iam get-role --role-name lab-cb-role --query Role.Arn --output text)

# 소스(Dockerfile + buildspec-ecr.yml)를 zip 으로 S3 에
zip -q src.zip Dockerfile.example buildspec-ecr.yml   # Dockerfile 로 이름 맞추기
aws s3 cp src.zip s3://lab-cbsrc-$ACCT/src.zip

# 프로젝트 — privilegedMode:true 필수(docker 데몬)
aws codebuild create-project --region $R --cli-input-json '{
  "name":"lab-cb",
  "source":{"type":"S3","location":"lab-cbsrc-'$ACCT'/src.zip","buildspec":"buildspec.yml"},
  "artifacts":{"type":"NO_ARTIFACTS"},
  "environment":{"type":"LINUX_CONTAINER","image":"aws/codebuild/amazonlinux2-x86_64-standard:5.0",
    "computeType":"BUILD_GENERAL1_SMALL","privilegedMode":true,
    "environmentVariables":[{"name":"AWS_DEFAULT_REGION","value":"'$R'"},{"name":"ECR_URI","value":"'$ACCT'.dkr.ecr.'$R'.amazonaws.com"},{"name":"IMAGE_TAG","value":"v1"}]},
  "serviceRole":"'$CBROLE'"}'

BUILD=$(aws codebuild start-build --region $R --project-name lab-cb --query 'build.id' --output text)
aws codebuild batch-get-builds --region $R --ids "$BUILD" --query 'builds[0].buildStatus' --output text  # SUCCEEDED
aws ecr describe-images --region $R --repository-name lab-cb-app --query 'imageDetails[].imageTags[]' --output text  # v1
```
`buildspec-ecr.yml` 이 ECR 로그인→build→push 를 한다.
> ★ **privilegedMode:true** 없으면 `docker build` 가 "Cannot connect to Docker daemon" 로 실패. 이미지 빌드 프로젝트의 필수 플래그.
> ★ **role 에 S3 소스 읽기 권한** 필요 — 없으면 DOWNLOAD_SOURCE 단계 403(실검증 중 실제로 밟음).

## 케이스 B — CodePipeline (source→build→deploy)

```bash
# 3단계: CodeConnections(GitHub) → CodeBuild → ECS/CodeDeploy
# CodePipeline 이 각 단계 artifact 를 S3 로 전달.
# ECS 배포 액션은 buildspec-ecs-deploy.yml 이 만든 imagedefinitions.json 을 읽는다.
```
- **source**: CodeConnections(구 CodeStar Connections)로 GitHub 연결. `aws codeconnections create-connection --provider-type GitHub` → 콘솔에서 OAuth 승인(수동).
- **build**: CodeBuild + `buildspec-ecs-deploy.yml`.
- **deploy**: ECS(롤링) 또는 CodeDeploy(blue/green).

## 케이스 C — CodeDeploy

```bash
# EC2/온프렘: in-place 또는 blue/green (appspec.yml + 배포 그룹)
# ECS: blue/green (트래픽 전환, CodeDeployDefault.ECSAllAtOnce 등)
# Lambda: 가중 트래픽 전환 (Canary10Percent5Minutes 등)
```
"무중단 배포"·"blue/green" 요구 시. ECS blue/green 은 ALB 리스너 2개(prod/test) 필요.

## 검증

```bash
aws codebuild batch-get-builds --region $R --ids "$BUILD" \
  --query 'builds[0].[buildStatus,phases[?phaseStatus==`FAILED`].phaseType]' --output text
aws ecr describe-images --region $R --repository-name lab-cb-app --query 'imageDetails[].imageTags[]' --output text
aws codepipeline get-pipeline-state --region $R --name lab-pipe --query 'stageStates[].[stageName,latestExecution.status]' --output text
```
빌드 실패 시 `phases[?phaseStatus==FAILED]` 로 어느 단계인지 → 그 phase 로그 확인.

## Terraform

```hcl
resource "aws_codebuild_project" "b" {
  name         = "lab-cb"
  service_role = aws_iam_role.cb.arn
  artifacts { type = "NO_ARTIFACTS" }
  environment {
    compute_type    = "BUILD_GENERAL1_SMALL"
    image           = "aws/codebuild/amazonlinux2-x86_64-standard:5.0"
    type            = "LINUX_CONTAINER"
    privileged_mode = true   # ★ docker 빌드 필수
    environment_variable {
      name  = "ECR_URI"
      value = "${data.aws_caller_identity.cur.account_id}.dkr.ecr.ap-northeast-2.amazonaws.com"
    }
  }
  source {
    type      = "S3"
    location  = "${aws_s3_bucket.src.id}/src.zip"
    buildspec = "buildspec.yml"
  }
}
# CodePipeline: aws_codepipeline (source=CodeConnections, build=CodeBuild, deploy=ECS)
```

## Console 팁

- **CodeBuild 프로젝트 마법사**: source(S3/GitHub/CodeCommit)·환경(privileged 체크박스)·buildspec 을 폼으로.
- **CodeConnections**: 콘솔에서 GitHub 연결 생성 → **OAuth 팝업 승인**(CLI 로는 승인 불가, 이 단계만 콘솔).
- **CodePipeline 마법사**: source→build→deploy 스테이지를 드래그로 구성. ECS/CodeDeploy 배포 액션 폼.
- **빌드 로그**: 실시간 스트리밍 + phase 별 성공/실패 표시.

## 참고 문서

- CodeBuild 사용 설명서: https://docs.aws.amazon.com/codebuild/latest/userguide/
- buildspec 레퍼런스: https://docs.aws.amazon.com/codebuild/latest/userguide/build-spec-ref.html
- CodePipeline: https://docs.aws.amazon.com/codepipeline/latest/userguide/
- Terraform `aws_codebuild_project`: https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/codebuild_project

## 함정

- **privilegedMode:true** — docker 빌드에 필수. 없으면 데몬 연결 실패.
- **role S3 소스 권한** — S3 소스면 `s3:GetObject` 필요. DOWNLOAD_SOURCE 403 의 원인.
- **CodeConnections 는 콘솔 OAuth 승인** 이 필요(CLI 로 생성만, 승인은 수동). 현장에서 GitHub 연동 시 이 단계.
- **ECR push 권한**: GetAuthorizationToken + layer 업로드 + PutImage 전부. 하나 빠지면 push 단계 실패.
- **imagedefinitions.json 의 container name** 은 ECS taskdef 의 name 과 정확히 일치.
- CodeBuild 첫 빌드는 이미지 provisioning 으로 조금 느림.

## 정리
```bash
aws codebuild delete-project --region $R --name lab-cb
aws ecr delete-repository --region $R --repository-name lab-cb-app --force
aws s3 rb s3://lab-cbsrc-$ACCT --force
aws iam delete-role-policy --role-name lab-cb-role --policy-name p; aws iam delete-role --role-name lab-cb-role
```
