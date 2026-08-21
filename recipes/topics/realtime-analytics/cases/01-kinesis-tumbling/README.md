# Kinesis 소스 + 윈도우 집계 (Managed Flink Studio) — ✅ live 검증

`notebook-kinesis-windows.sql` 을 **실제 Studio 노트북에서 실행**해 Kinesis 스트림의 레코드를 읽는 것까지 확인했다(eu-west-2, ZEPPELIN-FLINK-3_0 / Flink 1.15, 2026-08-21).

## ★★ 가장 중요한 함정 — 기본 Studio 앱에는 Kinesis 커넥터가 없다

CLI/Terraform 으로 만든 Studio 앱에서 `'connector'='kinesis'` 로 `CREATE TABLE` 하면 DDL 은 통과하지만
**SELECT 하는 순간** 이렇게 죽는다(실측):

```
org.apache.flink.table.api.ValidationException:
  Could not find any factory for identifier 'kinesis' that implements
  'org.apache.flink.table.factories.DynamicTableFactory' in the classpath.
Available factory identifiers are:
    blackhole
    datagen
    filesystem
    print
```

→ 커넥터 JAR 을 **앱 설정에 추가**해야 한다. 콘솔의 "Studio 노트북 만들기" 마법사는 이걸 자동으로 넣어주지만
**CLI/TF 로 만들면 안 들어간다.** 대회 현장에서 콘솔로 만들었다면 대개 괜찮고, CLI 로 만들었다면 반드시 확인할 것.

```bash
aws kinesisanalyticsv2 stop-application --application-name lab-flink --force   # 먼저 READY 로
V=$(aws kinesisanalyticsv2 describe-application --application-name lab-flink --query ApplicationDetail.ApplicationVersionId --output text)
aws kinesisanalyticsv2 update-application --application-name lab-flink --current-application-version-id $V \
  --application-configuration-update '{"ZeppelinApplicationConfigurationUpdate":{"CustomArtifactsConfigurationUpdate":[
    {"ArtifactType":"DEPENDENCY_JAR","MavenReference":{"GroupId":"org.apache.flink","ArtifactId":"flink-sql-connector-kinesis","Version":"1.15.4"}},
    {"ArtifactType":"DEPENDENCY_JAR","MavenReference":{"GroupId":"org.apache.flink","ArtifactId":"flink-connector-kafka","Version":"1.15.4"}}
  ]}}'
aws kinesisanalyticsv2 start-application --application-name lab-flink
```
- **Kafka 는 `flink-connector-kafka`**(sql- 없음). `flink-sql-connector-kafka:1.15.4` 는
  `InvalidArgumentException: Found unsupported Maven References` 로 거부된다(실측).
- 아티팩트 추가는 **앱이 READY(정지) 상태**에서만 가능. RUNNING/STARTING 이면 `ResourceInUseException`.

## 실측 결과 (커넥터 추가 후)

```sql
%flink.ssql
CREATE TABLE clicks (
  user_id STRING, event_type STRING, `value` DOUBLE, event_time TIMESTAMP(3),
  WATERMARK FOR event_time AS event_time - INTERVAL '5' SECOND
) WITH ('connector'='kinesis','stream'='lab-stream','aws.region'='eu-west-2',
        'scan.stream.initpos'='TRIM_HORIZON','format'='json',
        'json.timestamp-format.standard'='ISO-8601');
```
```
%flink.ssql(type=update)
SELECT * FROM clicks
→
user_id  event_type  value  event_time
u0       view        0.0    2026-01-01 00:00:00.000
u1       click       1.0    2026-01-01 00:00:10.000
u2       view        2.0    2026-01-01 00:00:20.000
u0       click       3.0    2026-01-01 00:00:30.000
…
```
Kinesis 에 `put-records` 로 넣은 JSON 이 그대로 파싱돼 나온다(ISO-8601 타임스탬프 포함).

**TUMBLE 1분 창 집계도 Kinesis 소스로 그대로 동작**(실측):
```
%flink.ssql(type=update)
SELECT window_start, window_end, event_type, COUNT(*) AS cnt, SUM(`value`) AS total
FROM TABLE(TUMBLE(TABLE clicks, DESCRIPTOR(event_time), INTERVAL '1' MINUTE))
GROUP BY window_start, window_end, event_type
→
window_start              window_end                event_type  cnt  total
2026-01-01 00:00:00.000   2026-01-01 00:01:00.000   view          3    6.0
2026-01-01 00:00:00.000   2026-01-01 00:01:00.000   click         3    9.0
2026-01-01 00:01:00.000   2026-01-01 00:02:00.000   click         3   27.0
2026-01-01 00:01:00.000   2026-01-01 00:02:00.000   view          3   24.0
2026-01-01 00:02:00.000   2026-01-01 00:03:00.000   view          3   42.0
2026-01-01 00:02:00.000   2026-01-01 00:03:00.000   click         3   45.0
```
(워터마크가 마지막 이벤트 시각까지 올라가면서 창들이 순서대로 닫혔다.)

## 그 외 함정 (실측)

- **`CREATE TABLE` 은 Glue 카탈로그에 영구 저장된다** — 앱을 재시작해도 남아서
  두 번째 실행 때 `Table (or view) lab_flink_db.clicks already exists in Catalog hive` 로 실패한다.
  재실행용 노트북은 `CREATE TABLE IF NOT EXISTS` 또는 앞에 `DROP TABLE IF EXISTS` 를 붙여라.
- **무한 스트림 SELECT 는 문단이 안 끝난다.** 결과를 확보하려면 문단을 **취소**(Zeppelin cancel)해야 그때까지의
  결과가 남는다(취소 시 `status=ABORT`, 결과 테이블은 보존됨 — 실측). 채점 스크린샷용이면 이 방식.
- `scan.stream.initpos`: `LATEST`(기본, 실행 후 들어온 것만) / `TRIM_HORIZON`(스트림에 남은 것부터).
  미리 넣어둔 데이터를 보려면 **TRIM_HORIZON**.
- 워터마크 없으면 이벤트시간 윈도우가 안 닫힌다.
- Studio 는 KPU 시간과금 — 검증 후 `stop-application`, 안 쓰면 `delete-application`.
