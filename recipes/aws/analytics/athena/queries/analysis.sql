-- Athena 분석 쿼리 모음. 실전에서 자주 쓰는 패턴.

-- ═══ 기본 집계 ═══
SELECT event_type, COUNT(*) AS cnt, SUM(value) AS total
FROM lab_db.events
WHERE dt = '2026-08-20'          -- 파티션 프루닝 (반드시 dt 조건)
GROUP BY event_type
ORDER BY cnt DESC;

-- ═══ 윈도우 함수: 사용자별 순위 ═══
SELECT user_id, cnt,
       RANK() OVER (ORDER BY cnt DESC) AS rnk,
       ROW_NUMBER() OVER (ORDER BY cnt DESC) AS rn
FROM (
    SELECT user_id, COUNT(*) AS cnt
    FROM lab_db.events WHERE dt='2026-08-20'
    GROUP BY user_id
)
LIMIT 10;

-- ═══ 시간대별 집계 (문자열 → timestamp) ═══
SELECT date_trunc('hour', from_iso8601_timestamp(created_at)) AS hr,
       COUNT(*) AS cnt
FROM lab_db.events_raw
GROUP BY 1 ORDER BY 1;

-- ═══ UNNEST: 배열 컬럼 펼치기 ═══
-- items: array<row(sku varchar, qty int)>
SELECT o.order_id, i.sku, i.qty
FROM lab_db.orders o
CROSS JOIN UNNEST(o.items) AS t(i);

-- ═══ JSON 문자열 컬럼 파싱 ═══
SELECT json_extract_scalar(payload, '$.user.id')   AS uid,
       CAST(json_extract_scalar(payload, '$.amount') AS double) AS amount
FROM lab_db.raw_logs;

-- ═══ 근사 집계 (대용량 빠르게) ═══
SELECT approx_distinct(user_id) AS uniq_users,
       approx_percentile(value, 0.95) AS p95
FROM lab_db.events WHERE dt='2026-08-20';

-- ═══ 조인 + 필터 ═══
SELECT e.user_id, u.grade, COUNT(*) AS cnt
FROM lab_db.events e
JOIN lab_db.users u ON e.user_id = u.user_id
WHERE e.dt='2026-08-20' AND u.grade='premium'
GROUP BY e.user_id, u.grade;
