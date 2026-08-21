# CodeBuild 이미지 빌드 → ECR (로컬 Docker 없이) — 실검증됨
`buildspec.yml` — NO_SOURCE 로 Dockerfile 즉석 생성 → build → ECR push. 지급 PC 에 Docker 안 깔고 이미지 만드는 길.
```bash
aws codebuild create-project --name cb --source '{"type":"NO_SOURCE","buildspec":"<buildspec.yml 내용>"}' \
  --artifacts '{"type":"NO_ARTIFACTS"}' \
  --environment 'type=LINUX_CONTAINER,image=aws/codebuild/amazonlinux2-x86_64-standard:5.0,computeType=BUILD_GENERAL1_SMALL,privilegedMode=true,environmentVariables=[{name=AWS_DEFAULT_REGION,value=ap-northeast-2},{name=ECR_URI,value=<acct>.dkr.ecr...}]' \
  --service-role <role>
aws codebuild start-build --project-name cb   # → SUCCEEDED, ECR 에 app:v1
```
★ privilegedMode:true 필수(docker 데몬). 인라인 buildspec 은 실제 개행 필요(JSON \n 이스케이프 시 YAML_FILE_ERROR — 실측). 전체 파이프라인은 ../01-codepipeline-ecs/.
