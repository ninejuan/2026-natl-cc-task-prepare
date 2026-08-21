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

| # | 케이스 | SQL 패턴 | 검증 |
|---|---|---|---|
| 01 | Kinesis 소스 + 텀블링 윈도우 | TUMBLE 집계 | ✅ **live**(Studio 노트북에서 Kinesis 레코드 조회 성공. ★커넥터 JAR 추가 필수 — 아래) |
| 02 | MSK 소스 | Kafka connector | 커넥터 아티팩트는 `flink-connector-kafka:1.15.4`(실측 수락). MSK 실연결은 01 과 동일 절차 |
| 03 | TopN + 스트림 조인 | ROW_NUMBER OVER | ✅ live(윈도우+TopN 실행 결과 확인 — `cases/05-window-variants/`) |
| 04 | 이상 탐지 → S3 sink | 임계 필터 + S3 | `notebook-anomaly-s3sink.sql` |
| 05 | 세션/슬라이딩 윈도우 | SESSION/HOP | ✅ **live**(TUMBLE/HOP/CUMULATE/TopN/SESSION 전부 실행→결과) `cases/05-window-variants/` |

## ★★ 커넥터 JAR 이 없으면 Kinesis/Kafka 소스가 통째로 안 된다 (실측)

CLI/TF 로 만든 Studio 앱은 커넥터가 **`blackhole / datagen / filesystem / print` 4개뿐**이다.
`'connector'='kinesis'` 로 만든 테이블을 SELECT 하면
`Could not find any factory for identifier 'kinesis' … in the classpath` 로 죽는다.
→ `update-application` 으로 **Maven 아티팩트를 추가**해야 한다(앱이 READY 일 때만). 상세: `cases/01-kinesis-tumbling/README.md`.

## ★ Zeppelin 은 CLI 로도 돌릴 수 있다 (실측 — 문서 정정)

`create-application-presigned-url` 의 URL 을 한 번 호출해 **`VerifiedAuthToken` 쿠키**를 받으면
그 뒤로는 Zeppelin REST API 를 그대로 쓸 수 있다. 노트북 생성·문단 추가·실행·결과 조회·취소 전부 가능.
```bash
URL=$(aws kinesisanalyticsv2 create-application-presigned-url --application-name lab-flink --url-type ZEPPELIN_UI_URL --query AuthorizedUrl --output text)
BASE=$(echo "$URL" | sed 's|\(https://[^/]*\).*|\1|')
TOK=$(curl -s -D - -o /dev/null "$URL" | grep -i '^set-cookie: VerifiedAuthToken=' | sed 's/^[Ss]et-[Cc]ookie: //; s/;.*//')
curl -s -H "Cookie: $TOK" "$BASE/zeppelin/api/notebook"                   # 노트북 목록
curl -s -X POST -H "Cookie: $TOK" -H 'Content-Type: application/json' \
     -d '{"name":"lab","paragraphs":[{"title":"t","text":"%flink.ssql\nSHOW TABLES"}]}' \
     "$BASE/zeppelin/api/notebook"                                        # 노트북 생성
# 실행: POST /zeppelin/api/notebook/run/{noteId}/{paragraphId}   취소: DELETE /zeppelin/api/notebook/job/{noteId}/{paragraphId}
```
- **GET 은 쿠키 없이도 되지만 POST 는 403** — 쿠키 필수(실측).
- 채점은 여전히 브라우저 노트북을 보겠지만, **준비/검증은 CLI 로 자동화 가능**하다.

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
  - 단, **커넥터 JAR(Maven 아티팩트) 추가는 "프로그래밍"이 아니라 앱 설정**이다. Kinesis/Kafka 소스를 쓰려면 필수(위 참조).
- **Studio 는 시간과금(KPU)** — 검증 후 즉시 stop/delete. **★ delete 가 조용히 실패**할 수 있음(실측) → 재확인 필수.
- **`CREATE TABLE` 은 Glue 카탈로그에 남는다** — 앱 재시작해도 남아 재실행 시 `already exists`. `IF NOT EXISTS`/`DROP` 선행.
- **윈도우 TVF 인자는 테이블 이름만** — `TABLE (SELECT … FROM (VALUES …))` 같은 인라인 서브쿼리는 ParseException(실측).
- **무한 스트림 SELECT 는 문단이 안 끝난다** — 결과 스냅샷은 문단 **취소** 후에 남는다(`status=ABORT` + 결과 보존, 실측).
- **워터마크 필수** — 이벤트 시간 윈도우는 `WATERMARK FOR ts AS ts - INTERVAL '5' SECOND`.
- Kinesis/MSK 소스 커넥터 속성(스트림명·리전·시작위치) 정확히.

## context7 참고

- Managed Flink Studio: https://docs.aws.amazon.com/managed-flink/latest/java/how-notebook.html
- Flink SQL 윈도우: https://nightlies.apache.org/flink/flink-docs-stable/docs/dev/table/sql/queries/window-tvf/
