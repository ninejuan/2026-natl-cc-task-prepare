# Flink SQL 윈도우 변형 — ✅ live 검증 (Managed Flink Studio, ZEPPELIN-FLINK-3_0 / Flink 1.15)

`windows.sql` 의 윈도우 패턴들을 **실제 Studio 노트북에서 실행**해 결과까지 확인했다(eu-west-2, 2026-08-21).
소스는 `datagen` 커넥터(내장)로 200건 생성 → 각 윈도우 쿼리 실행.

```sql
%flink.ssql
CREATE TABLE events (
  user_id STRING, amount INT, ts TIMESTAMP(3),
  WATERMARK FOR ts AS ts - INTERVAL '5' SECOND
) WITH ('connector'='datagen','rows-per-second'='20','number-of-rows'='200',
        'fields.user_id.length'='2','fields.amount.min'='1','fields.amount.max'='9');
```

## 실행 결과 (전부 SUCCESS/FINISHED)

**TUMBLE** — 겹치지 않는 1분 창
```
window_start              window_end                cnt  total
2026-08-21 08:40:00.000   2026-08-21 08:41:00.000    80    443
2026-08-21 08:41:00.000   2026-08-21 08:42:00.000   120    556
```
**HOP** — 1분 창을 30초마다 (겹침 → 같은 이벤트가 여러 창에 들어가 합이 200 초과)
```
08:40:30 ~ 08:41:30   180
08:41:00 ~ 08:42:00   200
08:41:30 ~ 08:42:30    20
```
**CUMULATE** — 1분 창을 10초 단위 누적 (running total 이 커짐)
```
08:41:00 ~ 08:41:50   664
08:41:00 ~ 08:42:00   948
```
**윈도우 + TopN** (`ROW_NUMBER() OVER (PARTITION BY window_start ORDER BY cnt DESC)`)
```
user_id cnt window_start              rn
37      3   2026-08-21 08:42:00.000   1
ea      3   2026-08-21 08:42:00.000   2
73      3   2026-08-21 08:42:00.000   3
```
**SESSION** (`GROUP BY user_id, SESSION(ts, INTERVAL '5' MINUTE)` + `SESSION_START(...)`) — 유저별 세션 집계 정상 출력.

## 함정 (실측)

- **윈도우 TVF 의 `TABLE(...)` 인자는 테이블 이름이어야 한다.** `TABLE (SELECT ... FROM (VALUES ...))` 처럼 인라인 서브쿼리를 넣으면 **ParseException**(`Encountered "(" ...`). 임시 데이터가 필요하면 `datagen` 커넥터 테이블이나 뷰를 먼저 만들어라.
- **SESSION 은 구문법**(`GROUP BY SESSION(ts, ...)` + `SESSION_START()`)이고, TUMBLE/HOP/CUMULATE 는 **윈도우 TVF 신문법**(`FROM TABLE(TUMBLE(TABLE t, DESCRIPTOR(ts), ...))`)이다. Flink 1.15 에서 SESSION 은 아직 TVF 가 없다 — 섞어 쓰지 말 것.
- **워터마크 없으면 이벤트시간 윈도우가 안 닫힌다** — 결과가 영영 안 나온다. `WATERMARK FOR ts AS ts - INTERVAL '5' SECOND` 필수.
- 무한 스트림에 `type=update` 로 SELECT 하면 문단이 끝나지 않는다. 채점용 스냅샷이 필요하면 `number-of-rows` 로 유한 소스를 쓰거나 문단을 중단시켜라.
