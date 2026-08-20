-- Managed Flink Studio 노트북: Top-N 순위 + 스트림 조인. 각 문단 %flink.ssql.
-- 소스는 notebook-kinesis-windows.sql 의 clicks 테이블 가정.

-- ── 윈도우 Top-N (분당 이벤트 많은 상위 3명) ──────────────────
-- %flink.ssql(type=update)
SELECT user_id, cnt, rn
FROM (
    SELECT
        user_id, cnt,
        ROW_NUMBER() OVER (PARTITION BY window_start ORDER BY cnt DESC) AS rn
    FROM (
        SELECT window_start, user_id, COUNT(*) AS cnt
        FROM TABLE(TUMBLE(TABLE clicks, DESCRIPTOR(event_time), INTERVAL '1' MINUTE))
        GROUP BY window_start, window_end, user_id
    )
)
WHERE rn <= 3;

-- ── 차원 테이블 (JDBC/DynamoDB lookup) 정의 ───────────────────
-- %flink.ssql
CREATE TABLE users_dim (
    user_id  STRING,
    grade    STRING,
    PRIMARY KEY (user_id) NOT ENFORCED
) WITH (
    'connector' = 'dynamodb',
    'table-name' = 'users',
    'aws.region' = 'ap-northeast-2'
);

-- ── 스트림 x 차원 조인 (이벤트에 등급 붙이기) ─────────────────
-- %flink.ssql(type=update)
SELECT c.user_id, c.event_type, u.grade
FROM clicks AS c
LEFT JOIN users_dim AS u ON c.user_id = u.user_id;

-- ── 인터벌 조인 (두 스트림, 시간 범위 내 매칭) ────────────────
-- 예: 주문(order)과 결제(pay)를 10분 이내로 매칭
-- %flink.ssql(type=update)
-- (orders, payments 테이블이 각각 event_time + WATERMARK 를 가진다고 가정)
SELECT o.order_id, o.amount, p.pay_ts
FROM orders AS o, payments AS p
WHERE o.order_id = p.order_id
  AND p.pay_ts BETWEEN o.order_ts AND o.order_ts + INTERVAL '10' MINUTE;
