# Tier 2 — 조립 블록 + 1과제 심화

여러 모듈·항목에서 재사용되는 핵심 서비스. 전부 실계정 검증.

| 카드 | 다루는 것 | 검증 |
|---|---|---|
| `dynamodb.md` | GSI/LSI/TTL/Stream/PITR/트랜잭션/조건부/복원/DAX/Global | ✓ |
| `s3.md` | 버전관리/SSE-KMS/라이프사이클/Access Point/정적호스팅/정책 | ✓ |
| `ecr.md` | 스캔/태그불변/라이프사이클/CMK/pull-through | ✓ (정책, push 제외) |
| `ecs.md` | Fargate/taskdef/service/**CloudMap**/ALB/FireLens/Exec | ✓ (task RUNNING+CloudMap) |
| `waf.md` | managed rule/rate limit/custom403/IP set/geo/로깅 | ✓ (WebACL+rules) |

## 공통
- **CloudFront 에 붙는 것(WAF)은 us-east-1**, 나머지는 리전.
- ECR/ECS 이미지: CloudShell 1GB 한계 → 지급 PC Docker 또는 CodeBuild(`../tier3/code-series/`).
- 버전관리 S3 삭제: 버전+삭제마커 먼저 제거해야 `rb` 됨.
