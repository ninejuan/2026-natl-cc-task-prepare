# ECS 중앙집중 로깅 플레이북 (2025 #9)

**가이드 원문(2025 #9)** — "ECS Task 로그를 한 곳에서 확인하는 중앙 집중 로깅. Python 앱으로 로그 발생(배포파일). 로그 드라이버 **awslogs, firelens** 활용. 저장/검색은 **OpenSearch/Kibana, CloudWatch**."
- 필수: ECS / 선택: CloudWatch, OpenSearch/Kibana

**트리거 문구** — "ECS 로그 중앙 수집", "FireLens", "awslogs", "여러 컨테이너 로그 한 곳에", "OpenSearch 로 로그".

**리전 격리** — 전용. 예시 `ap-northeast-2`.

**기반 카드**: ECS 태스크 정의(FireLens 사이드카·awslogs) `../../aws/tier2/ecs/taskdefs/`(6종 register 검증), ECS 카드 `../../aws/tier2/ecs.md`, Logs Insights 쿼리 `../../aws/tier3/cloudwatch/logs-insights.md`.

---

## 로그 경로 3종

| 드라이버 | 목적지 | 언제 |
|---|---|---|
| **awslogs** | CloudWatch Logs (단순 직결) | 기본. 컨테이너 stdout → CW 로그그룹 |
| **awsfirelens** + Fluent Bit | CloudWatch / OpenSearch / S3 (가공·분기) | 파싱·필터·다중 목적지 |
| firelens → OpenSearch | Kibana 로 검색·대시보드 | "검색" 요구 시 |

## 케이스 인덱스

| # | 케이스 | 경로 | 기반 |
|---|---|---|---|
| 01 | awslogs → CloudWatch | `cases/01-awslogs/` (tier2 register 실검증) | ✓ |
| 02 | FireLens → CloudWatch | `taskdefs/firelens-sidecar.json` | ✅ live(앱 JSON 로그 → Fluent Bit → CW, ecs_task_arn 메타 부착 실측) |
| 03 | FireLens → OpenSearch | `cases/03-firelens-opensearch/` | ✅ **live**(앱 stdout → Fluent Bit → `ecs-logs` 인덱스 33건, ecs 메타 포함) |
| 04 | FireLens → S3 (아카이브) | `cases/04-firelens-s3/` | ✅ live(앱 로그 → S3 객체 도착, ecs 메타 포함) |

## 검증 (채점자 문체)

```bash
# task 가 로그를 실제로 보냈는지
aws logs describe-log-streams --region $R --log-group-name /ecs/app \
  --query 'logStreams[].logStreamName' --output text
aws logs filter-log-events --region $R --log-group-name /ecs/app --limit 5 \
  --query 'events[].message' --output text
# OpenSearch 경로면 도메인 상태 + 인덱스
aws opensearch describe-domain --region $R --domain-name lab-logs --query 'DomainStatus.Processing' --output text
```

## 함정

- **FireLens 는 log-router 사이드카가 essential** — 아니면 앱만 죽어도 로그 유실.
- **task role vs execution role** — 앱이 로그를 보내는 게 아니라 로그드라이버(execution)가. OpenSearch 로 보내면 task role 에 `es:ESHttp*`.
- **★ 사이드카(log-router)의 `awslogs` 드라이버 + `awslogs-create-group:true` 는 execution role 로 실행**(실측) — 기본 `AmazonECSTaskExecutionRolePolicy` 엔 `logs:CreateLogGroup` 이 없어서 task 가 `ResourceInitializationError ... AccessDeniedException: logs:CreateLogGroup` 로 STOPPED 된다. 해결: 로그그룹을 미리 만들거나 execution role 에 `logs:CreateLogGroup` 추가.
- **★ FireLens 앱 로그의 CloudWatch 출력은 task role** 이 담당(cloudwatch output). task role 에 `logs:CreateLogGroup/Stream/PutLogEvents` 필요.
- **`enable-ecs-log-metadata:true`** → 로그에 `ecs_cluster`/`ecs_task_arn`/`container_name` 자동 부착(실측 확인).
- **awslogs 는 로그그룹 사전 생성** 또는 `awslogs-create-group=true`.
- **OpenSearch 도메인 생성 실측 ~50분**(t3.small.search 1노드, 가이드상 "~15분"보다 훨씬 오래) + 시간과금. `Processing=True` 동안 `Endpoint` 는 `None`. 채점은 미리 떠 있는 전제.
- **OpenSearch 출력에 `Type` 옵션 쓰지 말 것**(2.x 는 매핑 타입 없음) — `Suppress_Type_Name: On` 만. 도메인 조회도 SigV4 서명 필요(`cases/03-firelens-opensearch/osquery.py`).
- **taskdef JSON 을 셸 heredoc 으로 만들지 말 것**(실측) — 앱 command 의 `$i`/`$((i+1))` 가 셸에 치환돼 JSON 이 깨진다. 템플릿+`sed` 치환.
- Logs Insights 쿼리는 `../../aws/tier3/cloudwatch/logs-insights.md` 15종 재사용.

## context7 참고

- FireLens: https://docs.aws.amazon.com/AmazonECS/latest/developerguide/using_firelens.html
- `aws_opensearch_domain` (TF AWS v6)
