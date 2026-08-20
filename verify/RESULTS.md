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

## 미검증 / 확인 필요

- `bin/bootstrap.sh` 를 CloudShell(bash 5, Amazon Linux 2023)에서 실제 실행
- `lambda/image-resize` (Pillow 네이티브 의존성 — 실배포 시 아키텍처 wheel 확인 필요)
- `apigateway/vtl/sns-publish-req`, `validate-transform-req` (문법만, 실 API 미검증)
- `glue/etl_json_to_parquet.py` (Spark job 실행 — DPU 비용), `managed-flink` SQL 노트북(Zeppelin UI), `msk` produce/consume (VPC 내 EC2)
- k8s/cncf 매니페스트 (오프라인 문법만)
