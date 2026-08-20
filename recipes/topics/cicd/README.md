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
| 01 | GHA → ECR → ECS 롤링 | build→push→update-service | `cases/01-gha-ecs/` |
| 02 | GHA → ArgoCD GitOps | manifest push → Argo sync | cncf/argocd |
| 03 | GHA OIDC 인증(키 없이) | assume-role-with-web-identity | `cases/03-oidc/` |
| 04 | CodeBuild 이미지 빌드(로컬 docker 없이) | buildspec | tier3/code-series ✓ |

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
- GitHub 연동은 **콘솔 OAuth 승인**(CodeConnections) 단계만 수동.

## context7 참고

- GitHub Actions OIDC: https://docs.github.com/actions/deployment/security-hardening-your-deployments/configuring-openid-connect-in-amazon-web-services
- `aws-actions/configure-aws-credentials`
- ArgoCD: `../../cncf/argocd/`
