-- Flink SQL 윈도우 변형 모음 (Managed Flink Studio / Zeppelin %flink.ssql).
-- 소스 테이블 예: events(user_id STRING, amount INT, ts TIMESTAMP(3), WATERMARK FOR ts AS ts - INTERVAL '5' SECOND)
-- ★ 이벤트시간 윈도우는 WATERMARK 필수. Studio 노트북에서 SQL 로만(프로그래밍 금지).

-- ═══ 1. Tumbling (겹치지 않는 고정 1분) ═══
SELECT window_start, window_end, COUNT(*) AS cnt, SUM(amount) AS total
FROM TABLE(TUMBLE(TABLE events, DESCRIPTOR(ts), INTERVAL '1' MINUTE))
GROUP BY window_start, window_end;

-- ═══ 2. Sliding / Hop (1분 창을 30초마다 이동 — 겹침) ═══
SELECT window_start, window_end, COUNT(*) AS cnt
FROM TABLE(HOP(TABLE events, DESCRIPTOR(ts), INTERVAL '30' SECOND, INTERVAL '1' MINUTE))
GROUP BY window_start, window_end;

-- ═══ 3. Cumulate (1분 창을 10초 단위로 누적 — 대시보드 실시간 누계) ═══
SELECT window_start, window_end, SUM(amount) AS running_total
FROM TABLE(CUMULATE(TABLE events, DESCRIPTOR(ts), INTERVAL '10' SECOND, INTERVAL '1' MINUTE))
GROUP BY window_start, window_end;

-- ═══ 4. Session (5분 유휴 간격 기준 — 사용자 세션) ═══
SELECT user_id, SESSION_START(ts, INTERVAL '5' MINUTE) AS s_start, COUNT(*) AS events_in_session
FROM events
GROUP BY user_id, SESSION(ts, INTERVAL '5' MINUTE);

-- ═══ 5. 윈도우 + TopN (각 텀블 윈도우에서 상위 3 유저) ═══
SELECT * FROM (
  SELECT user_id, cnt, window_start,
         ROW_NUMBER() OVER (PARTITION BY window_start ORDER BY cnt DESC) AS rn
  FROM (
    SELECT user_id, window_start, COUNT(*) AS cnt
    FROM TABLE(TUMBLE(TABLE events, DESCRIPTOR(ts), INTERVAL '1' MINUTE))
    GROUP BY user_id, window_start
  )
) WHERE rn <= 3;
