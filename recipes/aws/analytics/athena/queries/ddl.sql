-- Athena DDL 모음. <BUCKET> 치환해서 사용.

-- ═══ JSON 테이블 + partition projection (crawler 없이) ═══
CREATE EXTERNAL TABLE IF NOT EXISTS lab_db.events (
    event_type string,
    user_id    string,
    `value`    double,
    id         int
)
PARTITIONED BY (dt string)
ROW FORMAT SERDE 'org.openx.data.jsonserde.JsonSerDe'
LOCATION 's3://<BUCKET>/events/'
TBLPROPERTIES (
    'projection.enabled'='true',
    'projection.dt.type'='date',
    'projection.dt.range'='2026-01-01,2026-12-31',
    'projection.dt.format'='yyyy-MM-dd',
    'storage.location.template'='s3://<BUCKET>/events/dt=${dt}/'
);

-- ═══ Parquet 테이블 (컬럼형, 스캔 저렴) ═══
CREATE EXTERNAL TABLE IF NOT EXISTS lab_db.events_parquet (
    event_type string, user_id string, `value` double, id int
)
PARTITIONED BY (dt string)
STORED AS PARQUET
LOCATION 's3://<BUCKET>/parquet/'
TBLPROPERTIES ('parquet.compression'='SNAPPY');

-- ═══ CSV 테이블 (헤더 스킵) ═══
CREATE EXTERNAL TABLE IF NOT EXISTS lab_db.events_csv (
    event_type string, user_id string, `value` double
)
ROW FORMAT SERDE 'org.apache.hadoop.hive.serde2.OpenCSVSerde'
LOCATION 's3://<BUCKET>/csv/'
TBLPROPERTIES ('skip.header.line.count'='1');

-- ═══ 정수 범위 projection (dt 대신 숫자 파티션) ═══
-- TBLPROPERTIES (
--   'projection.enabled'='true',
--   'projection.hour.type'='integer',
--   'projection.hour.range'='0,23',
--   'projection.hour.digits'='2'
-- );

-- ═══ 수동 파티션 로드 (projection 안 쓸 때) ═══
-- MSCK REPAIR TABLE lab_db.events;                    -- 경로 자동 스캔
-- ALTER TABLE lab_db.events ADD PARTITION (dt='2026-08-20')
--   LOCATION 's3://<BUCKET>/events/dt=2026-08-20/';   -- 명시적
