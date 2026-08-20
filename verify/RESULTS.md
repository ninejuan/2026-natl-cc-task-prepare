# 실검증 기록

계정 `156041424727`. 카드/스크립트를 실제로 돌린 결과만 적는다. 추정치는 적지 않는다.

> 주의: 이 계정에는 task3 연습 인프라(`apdev-*`, EKS `apdev-eks` 1.35)가 살아 있다. 검증용 리소스는 이름을 겹치지 않게 만들고, 남의 것을 지우지 않는다.

| 대상 | 리전 | 결과 | 소요 | 비용 | 비고 |
|---|---|---|---|---|---|
| `bin/discover.sh` | ap-northeast-2 | ✓ | ~20s | $0 | 41개 변수 추출. VPC/서브넷/SG/RT/EKS(+OIDC·버전·NG)/ALB·TG/CF/DDB/S3/Lambda/ECR/KMS/EC2 확인 |
| `bin/mark-self.sh --foul` | ap-northeast-2 | ✓ | 5.5s | $0 | 최초 120s+ → IAM 정책 조회 `xargs -P8` 병렬화로 5.5s. `Resource:"*"` 오탐 제거(Action/Principal만 검사) |
| `bin/build-all.sh` | — | ✓ | 즉시 | $0 | 카드 0개 상태 정상 종료 확인. bash 3.2 호환(mapfile 제거) |
| `bin/bootstrap.sh` | — | 부분 | — | $0 | macOS에서 실행 불가(Linux 바이너리). 다운로드 URL 6종 HTTP 200 확인, kustomize는 404라 제거(kubectl -k 사용). **CloudShell 실행 검증 필요** |

## recipes/aws/serverless — 실계정 배포·호출 검증

| 대상 | 결과 | 비고 |
|---|---|---|
| `lambda.md` zip 생성·invoke·env | ✓ | python3.13, query/env 정상 반환 |
| `lambda.md` Function URL (auth NONE) | ⚠️ | URL 발급은 정상이나 **org SCP 로 403**. 카드에 함정 기록. AWS_IAM/ALB/APIGW 로 우회 |
| `lambda.md` ESM(SQS) | ✓ | 메시지 2건 발행→소비, 큐 잔량 0 |
| `scripts/deploy-lambda.sh` | ✓ | 생성/갱신 멱등, invoke 로 코드 반영 확인 |
| `lambda/crud-booking` | ✓ | POST 저장·GET booking_id·**GSI client_id 2건**·검증 400·health 200 |
| `lambda/sqs-batch` | ✓ | ESM + **ReportBatchItemFailures**: 정상 2건 저장, broken 1건만 재시도(NotVisible) |
| `lambda/ddb-stream` `_deser` | ✓ | 단위테스트 (S/N/BOOL 변환) |
| 핸들러 8종 구문 | ✓ | `py_compile` 전부 통과 |
| `apigateway.md` A(DDB 직접통합+VTL) | ✓ | `1000`/`100` raw 출력, `mysecret*`→403. 2025 inventory 재현 |
| `apigateway/vtl/ddb-query-json-res` | ✓ | Query→JSON 배열 변환(`#foreach`+콤마) 실 API 확인 |
| `apigateway/vtl/sfn-start-req` | ✓ | API→SFN StartExecution, executionArn 200 |
| `stepfunctions/inventory-ddb` | ✓ | 실행 SUCCEEDED, stock 80·balance 1020 (SDK 직접통합) |
| `stepfunctions/map-parallel` | ✓ | Map 2항목 저장 + Parallel 2브랜치 결과 |
| `stepfunctions/` 나머지 3종 | ✓ | `validate-state-machine-definition` OK |
| `eventbridge.md` Scheduler | ✓ | rate(5min) 스케줄 ENABLED |
| `eventbridge.md` Pipes(SQS→SNS) | ✓ | 필터 포함 RUNNING |
| `sqs-sns.md` FIFO·DLQ·filter policy | ✓ | FIFO 순서 보장, redrive policy, SNS filter 확인 |

