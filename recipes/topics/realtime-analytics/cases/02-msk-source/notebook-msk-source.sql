-- Managed Flink Studio 노트북: MSK 를 소스로 하는 실시간 처리.
-- Kinesis 대신 MSK(Kafka)에서 읽을 때. 각 문단 %flink.ssql.

-- ── MSK 소스 테이블 (IAM 인증) ────────────────────────────────
-- %flink.ssql
CREATE TABLE orders_kafka (
    order_id    STRING,
    user_id     STRING,
    amount      DOUBLE,
    ts          TIMESTAMP(3),
    WATERMARK FOR ts AS ts - INTERVAL '5' SECOND
) WITH (
    'connector' = 'kafka',
    'topic' = 'orders',
    'properties.bootstrap.servers' = 'boot-xxxx.c2.kafka-serverless.ap-northeast-2.amazonaws.com:9098',
    'properties.security.protocol' = 'SASL_SSL',
    'properties.sasl.mechanism' = 'AWS_MSK_IAM',
    'properties.sasl.jaas.config' = 'software.amazon.msk.auth.iam.IAMLoginModule required;',
    'properties.sasl.client.callback.handler.class' = 'software.amazon.msk.auth.iam.IAMClientCallbackHandler',
    'scan.startup.mode' = 'latest-offset',
    'format' = 'json',
    'json.timestamp-format.standard' = 'ISO-8601'
);

-- ── 실시간 매출 집계 (1분 텀블) ───────────────────────────────
-- %flink.ssql(type=update)
SELECT
    window_start,
    COUNT(*)     AS order_cnt,
    SUM(amount)  AS revenue
FROM TABLE(TUMBLE(TABLE orders_kafka, DESCRIPTOR(ts), INTERVAL '1' MINUTE))
GROUP BY window_start, window_end;

-- ── Kafka -> Kafka (처리 결과를 다른 토픽으로) ─────────────────
-- %flink.ssql
CREATE TABLE alerts_kafka (
    order_id STRING,
    amount   DOUBLE,
    reason   STRING
) WITH (
    'connector' = 'kafka',
    'topic' = 'alerts',
    'properties.bootstrap.servers' = 'boot-xxxx...:9098',
    'properties.security.protocol' = 'SASL_SSL',
    'properties.sasl.mechanism' = 'AWS_MSK_IAM',
    'properties.sasl.jaas.config' = 'software.amazon.msk.auth.iam.IAMLoginModule required;',
    'properties.sasl.client.callback.handler.class' = 'software.amazon.msk.auth.iam.IAMClientCallbackHandler',
    'format' = 'json'
);

-- %flink.ssql(type=update)
-- 고액 주문을 실시간으로 alerts 토픽에 발행
INSERT INTO alerts_kafka
SELECT order_id, amount, 'high-value' AS reason
FROM orders_kafka
WHERE amount >= 10000;
