# FireLens → OpenSearch (Kibana/Dashboards 검색) — ✅ live 검증

02(FireLens→CloudWatch)와 인프라는 같고 **app 컨테이너의 output 플러그인만 `opensearch`** 로 바꾼다. "로그 저장 **및 검색**"(2025 #9) 요구 시 이 경로.

파일: `containerdef-opensearch.json`(컨테이너 정의) / `setup.sh`(도메인·VPC·클러스터·role) / `verify.sh`(taskdef 등록→run-task→인덱스 조회) / `teardown.sh` / `osquery.py`(SigV4 로 도메인 조회).

## 실검증 결과 (ap-northeast-2, 2026-08-21)

OpenSearch `lab-oslog`(OpenSearch_2.19, t3.small.search×1, gp3 10GB) + Fargate task(app + aws-for-fluent-bit 사이드카).

```
health status index      docs.count
yellow open   ecs-logs           8      ← Fluent Bit 이 만든 인덱스
```
`GET /ecs-logs*/_search` → **hits.total = 33**, 문서 실체:
```json
{ "@timestamp": "2026-08-21T08:33:44.058Z",
  "container_name": "app", "source": "stdout",
  "log": "{\"level\":\"INFO\",\"seq\":7,\"msg\":\"hello-opensearch\"}",
  "ecs_cluster": "lab-oslog-cluster",
  "ecs_task_arn": "arn:aws:ecs:ap-northeast-2:…:task/lab-oslog-cluster/a06f0c0a…",
  "ecs_task_definition": "lab-oslog:1" }
```
→ 앱 stdout → Fluent Bit → **OpenSearch 인덱싱까지 실제로 도달**했고, `enable-ecs-log-metadata:true` 가 붙인 `ecs_cluster`/`ecs_task_arn`/`ecs_task_definition`/`container_name` 이 문서에 그대로 들어간다(채점이 이 필드로 "어느 task 의 로그인지" 확인 가능).

## 접근정책 / 권한 (실측)

- 도메인 **access policy** 는 계정 root 프린시펄 허용 + **task role 에 `es:ESHttp*`**(도메인 `/*` 리소스) 조합이면 충분. FGAC(fine-grained access control) 없이 IAM 만으로 동작.
- Fluent Bit 이 `AWS_Auth On` + `AWS_Region` 으로 **SigV4 서명**해서 보낸다 → 도메인이 퍼블릭 엔드포인트여도 IAM 으로 잠긴다.
- 조회도 SigV4 가 필요하다. `osquery.py <endpoint> "/_cat/indices?v"` 처럼 botocore `SigV4Auth` 로 서명(브라우저 없이 채점 가능).

## 함정 (실측)

- **도메인 생성이 오래 걸린다 — 실측 ~50분**(t3.small.search 1노드). `Processing=True` 인 동안 `Endpoint` 는 `None`. 대회에선 미리 떠 있는 전제. `describe-domain-change-progress` 로 단계 확인.
- **`Type` 옵션은 빼라** — OpenSearch 2.x 는 매핑 타입이 없다. `Suppress_Type_Name: On` 만.
- **taskdef JSON 을 셸 heredoc 으로 조립하지 마라** — `$i`/`$((i+1))` 같은 앱 command 가 셸에 먹혀 JSON 이 깨진다(실측 `Invalid JSON received`). 템플릿 파일 + `sed` 로 엔드포인트만 치환할 것(`verify.sh` 방식).
- **execution role 에 `logs:CreateLogGroup`** — 사이드카가 `awslogs-create-group:true` 를 쓰면 기본 `AmazonECSTaskExecutionRolePolicy` 로는 부족(02 케이스와 동일).
- 인덱스는 Fluent Bit 이 만들며 기본 5샤드/1레플리카 → 단일 노드라 `yellow`(레플리카 미할당). 정상이다.