모든 lab 리소스 삭제 완료(함수·큐·API·SM·테이블·역할). 잔여 0.

### 발견한 함정 (카드에 반영됨)
- **zsh ARN modifier**: `"$VAR:영문자"` 가 `:r`/`:s` 로 잘림. `${VAR}:...` 또는 조회로 받기. 반복 발생 → 전 카드 공통 경고.
- **Function URL SCP 403**: org 계정에서 auth NONE 차단 가능.
- **DDB 키 스키마 불일치**: 핸들러 PK(`pk`)와 테이블 PK(`booking_id`) 다르면 PutItem 이 조용히 실패(ESM 은 NotVisible 로 쌓임).

## recipes/aws/analytics — 실계정 검증

| 대상 | 결과 | 비고 |
|---|---|---|
| `kinesis.md` Data Stream (on-demand) | ✓ | ACTIVE, put/get-record |
| `kinesis.md` Firehose→S3 동적 파티셔닝 | ✓ | `events/dt=2026-08-20/` 파티션 적재. **키명 `DynamicPartitioningConfiguration`** |
| `athena.md` partition projection | ✓ | crawler 없이 CREATE TABLE → click 5건 집계 SUCCEEDED |
| `glue/` Crawler | ✓ | S3 JSON 스캔 → 스키마(event_type/id)+파티션(dt) 자동발견, SUCCEEDED |
| `glue/etl_json_to_parquet.py` | 문서 | 스크립트 제공(구문). job 실행은 DPU 비용 커서 미실행 |
| `managed-flink/` Studio | ✓ | RUNNING, ZEPPELIN-FLINK-3_0, Glue 카탈로그 연결 확인 |
| `managed-flink/notebook-*.sql` | 문서 | SQL 노트북 예제(Zeppelin UI 실행 필요, CLI 불가) |
| `msk/` Serverless 클러스터 | ✓ | **~15분 내 ACTIVE**(provisioned보다 빠름), IAM SASL 부트스트랩 9098 확인 |
| `msk/producer.py·consumer.py` | 문서 | IAM 인증 코드. produce/consume 은 VPC 내 EC2 필요(미실행) |

**검증된 파이프라인**: Kinesis→Firehose→S3→Athena 전 구간(click 5건) + Glue crawler 스키마 자동발견.
모든 analytics lab 삭제 완료(IAM 잔여 0, MSK DELETING).

### 발견한 함정 (카드 반영)
- Firehose `DynamicPartitioning` → `DynamicPartitioningConfiguration` (CLI 검증 에러).
- Firehose 는 즉시 배달 안 함 — 동적 파티셔닝 시 버퍼 최소 60초.
- MSK/Flink VPC 내부 전용, MSK SG self-inbound 9098 필수.

## analytics 보강분 추가 실검증 (2차)

| 대상 | 결과 | 비고 |
|---|---|---|
| `kinesis/transform-lambda.py` | ✓ | Firehose 이벤트로 invoke: CLICK→click 정규화·dt보강·Ok / value없음 Dropped |
| `kinesis/firehose-parquet-conf.json` | ✓ | Direct PUT + Lambda transform + Parquet 변환 → S3 .parquet → Athena 재쿼리(click 3/sum 60) |
| `glue/etl_aggregate_join.py` | ✓ | Glue job SUCCEEDED, events+users 조인·집계 → Parquet (premium/click 2/30, basic/view 1/5) |
| `msk/admin.py` | ✓ | 토픽 orders 6파티션 생성·list (VPC EC2 + IAM SASL) |
| `msk/producer.py` · `consumer.py` | ✓ | 10건 발행 → 10건 소비 왕복 (IAM SASL 9098) |
| athena `queries/*.sql` | ✓ | (1차) DDL·집계·윈도우·CTAS·UNLOAD |
| `kinesis/producer.py` | ✓ | (1차) 실 스트림 15건 발행 |

