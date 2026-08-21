-- Managed Flink Studio 노트북: 이상 탐지 + S3 싱크. 각 문단 %flink.ssql.
-- clicks 소스 가정 (notebook-kinesis-windows.sql).
-- ★ 아래 SQL 은 ZEPPELIN-FLINK-3_0(Flink 1.15)에서 실제로 실행해 통과한 형태다. README 의 함정 참조.

-- ── 이상 탐지 1: 급증 감지 (직전 창 대비 3배) ─────────────────
-- ★ Flink 1.15(ZEPPELIN-FLINK-3_0)에서는 스트리밍 OVER 에 LAG/LEAD 를 못 쓴다(실측).
--   ORDER BY window_start → "OVER windows' ordering ... must be defined on a time attribute"
--   ORDER BY window_time  → NullPointerException
--   ⇒ 윈도우 집계를 뷰로 만들고 self-join 으로 직전 창과 비교한다(실행 성공 확인).

-- %flink.ssql
CREATE TEMPORARY VIEW win_cnt AS
SELECT window_start, window_end, COUNT(*) AS cnt
FROM TABLE(TUMBLE(TABLE clicks, DESCRIPTOR(event_time), INTERVAL '1' MINUTE))
GROUP BY window_start, window_end;

-- %flink.ssql(type=update)
SELECT c.window_start, c.cnt, p.cnt AS prev_cnt,
       CASE WHEN c.cnt > 3 * p.cnt THEN 'SPIKE' ELSE 'normal' END AS status
FROM win_cnt c JOIN win_cnt p
  ON p.window_start = c.window_start - INTERVAL '1' MINUTE;

-- ── 이상 탐지 2: 임계 초과 사용자 (윈도우 내 100회 초과) ───────
-- %flink.ssql(type=update)
SELECT user_id, cnt
FROM (
    SELECT window_start, user_id, COUNT(*) AS cnt
    FROM TABLE(TUMBLE(TABLE clicks, DESCRIPTOR(event_time), INTERVAL '1' MINUTE))
    GROUP BY window_start, window_end, user_id
)
WHERE cnt > 100;

-- ── S3 싱크 (파티션) ──────────────────────────────────────────
-- %flink.ssql
-- ★ format='parquet' 는 Studio 기본 클래스패스에 없다 → 실행 시
--   "Could not find any format factory for identifier 'parquet' in the classpath." (실측)
--   json/csv 는 내장이라 그대로 된다. parquet 이 꼭 필요하면 flink-sql-parquet JAR 을
--   CustomArtifactsConfiguration 으로 추가할 것.
CREATE TABLE agg_s3 (
    window_end TIMESTAMP(3),
    event_type STRING,
    cnt        BIGINT,
    dt         STRING
) PARTITIONED BY (dt)
WITH (
    'connector' = 'filesystem',
    'path' = 's3://lab-analytics-BUCKET/flink-json/',
    'format' = 'json',                                   -- 내장. parquet 은 JAR 추가 필요
    'sink.partition-commit.policy.kind' = 'success-file'
);

-- %flink.ssql
-- ★ 파일은 "체크포인트마다" 커밋된다. 인터랙티브 노트북은 체크포인팅이 꺼져 있을 수 있으니 먼저 켠다.
SET 'execution.checkpointing.interval' = '10s';

-- %flink.ssql(type=update)
INSERT INTO agg_s3
SELECT
    window_end,
    event_type,
    COUNT(*) AS cnt,
    DATE_FORMAT(window_end, 'yyyy-MM-dd') AS dt
FROM TABLE(TUMBLE(TABLE clicks, DESCRIPTOR(event_time), INTERVAL '1' MINUTE))
GROUP BY window_end, event_type;
