-- Managed Flink Studio 노트북: 이상 탐지 + S3 Parquet 싱크. 각 문단 %flink.ssql.
-- clicks 소스 가정 (notebook-kinesis-windows.sql).

-- ── 이상 탐지 1: 급증 감지 (직전 창 대비 3배) ─────────────────
-- %flink.ssql(type=update)
-- 분당 건수를 구하고, 이전 창 대비 배율을 LAG 로 비교
SELECT
    window_start,
    cnt,
    LAG(cnt, 1) OVER (ORDER BY window_start) AS prev_cnt,
    CASE WHEN cnt > 3 * LAG(cnt, 1) OVER (ORDER BY window_start)
         THEN 'SPIKE' ELSE 'normal' END AS status
FROM (
    SELECT window_start, COUNT(*) AS cnt
    FROM TABLE(TUMBLE(TABLE clicks, DESCRIPTOR(event_time), INTERVAL '1' MINUTE))
    GROUP BY window_start, window_end
);

-- ── 이상 탐지 2: 임계 초과 사용자 (윈도우 내 100회 초과) ───────
-- %flink.ssql(type=update)
SELECT user_id, cnt
FROM (
    SELECT window_start, user_id, COUNT(*) AS cnt
    FROM TABLE(TUMBLE(TABLE clicks, DESCRIPTOR(event_time), INTERVAL '1' MINUTE))
    GROUP BY window_start, window_end, user_id
)
WHERE cnt > 100;

-- ── S3 Parquet 싱크 (파티션 + 컬럼형) ─────────────────────────
-- %flink.ssql
CREATE TABLE agg_s3 (
    window_end TIMESTAMP(3),
    event_type STRING,
    cnt        BIGINT,
    dt         STRING
) PARTITIONED BY (dt)
WITH (
    'connector' = 'filesystem',
    'path' = 's3://lab-analytics-BUCKET/flink-parquet/',
    'format' = 'parquet',
    'sink.partition-commit.policy.kind' = 'success-file'
);

-- %flink.ssql(type=update)
INSERT INTO agg_s3
SELECT
    window_end,
    event_type,
    COUNT(*) AS cnt,
    DATE_FORMAT(window_end, 'yyyy-MM-dd') AS dt
FROM TABLE(TUMBLE(TABLE clicks, DESCRIPTOR(event_time), INTERVAL '1' MINUTE))
GROUP BY window_end, event_type;