### MSK IAM 인증 — 실검증 중 발견한 버그 2개 (코드·카드 수정 완료)
1. `kafka.sasl.oauth.AbstractTokenProvider` import 실패 → kafka-python-ng 2.2+ 는
   `sasl_mechanism="AWS_MSK_IAM"` 내장(`kafka/sasl/msk.py`). `aws-msk-iam-sasl-signer`
   불필요, botocore 만 필요. producer/consumer/admin 3개 전면 수정.
2. botocore `region: None` → `NoBrokersAvailable`. `AWS_DEFAULT_REGION` 명시 필요.
- Glue Parquet 타입 함정: SUM(int)→INT64 라 Athena 테이블 스키마를 double 로 잡으면 HIVE_BAD_DATA.

## recipes/aws/tier1 — 실계정 검증

| 대상 | 결과 | 비고 |
|---|---|---|
| `route53.md` split-view | ✓ | public zone q1→54.0.0.10(권위서버 dig), private zone q1→172.16.0.10(API). 2024 DNS 재현 |
| `route53.md` 라우팅정책 | ✓ | weighted·failover(+health check)·latency·geolocation 4종 생성 |
| `cloudfront.md` OAC | ✓ | 배포 Deployed(실측 ~2분), CF 200 "Cloud Skills 2026", **S3 직접 403**. 2024 CDN 재현 |
| `cloudfront/functions/viewer-request` | ✓ | test-function: /old→/index.html 리라이트 |
| `cloudfront/functions/viewer-response-headers` | ✓ | test-function: x-custom-marker 헤더 추가 |
| `acm.md` DNS 검증 발급 | ✓ | us-east-1 request-certificate, PENDING_VALIDATION 확인 |

tier1 lab 정리: Route53 zone/HC 삭제 완료. CloudFront 는 disable→반영 대기 후 삭제 예정(S3 포함).

## recipes/aws/tier2 — 실계정 검증

| 대상 | 결과 | 비고 |
|---|---|---|
| dynamodb GSI+LSI+Stream+TTL | ✓ | 한 테이블에 다 구성 |
| dynamodb PITR·트랜잭션·조건부·GSI/LSI 쿼리 | ✓ | PITR ENABLED(재시도), transact-write, ConditionalCheckFailed 차단, GSI/LSI query |
| s3 버전관리·SSE-KMS·라이프사이클 | ✓ | 2버전, aws:kms, expire 룰 |
| s3 Access Point·정적호스팅 | ✓ | AP 객체접근(v2), 웹호스팅 "Cloud Skills 2026" |
| ecr 스캔·태그불변·라이프사이클 | ✓ | IMMUTABLE·scanOnPush·2룰 (push 제외) |
| ecs Fargate+CloudMap | ✓ | task RUNNING, CloudMap task IP 자동등록(10.0.139.110), awslogs 스트림 |
| waf managed+rate+custom403 | ✓ | WebACL REGIONAL + 3룰 생성 |

tier2 lab 전량 정리(DDB·S3 버전버킷·ECS·CloudMap·WAF·역할). 
S3 버전관리 버킷은 버전+삭제마커 제거 후 rb (카드 정리 절차 반영).

## recipes/aws/tier3 — 실계정 검증

| 대상 | 결과 | 비고 |
|---|---|---|
| code-series CodeBuild | ✓ | S3소스→docker build→ECR push v1. 로컬 Docker 없이. DOWNLOAD_SOURCE 403·privilegedMode 함정 발견 |
| efs 파일시스템+AP+정책 | ✓ | available, access point(/app POSIX1000), fs policy |
| config-ssm Parameter Store | ✓ | String/SecureString(복호화)/StringList/경로조회 |
| cloudwatch 대시보드·알람·metric filter | ✓ | dashboard, alarm(INSUFFICIENT_DATA), metric filter |
| secretsmanager 시크릿·정책 | ✓ | 시크릿 조회, resource policy |
| backup vault·plan | ✓ | vault, plan(cron 0 5) |
| cloudmap | ✓ | (tier2 ECS 연동에서 task IP 자동등록 검증) |
| mq RabbitMQ 브로커 | ✓ | RUNNING(m7g.large, t3.micro 미지원), amqps 5671 |
| iam-federation Assume+ExternalID | ✓ | 올바른 ID assume 성공, 없거나틀리면 AccessDenied |

