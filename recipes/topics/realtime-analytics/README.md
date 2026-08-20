# Real-time Analytics 플레이북 (2025 #5 / 2026 #4)

**가이드 원문** — "앱 로그 기반 실시간 데이터 분석. 로그 발생용 **Python 앱(배포파일)**, 서비스 환경 **ALB + EC2**. 분석은 **Managed Service for Apache Flink**. ★ Flink 앱 **프로그래밍 금지**, **Notebook(Zeppelin)에서 SQL** 로만."
- 필수: VPC, EC2, ELB, Managed Flink / 선택: X

**트리거 문구** — "실시간 분석", "Flink", "Zeppelin 노트북 SQL", "스트리밍 집계", "윈도우 쿼리".

**리전 격리** — 전용. 예시 `ap-northeast-2`.

**기반 카드**: Flink Studio 노트북 SQL 4종 `../../aws/analytics/managed-flink/`, Kinesis 프로듀서 `../../aws/analytics/kinesis/`, MSK 소스 `../../aws/analytics/msk/`.

---

## ★ 핵심 제약: SQL only (프로그래밍 금지)

- **Managed Service for Apache Flink Studio**(Zeppelin) 노트북에서 **Flink SQL** 로만.
- Java/Python Flink 앱(JAR) 금지. `%flink.ssql` 문단에 SQL.

## 케이스 인덱스 (노트북 SQL 4종 기반)

| # | 케이스 | SQL 패턴 | 기반 |
|---|---|---|---|
| 01 | Kinesis 소스 + 텀블링 윈도우 | TUMBLE 집계 | `notebook-kinesis-windows.sql` |
| 02 | MSK 소스 | Kafka connector | `notebook-msk-source.sql` |
| 03 | TopN + 스트림 조인 | ROW_NUMBER OVER | `notebook-topn-join.sql` |
| 04 | 이상 탐지 → S3 sink | 임계 필터 + S3 | `notebook-anomaly-s3sink.sql` |
| 05 | 세션/슬라이딩 윈도우 | SESSION/HOP | `cases/05-window-variants/` |

## 로그 발생 파이프라인

```
Python 앱(EC2, ALB 뒤) ──로그──> Kinesis Data Stream ──> Managed Flink Studio(Zeppelin SQL)
                                                              └─ 집계/이상탐지 → S3/출력
```

## 윈도우 종류 (Flink SQL)

| 윈도우 | 문법 | 용도 |
|---|---|---|
| Tumbling | `TUMBLE(TABLE t, DESCRIPTOR(ts), INTERVAL '1' MINUTE)` | 겹치지 않는 고정 구간 |
| Sliding(Hop) | `HOP(..., INTERVAL '30' SECOND, INTERVAL '1' MINUTE)` | 겹치는 이동 구간 |
| Session | `SESSION(..., INTERVAL '5' MINUTE)` | 유휴 간격 기준 |

## 검증 (채점자 문체)

```bash
# Studio 앱 상태 (RUNNING 이어야 SQL 실행 가능)
aws kinesisanalyticsv2 describe-application --region $R --application-name lab-flink \
  --query 'ApplicationDetail.ApplicationStatus' --output text  # RUNNING
# ★ Zeppelin SQL 실행 자체는 브라우저(노트북) — CLI 자동화 불가. Studio RUNNING + 노트북 결과가 채점.
# 소스 스트림에 데이터 유입 확인
aws kinesis describe-stream-summary --region $R --stream-name lab-stream --query 'StreamDescriptionSummary.OpenShardCount' --output text
```

## 함정

- **★ SQL only** — Flink JAR/프로그래밍 넣으면 감점(가이드 명시). Zeppelin `%flink.ssql`.
- **Studio 는 시간과금(KPU)** — 검증 후 즉시 stop/delete. **★ delete 가 조용히 실패**할 수 있음(실측) → 재확인 필수.
- **Zeppelin SQL 은 CLI 자동화 불가** — Studio RUNNING 은 CLI 확인, SQL 실행/결과는 브라우저.
- **워터마크 필수** — 이벤트 시간 윈도우는 `WATERMARK FOR ts AS ts - INTERVAL '5' SECOND`.
- Kinesis/MSK 소스 커넥터 속성(스트림명·리전·시작위치) 정확히.

## context7 참고

- Managed Flink Studio: https://docs.aws.amazon.com/managed-flink/latest/java/how-notebook.html
- Flink SQL 윈도우: https://nightlies.apache.org/flink/flink-docs-stable/docs/dev/table/sql/queries/window-tvf/
