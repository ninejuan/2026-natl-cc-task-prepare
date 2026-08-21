# 이상 탐지 + S3 싱크 — ✅ live 검증 (Flink 1.15 / ZEPPELIN-FLINK-3_0)

`notebook-anomaly-s3sink.sql` 은 **실제로 돌려 고친 버전**이다. 원래 쓰려던 SQL 3곳이 이 런타임에서 죽었다.

## 실측: S3 싱크 성공

```
s3://lab-flink2-…/flink-json/dt=2026-08-21/_SUCCESS
s3://lab-flink2-…/flink-json/dt=2026-08-21/part-8bee057d-…-0-0   (25,935 B, 399 줄)
```
```json
{"window_end":"2026-08-21 10:11:00","event_type":"161b","cnt":1}
```
→ `PARTITIONED BY (dt)` 가 **`dt=2026-08-21/` 디렉토리**를 만들고,
`sink.partition-commit.policy.kind='success-file'` 이 **`_SUCCESS`** 를 남긴다(채점이 이걸 본다).

## ★ 죽는 SQL 3종과 고친 형태 (전부 실측)

**1) `format='parquet'` → 실행 불가**
```
Could not find any format factory for identifier 'parquet' in the classpath.
```
Studio 기본 클래스패스에 parquet 포맷이 없다. **`json`/`csv` 는 내장**이라 그대로 된다.
parquet 이 꼭 필요하면 `flink-sql-parquet` JAR 을 `CustomArtifactsConfiguration` 으로 추가.

**2) `GROUP BY window_end, event_type` → 싱크가 거부**
```
Table sink '…agg_s3' doesn't support consuming update changes
which is produced by node GroupAggregate(groupBy=[window_end, event_type])
```
`window_start` 를 빼면 **윈도우 집계가 아니라 일반 GroupAggregate** 가 되어 retraction(update) 을 낸다.
파일시스템 싱크는 **append-only** 만 받는다. → **`GROUP BY window_start, window_end, event_type`**(select 는 `window_end` 만 해도 된다).

**3) `LAG(cnt,1) OVER (ORDER BY window_start)` → 실행 불가**
```
TableException: OVER windows' ordering in stream mode must be defined on a time attribute.
```
`window_time` 으로 바꿔도 이번엔 **`NullPointerException`** — Flink 1.15 의 스트리밍 OVER 는 `LAG`/`LEAD` 를 지원하지 않는다.
→ **윈도우 집계 뷰를 self-join** 해서 직전 창과 비교한다(실행 성공):
```sql
%flink.ssql
CREATE TEMPORARY VIEW win_cnt AS
SELECT window_start, window_end, COUNT(*) AS cnt
FROM TABLE(TUMBLE(TABLE clicks, DESCRIPTOR(event_time), INTERVAL '1' MINUTE))
GROUP BY window_start, window_end;

%flink.ssql(type=update)
SELECT c.window_start, c.cnt, p.cnt AS prev_cnt,
       CASE WHEN c.cnt > 3 * p.cnt THEN 'SPIKE' ELSE 'normal' END AS status
FROM win_cnt c JOIN win_cnt p
  ON p.window_start = c.window_start - INTERVAL '1' MINUTE;
```

## 그 외 함정

- **파일은 체크포인트마다 커밋**된다. 인터랙티브 노트북에서는 먼저
  `SET 'execution.checkpointing.interval' = '10s';` 를 실행할 것. 안 그러면 S3 에 아무것도 안 생긴다.
- 임계 초과 필터(`WHERE cnt > N`)는 문제없이 동작(실행 결과 확인).
- 실행 role 에 대상 버킷 `s3:*`(최소 Put/List/Delete) 필요.
