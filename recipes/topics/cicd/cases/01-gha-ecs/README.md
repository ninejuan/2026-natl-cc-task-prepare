# GHA → ECR → ECS 롤링 배포 — ✅ **live E2E 검증** (실제 GitHub repo 로)

`deploy.yml`(워크플로) · `render_td.py`(taskdef 리비전 렌더) · `Dockerfile` · `app.py`.
2026-08-21, GitHub `ninejuan/lab-gha`(검증 후 삭제) + AWS `ap-northeast-1` 에서 **끝까지 돌렸다**.

## 검증 결과

| 단계 | 결과 |
|---|---|
| OIDC assume (`configure-aws-credentials@v4`) | ✅ `assumed-role/lab-gha-deploy` |
| ECR 로그인 + build & push | ✅ 이미지 태그 = `$GITHUB_SHA`, 44 MB |
| taskdef 새 리비전 등록 | ✅ `lab-gha:1` → **`lab-gha:2`** (image 가 ECR URI 로 교체됨) |
| ECS 롤링 배포 | ✅ 서비스가 `:2` 로 전환, `rolloutState=COMPLETED` |
| 앱 실제 응답 | ✅ `curl http://<task-ip>:8080/` → **`lab-gha v1`** (GHA 가 빌드한 이미지) |

## 흐름

```
push(main) ─▶ GHA ubuntu-latest
                ├─ OIDC 토큰 → sts:AssumeRoleWithWebIdentity → gha-deploy role  (장기 키 0개)
                ├─ docker build/push → ECR:<git-sha>
                ├─ describe-task-definition → image 만 교체 → register-task-definition (새 리비전)
                └─ update-service --task-definition FAMILY:REV → wait services-stable
```

## ★ 이 카드의 예전 버전이 틀렸던 곳 (실행해서 알아낸 것)

**`--force-new-deployment` 로는 새 이미지가 배포되지 않는다.**
그건 *같은 taskdef* 로 태스크만 다시 띄우는 것이다. 이미지 태그를 git SHA 로 올렸다면
taskdef 의 `image` 가 그대로라 **옛 이미지가 다시 뜬다**(태그가 `latest` 일 때만 우연히 동작).
→ `describe-task-definition` → image 교체 → `register-task-definition` → `update-service --task-definition` 이 맞다.

**`register-task-definition` 은 describe 응답을 그대로 못 받는다.**
`taskDefinitionArn / revision / status / requiresAttributes / compatibilities / registeredAt / registeredBy / deregisteredAt`
를 제거해야 한다. `render_td.py` 가 그 일을 한다.

## ★ OIDC 가 막히면 → `../03-oidc/README.md` 를 먼저 봐라

`Not authorized to perform sts:AssumeRoleWithWebIdentity` 로 2분 재시도 후 죽는 경우가 있는데,
원인은 **`sub` 클레임에 불변 ID(`OWNER@123/REPO@456`)가 들어가서** 옛 형식 `StringEquals` 가 안 맞는 것이다.
이번 검증에서도 이것 때문에 첫 두 번의 실행이 실패했고, trust 를 `StringLike`+와일드카드로 바꾸자 바로 통과했다.

## 필요한 IAM (실검증한 최소권한)

- **배포 role(`gha-deploy`)**: `ecr:GetAuthorizationToken`(Resource `*`) + 대상 repo 에 대한 ECR push/pull 액션 +
  `ecs:RegisterTaskDefinition/DescribeTaskDefinition/DescribeServices/UpdateService` + **`iam:PassRole`**(taskdef 의 execution/task role 대상).
  `PassRole` 을 빼면 `register-task-definition` 이 거부된다.
- **워크플로 권한**: `permissions: {id-token: write, contents: read}`.

## 함정

- **정책 JSON 을 셸 heredoc 으로 만들 때 `$ACCT:role/...` 쓰지 마라** — zsh 가 `:r` 을 modifier 로 먹어
  ARN 이 깨지고 `MalformedPolicyDocument: The policy failed legacy parsing` 이 난다(이번에도 발생). **`${ACCT}`** 로.
- 첫 배포는 **부트스트랩 taskdef**(퍼블릭 이미지)로 서비스를 먼저 띄워두면 깔끔하다. ECR 이 비어 있는 상태에서
  서비스를 만들면 태스크가 계속 실패한다.
- `aws ecs wait services-stable` 은 **구 태스크 드레이닝까지** 기다려 수 분 걸린다. 채점 3분 제약이면 대기를 줄이거나
  `describe-services` 로 `rolloutState` 만 확인.
- ECR 이미지 태그는 `$GITHUB_SHA` 로. `latest` 만 쓰면 롤백·이력 추적이 안 된다.
- GHA 대신 AWS 네이티브가 필요하면 `../01-codepipeline-ecs/`(CodeCommit→CodeBuild→ECS, 역시 live E2E).