tier3 lab 전량 정리.
- ⚠️ Flink Studio(analytics 검증 때 생성)가 삭제 실패로 READY 로 수 시간 잔존 → 최종 스캔에서 발견·재삭제. **삭제 요청 후 상태 재확인 필요**(delete-application 이 조용히 실패할 수 있음).

## 예제 컬렉션 보강 (tier1/2/3, Athena.md 식 다양한 use-case)

| 컬렉션 | 상태 | 검증 방식 / 발견 |
|---|---|---|
| tier2/dynamodb/partiql.sql (15종) | ✓ | `execute-statement` 15개 실행. 카운터 1000→900→400, 조건부 amount<500 정확히 ConditionalCheckFailed |
| tier2/s3/bucket-policies.md (13종) | ✓ | 정책 문법(기존 s3.md apply 로 대표 검증). 복붙용 패턴 |
| tier2/waf/rule-statements.json (12종) | ✓ | 12종 전부 한 WebACL 에 넣어 `create-web-acl` 통과. **CLI ByteMatch SearchString 은 base64 필수**(평문이면 "Invalid base64") |
| tier1/route53/record-sets.md | ✓ | 레코드 JSON 문법(기존 route53 apply 로 대표 검증) |
| tier3/cloudwatch/logs-insights.md (15종) | ✓ | `start-query`→`get-query-results` 14개 실행. error_pct=40, distinct=3, pct/avg 정확 |
| tier3/iam/policy-documents.md | ✓ | identity 13종 Access Analyzer 통과, trust 9종 실제 `create-role` 통과 |
| tier1/cloudfront/functions/ (7종) | ✓ | 전부 `test-function` 실행 검증. **querystring 재할당은 키 순서 못 바꿈**(정렬 no-op) → utm 삭제로 수정 |

전량 정리 확인(DDB 테이블·로그그룹·WebACL·IPSet·test role·CFF 함수 0개 잔존).

## 발견 함정 총정리 (전 카드 반영)
- **zsh ARN modifier**: `"$VAR:영문자"` → `:r`/`:s`/`:l` 로 잘림. `${VAR}:...` 중괄호 또는 조회. heredoc 안에서도 발생.
- Firehose `DynamicPartitioningConfiguration`(not `DynamicPartitioning`).
- MSK: kafka-python-ng 2.2+ AWS_MSK_IAM 내장, botocore `AWS_DEFAULT_REGION` 필요, SG self-inbound 9098.
- Lambda Function URL SCP 403(org 계정).
- CodeBuild: S3 소스 권한, privilegedMode:true.
- RabbitMQ t3.micro 미지원. Glue Parquet SUM(int)=INT64.
- 삭제 요청 후 재확인(Flink delete 조용히 실패).

## 미검증 / 확인 필요

- `bin/bootstrap.sh` 를 CloudShell(bash 5, Amazon Linux 2023)에서 실제 실행
- `lambda/image-resize` (Pillow 네이티브 의존성 — 실배포 시 아키텍처 wheel 확인 필요)
- `apigateway/vtl/sns-publish-req`, `validate-transform-req` (문법만, 실 API 미검증)
- `managed-flink` SQL 노트북 (Zeppelin UI 기반 — CLI 자동화 불가. Studio RUNNING 은 확인, SQL 실행은 브라우저 필요)
- k8s/cncf 매니페스트 (오프라인 문법만)
