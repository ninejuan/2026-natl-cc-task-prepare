-- Athena CTAS/INSERT — SQL 만으로 ETL (Glue Spark 없이).

-- ═══ CTAS: JSON → Parquet 재적재 (파티션 + 압축) ═══
-- 이후 쿼리 스캔량·비용 급감. 대회에서 "Parquet 로 저장" 요구에.
CREATE TABLE lab_db.events_parquet
WITH (
    format = 'PARQUET',
    parquet_compression = 'SNAPPY',
    external_location = 's3://<BUCKET>/parquet/',
    partitioned_by = ARRAY['dt']
) AS
SELECT event_type, user_id, value, id, dt
FROM lab_db.events
WHERE dt >= '2026-08-01';

-- ═══ CTAS: 집계 결과 테이블 ═══
CREATE TABLE lab_db.daily_summary
WITH (format='PARQUET', external_location='s3://<BUCKET>/summary/')
AS
SELECT dt, event_type, COUNT(*) AS cnt, SUM(value) AS total
FROM lab_db.events
GROUP BY dt, event_type;

-- ═══ INSERT INTO: 기존 테이블에 증분 적재 ═══
-- (CTAS 는 새 테이블, INSERT 는 기존에 추가)
INSERT INTO lab_db.events_parquet
SELECT event_type, user_id, value, id, dt
FROM lab_db.events
WHERE dt = '2026-08-21';

-- ═══ UNLOAD: 쿼리 결과를 S3 로 직접 (CSV/Parquet/JSON) ═══
UNLOAD (SELECT * FROM lab_db.events WHERE dt='2026-08-20')
TO 's3://<BUCKET>/export/'
WITH (format='JSON');
