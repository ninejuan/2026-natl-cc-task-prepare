-- Managed Flink Studio (Zeppelin) 노트북. 문단마다 %flink.ssql 로 시작.
-- 가이드: "프로그래밍 형태 금지, Notebook 에서 SQL 로 쿼리". 이 파일이 그 형태.
-- 소스 Kinesis Data Stream, 실시간 윈도우 집계.

-- ── 문단 1: Kinesis 소스 테이블 정의 ────────────────────────────
-- %flink.ssql
CREATE TABLE clicks (
    user_id     STRING,
    event_type  STRING,
    `value`     DOUBLE,
    event_time  TIMESTAMP(3),
    -- 워터마크: event_time 기준 5초 지연 허용
    WATERMARK FOR event_time AS event_time - INTERVAL '5' SECOND
) WITH (
    'connector' = 'kinesis',
    'stream' = 'lab-stream',
    'aws.region' = 'ap-northeast-2',
    'scan.stream.initpos' = 'LATEST',
    'format' = 'json',
    'json.timestamp-format.standard' = 'ISO-8601'
);

-- ── 문단 2: TUMBLE (고정 1분 윈도우) 집계 ──────────────────────
-- %flink.ssql(type=update)
-- 1분마다 event_type 별 건수·합계. 겹치지 않는 창.
SELECT
    window_start,
    window_end,
    event_type,
    COUNT(*)      AS cnt,
    SUM(`value`)  AS total
FROM TABLE(
    TUMBLE(TABLE clicks, DESCRIPTOR(event_time), INTERVAL '1' MINUTE)
)
GROUP BY window_start, window_end, event_type;

-- ── 문단 3: HOP (슬라이딩 윈도우) ─────────────────────────────
-- %flink.ssql(type=update)
-- 10초마다 갱신되는 최근 1분 집계 (겹치는 창).
SELECT
    window_start,
    window_end,
    COUNT(*) AS cnt
FROM TABLE(
    HOP(TABLE clicks, DESCRIPTOR(event_time), INTERVAL '10' SECOND, INTERVAL '1' MINUTE)
)
GROUP BY window_start, window_end;

-- ── 문단 4: SESSION (세션 윈도우) ─────────────────────────────
-- %flink.ssql(type=update)
-- 사용자별 30초 비활동이면 세션 종료.
SELECT
    user_id,
    SESSION_START(event_time, INTERVAL '30' SECOND) AS session_start,
    COUNT(*) AS events
FROM clicks
GROUP BY user_id, SESSION(event_time, INTERVAL '30' SECOND);

-- ── 문단 5: 결과를 S3 로 싱크 ─────────────────────────────────
-- %flink.ssql
CREATE TABLE agg_sink (
    window_end TIMESTAMP(3),
    event_type STRING,
    cnt        BIGINT
) WITH (
    'connector' = 'filesystem',
    'path' = 's3://lab-analytics-BUCKET/flink-out/',
    'format' = 'json'
);

-- %flink.ssql
-- ★ 파일 싱크는 체크포인트마다 커밋된다 → 인터랙티브 노트북은 먼저 켜야 S3 에 파일이 생긴다(실측).
SET 'execution.checkpointing.interval' = '10s';

-- %flink.ssql(type=update)
-- ★ GROUP BY 에 window_start 를 반드시 포함할 것(실측).
--   window_end 만 넣으면 윈도우 집계가 아니라 일반 GroupAggregate 가 되어 update(retraction) 를 내고
--   파일시스템 싱크가 "doesn't support consuming update changes" 로 거부한다.
INSERT INTO agg_sink
SELECT window_end, event_type, COUNT(*) AS cnt
FROM TABLE(TUMBLE(TABLE clicks, DESCRIPTOR(event_time), INTERVAL '1' MINUTE))
GROUP BY window_start, window_end, event_type;
