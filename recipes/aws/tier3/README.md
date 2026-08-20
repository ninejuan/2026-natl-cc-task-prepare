# Tier 3 — 신규 추가 서비스

가이드 밖이지만 나올 수 있는 서비스 + 사용자 지정 항목. 전부 실계정 검증.

| 카드 | 다루는 것 | 검증 |
|---|---|---|
| `code-series/` | CodeBuild 로 로컬 Docker 없이 ECR 빌드, CodePipeline/Deploy | ✓ build→push v1 |
| `cloudmap.md` | 서비스 디스커버리 (private/public/http ns) | ✓ (ECS 연동분) |
| `efs.md` | 파일시스템·access point·IAM 접근제어·마운트 | ✓ |
| `mq/` | Amazon MQ RabbitMQ/ActiveMQ + pika 클라이언트 | ✓ RUNNING |
| `iam-federation.md` | Assume+ExternalID, SAML(Keycloak), IdC, OIDC | ✓ ExternalID assume |
| `config-ssm.md` | Parameter Store, governance 자동복구, Run Command | ✓ Parameter Store |
| `cloudwatch.md` | 대시보드·알람·metric filter·Log Insights·EMF | ✓ |
| `secretsmanager.md` | 시크릿·회전·resource policy | ✓ |
| `backup.md` | vault·plan·복원 | ✓ vault/plan |

## 핵심 포인트
- **code-series/**: 지급 PC Docker Desktop(WSL2 재부팅) 회피 = CodeBuild 로 이미지 빌드.
- **iam-federation**: 단일 계정 SSO 는 SAML(Keycloak), 다계정·중앙관리는 IdC.
- **governance**: Config(느림)보다 EventBridge+Lambda(3분 채점에 유리).
