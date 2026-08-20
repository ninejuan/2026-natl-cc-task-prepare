# CI/CD 플레이북 (2025 #4)

**가이드 원문(2025 #4)** — "EC2/컨테이너에 앱 배포 CI/CD 파이프라인. 웹서버는 Python 앱/HTML(nginx), 코드 제공. ★ **하나의 채점항목 5분 초과 불가** → 배포 시간 고려."
- 필수: **GitHub, GitHub Action** / 선택: ArgoCD, EC2, ECS, EKS, ECR, ELB

**트리거 문구** — "CI/CD 파이프라인", "GitHub Actions 로 배포", "ArgoCD GitOps", "이미지 빌드→배포", "자동 배포".

**리전 격리** — 전용. 예시 `ap-northeast-2`.

**기반 카드**: AWS 네이티브 CI/CD·CodeBuild `../../aws/tier3/code-series/`(실검증), ArgoCD `../../cncf/argocd/`, ECR `../../aws/tier2/ecr.md`, ECS `../../aws/tier2/ecs.md`.

> ★ 필수가 **GitHub + GitHub Actions** 다(AWS Code 시리즈 아님). GHA 워크플로가 중심, AWS 는 배포 타깃.

---

## 케이스 인덱스

| # | 케이스 | 흐름 | 검증 |
|---|---|---|---|
| 01 | GHA → ECR → ECS 롤링 | build→push→update-service | `cases/01-gha-ecs/` (GHA 실행은 GitHub repo 필요) |
| 01b | **CodePipeline: CodeCommit → CodeBuild → ECS** | 3-스테이지 완전 자동 | ✅ **live E2E** `cases/01-codepipeline-ecs/`(Source/Build/Deploy 전부 Succeeded, ECS taskdef :1→:2) |
| 02 | GHA → ArgoCD GitOps | manifest push → Argo sync | cncf/argocd |
| 03 | GHA OIDC 인증(키 없이) | assume-role-with-web-identity | ✅ live(OIDC provider + role trust sub=repo:.../main 실측) |
| 04 | CodeBuild 이미지 빌드(로컬 docker 없이) | buildspec | ✅ live(NO_SOURCE 빌드→ECR push v1, SUCCEEDED) — GHA→ECR 절반과 동일 산출 |

## AWS 네이티브 CodePipeline (CodeCommit → CodeBuild → ECS) [live E2E 검증]

GHA 대신(또는 GitHub 접근 불가 시) AWS 네이티브로 완전한 3-스테이지 파이프라인. **CodeCommit 재출시**로 source 저장소까지 AWS 안에서 완결. 실검증(ap-northeast-2): 파이프라인 생성 자동 트리거 → 세 스테이지 전부 Succeeded, ECS 서비스가 새 이미지로 롤링(taskdef :1→:2).

```bash
# 1) CodeCommit repo + 소스(put-file 로 git 없이 시드 가능)
aws codecommit create-repository --repository-name app
aws codecommit put-file --repository-name app --branch-name main --file-path buildspec.yml --file-content fileb://buildspec.yml --commit-message init
# 2) CodeBuild 프로젝트: source/artifacts type=CODEPIPELINE, privilegedMode=true(docker build)
# 3) ECS 클러스터+서비스(배포 타깃), ECR
# 4) CodePipeline: Source(CodeCommit main) → Build(CodeBuild) → Deploy(ECS, imagedefinitions.json)
aws codepipeline create-pipeline --cli-input-json file://pipeline.json   # 생성 즉시 실행
aws codepipeline get-pipeline-state --name app-pipe --query 'stageStates[].[stageName,latestExecution.status]' --output text
```
- **Deploy(ECS) 액션**은 Build 아티팩트의 `imagedefinitions.json`(`[{"name":"<container>","imageUri":"<ecr>:<tag>"}]`)을 읽어 롤링. container name = taskdef name 정확히.
- **CodeCommit 재출시**: 2024년 신규계정 차단됐다가 재개 — `create-repository` 로 확인(실측 됨). git 없이 `put-file` API 로 시드 가능.
- buildspec 의 `post_build` 에서 imagedefinitions.json 생성 → `artifacts.files` 에 포함.

## GHA OIDC (장기 키 없이 — 권장)

```yaml
# .github/workflows/deploy.yml
permissions:
  id-token: write   # OIDC 토큰
  contents: read
jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: arn:aws:iam::ACCT:role/gha-deploy
          aws-region: ap-northeast-2
      - run: |   # ECR push + ECS 롤링
          aws ecr get-login-password | docker login --username AWS --password-stdin $ECR
          docker build -t $ECR/app:$GITHUB_SHA . && docker push $ECR/app:$GITHUB_SHA
          aws ecs update-service --cluster c --service s --force-new-deployment
```
IAM trust: `token.actions.githubusercontent.com:sub = repo:OWNER/REPO:ref:refs/heads/main` (→ `../../aws/tier3/iam/policy-documents.md` OIDC 예시).

## 검증 (채점자 문체)

```bash
# 배포 결과가 실제로 반영됐는지 (5분 내)
aws ecs describe-services --region $R --cluster lab --services app \
  --query 'services[0].deployments[0].rolloutState' --output text   # COMPLETED
aws ecr describe-images --region $R --repository-name app --query 'imageDetails[].imageTags[]' --output text
curl -s "http://$ALB/" | grep -q "v2" && echo "새 버전 배포 확인"
# ArgoCD: kubectl get application -n argocd -o jsonpath synced/healthy
```

## 함정

- **5분 제약**(가이드) — 배포 시간 설정 주의. ECS 롤링은 health check grace + min healthy % 로 빠르게. GHA runner 시작+빌드+배포가 5분 안에.
- **GHA OIDC 가 장기 키보다 안전** — `aws-actions/configure-aws-credentials` + IAM OIDC provider.
- **imagedefinitions.json container name = taskdef name** 정확히.
- **ArgoCD sync** — auto-sync 아니면 수동 sync. 채점이 sync 상태 확인.
- CodeBuild 이미지 빌드는 `privilegedMode:true` + S3 소스 권한(→ code-series 실검증 함정).
- **★ 인라인 buildspec(NO_SOURCE) YAML 주의**(실측) — JSON 안에 `\n` 이스케이프로 buildspec 을 욱여넣으면 `YAML_FILE_ERROR: could not find expected ':'` 로 DOWNLOAD_SOURCE 단계 실패. buildspec 은 실제 개행이 든 문자열로(파일로 만들어 넣거나 update-project 로). NO_SOURCE + privilegedMode:true 로 로컬 Docker 없이 build→ECR push 실검증됨.
- GitHub 연동은 **콘솔 OAuth 승인**(CodeConnections) 단계만 수동.

## context7 참고

- GitHub Actions OIDC: https://docs.github.com/actions/deployment/security-hardening-your-deployments/configuring-openid-connect-in-amazon-web-services
- `aws-actions/configure-aws-credentials`
- ArgoCD: `../../cncf/argocd/`
