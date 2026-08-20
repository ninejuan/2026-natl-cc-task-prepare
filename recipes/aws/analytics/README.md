# Data Analytics

Kinesis·Firehose·Athena·Glue·Managed Flink·MSK·OpenSearch. 2과제 Real-time analytics 모듈 + 로그 분석 파이프라인을 커버한다.

전부 실계정(`ap-northeast-2`)에서 검증. 요약은 `../../../verify/RESULTS.md`.

## 카드

| 파일 | 다루는 것 |
|---|---|
| `kinesis.md` | Data Streams(on-demand/샤드), **Firehose→S3 동적 파티셔닝**, →OpenSearch |
| `athena.md` | **partition projection**(crawler 없이), CTAS, workgroup |
| `glue/` | **Crawler**(스키마 자동발견), ETL Job(JSON→Parquet), 워크플로우 |
| `managed-flink/` | **Studio(Zeppelin) SQL** — TUMBLE/HOP/SESSION 윈도우. 프로그래밍 금지 대응 |
| `msk/` | Serverless 클러스터, IAM SASL, producer/consumer 코드 |

## ★ 검증된 파이프라인 (클릭스트림 적재+분석)

```
앱 → Kinesis Data Stream → Firehose → S3(events/dt=.../) → Athena SQL
                                        └ Glue Crawler → 카탈로그
```
전 구간 실동작 확인: Kinesis 발행 5건 → Firehose 동적 파티셔닝 → S3 적재 → Athena `click 5건` 집계 + Glue crawler 스키마 자동발견. `kinesis.md` + `athena.md` + `glue/` 조합.

## 실시간 분석 (Real-time analytics 모듈)

```
앱(ALB+EC2) → Kinesis/MSK → Managed Flink Studio (SQL 윈도우) → S3/Kinesis 싱크
```
가이드: "Flink 프로그래밍 금지, Notebook SQL only" → `managed-flink/notebook-kinesis-windows.sql`.

## 로그 분석 (logging 모듈)

```
ECS/앱 로그 → Firehose → OpenSearch → Dashboards
        또는 → S3 → Athena
```
`kinesis.md` 케이스 C(Firehose→OpenSearch).

## 이벤트 스트리밍 (MSK 모듈)

```
Producer(EC2) → MSK 토픽 → Lambda ESM / EC2 Consumer → DynamoDB/S3
```
`msk/` — VPC 내부 전용, IAM SASL 9098, SG self-inbound 필수.

## 생성 시간 (실측)

| 리소스 | 실측 |
|---|---|
| Kinesis Data Stream (on-demand) | 즉시~1분 |
| Firehose | 1~2분. **단 첫 배달은 버퍼(60초+) 대기** |
| Athena/Glue 카탈로그 | 즉시 (crawler 실행은 1~3분) |
| Managed Flink Studio | 생성 즉시, START→RUNNING 수 분 |
| **MSK Serverless** | **~15분 내 ACTIVE** (provisioned 25~35분보다 빠름) |
| OpenSearch 도메인 | 15~25분 (가장 느림) |

오래 걸리는 것(MSK·OpenSearch·Flink)은 문제 읽자마자 던지고 다른 항목을 하러 간다.

## 공통 함정

- **Firehose 즉시 배달 안 함** — 버퍼 조건까지 대기.
- **MSK/Flink 는 VPC 내부** — 클라이언트도 VPC 안에.
- **Glue DB = Athena DB** — 카탈로그 공유.
- zsh ARN 함정: `${VAR}:...` 중괄호.
