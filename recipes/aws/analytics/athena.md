# Athena

**트리거 문구** — "S3 데이터를 쿼리", "SQL 로 분석", "로그 분석", "Glue 카탈로그".

**전제**
```bash
export R=ap-northeast-2 ACCT=$(aws sts get-caller-identity --query Account --output text)
BUCKET=lab-analytics-$ACCT   # 데이터 + 결과 저장
```

> **쿼리 라이브러리**: `queries/ddl.sql`(JSON/Parquet/CSV 테이블·projection), `queries/analysis.sql`(집계·윈도우·UNNEST·근사집계·조인), `queries/ctas-etl.sql`(CTAS·INSERT·UNLOAD). 전부 실 API 검증.

Athena 는 S3 데이터를 SQL 로 조회. 테이블 정의는 ① Glue crawler 자동 ② DDL 수동 ③ **partition projection**(crawler 없이, 아래 권장).

---

## ★ 케이스 A — partition projection (crawler 없이) [검증됨]

파티션을 규칙으로 정의해 crawler·`MSCK REPAIR` 없이 바로 쿼리. 대회에서 가장 빠르다.

```bash
# 1) DB
aws athena start-query-execution --region $R \
  --query-string "CREATE DATABASE IF NOT EXISTS lab_db" \
  --result-configuration "OutputLocation=s3://$BUCKET/athena-results/"

# 2) 테이블 (JSON, dt 파티션을 projection 으로)
aws athena start-query-execution --region $R \
  --query-string "CREATE EXTERNAL TABLE IF NOT EXISTS lab_db.events (
    event_type string, id int
  )
  PARTITIONED BY (dt string)
  ROW FORMAT SERDE 'org.openx.data.jsonserde.JsonSerDe'
  LOCATION 's3://$BUCKET/events/'
  TBLPROPERTIES (
    'projection.enabled'='true',
    'projection.dt.type'='date',
    'projection.dt.range'='2026-01-01,2026-12-31',
    'projection.dt.format'='yyyy-MM-dd',
    'storage.location.template'='s3://$BUCKET/events/dt=\${dt}/'
  )" \
  --result-configuration "OutputLocation=s3://$BUCKET/athena-results/"
```

쿼리 + 결과:
```bash
QID=$(aws athena start-query-execution --region $R \
  --query-string "SELECT event_type, count(*) c FROM lab_db.events WHERE dt='2026-08-20' GROUP BY event_type" \
  --query-execution-context "Database=lab_db" \
  --result-configuration "OutputLocation=s3://$BUCKET/athena-results/" \
  --query QueryExecutionId --output text)
# 상태 폴링
aws athena get-query-execution --region $R --query-execution-id $QID --query 'QueryExecution.Status.State' --output text
# 결과
aws athena get-query-results --region $R --query-execution-id $QID \
  --query 'ResultSet.Rows[].Data[].VarCharValue' --output text
```

## 케이스 B — Glue crawler 자동 스키마

파일 구조가 복잡하거나 스키마를 모를 때. `../analytics/glue/` 참조. crawler 가 카탈로그를 채우면 Athena 가 그대로 쿼리.

## 케이스 C — CTAS (결과를 Parquet 로 저장)

```sql
CREATE TABLE lab_db.events_parquet
WITH (format='PARQUET', external_location='s3://<BUCKET>/parquet/', partitioned_by=ARRAY['dt'])
AS SELECT event_type, id, dt FROM lab_db.events;
```
원본 JSON 을 컬럼형으로 재적재 → 이후 쿼리 스캔량·비용 급감. ETL 을 SQL 로.

## 케이스 D — workgroup (결과 위치·비용 제어)

```bash
aws athena create-work-group --region $R --name lab-wg \
  --configuration "ResultConfiguration={OutputLocation=s3://$BUCKET/wg-results/},BytesScannedCutoffPerQuery=1073741824"
# 쿼리 시 --work-group lab-wg
```

## 검증

```bash
aws athena list-databases --region $R --catalog-name AwsDataCatalog --query 'DatabaseList[].Name' --output text
aws glue get-tables --region $R --database-name lab_db --query 'TableList[].Name' --output text
# 쿼리 성공률
aws athena get-query-execution --region $R --query-execution-id $QID \
  --query 'QueryExecution.[Status.State,Statistics.DataScannedInBytes]' --output text
```

## 함정

- **결과 위치(OutputLocation) 필수** — workgroup 에 기본값 없으면 매 쿼리에 지정. 없으면 실패.
- **projection range** 밖의 날짜는 조회 안 됨. range 를 넉넉히.
- **JsonSerDe** 는 한 줄 = 한 객체(JSONL). Firehose 기본 출력이 이 형식이라 맞는다. 배열이면 실패.
- **비동기** — start → 폴링 → get-results. 한 방에 안 나온다.
- **파티션 안 타면 전체 스캔** — WHERE 에 파티션 컬럼(dt)을 넣어야 싸다.
- Glue 테이블과 공유 — Athena DB = Glue database. `get-tables` 로 교차 확인.

## 정리
```bash
aws athena start-query-execution --region $R --query-string "DROP TABLE lab_db.events" \
  --result-configuration "OutputLocation=s3://$BUCKET/athena-results/"
aws athena start-query-execution --region $R --query-string "DROP DATABASE lab_db" \
  --result-configuration "OutputLocation=s3://$BUCKET/athena-results/"
```
