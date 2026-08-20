# CloudWatch Logs Insights 쿼리 모음

본 문서는 CloudWatch Logs 에 쌓인 로그를 Logs Insights 로 분석하는 쿼리 예시 모음이다.
콘솔 **Logs Insights** 편집기에 붙여넣거나 CLI 로 실행한다.

```bash
export R=ap-northeast-2 LG=/lab/app
QID=$(aws logs start-query --region $R --log-group-name $LG \
  --start-time $(($(date +%s)-3600)) --end-time $(date +%s) \
  --query-string '<아래 쿼리>' --query queryId --output text)
sleep 5
aws logs get-query-results --region $R --query-id $QID --query results --output json
```

구문 기본: `fields` / `filter` / `stats … by` / `sort` / `limit` / `parse` / `bin()`. 파이프(`|`) 로 연결.

## 예시 쿼리

- 최근 로그 20건 (시간 역순)
```
fields @timestamp, @message | sort @timestamp desc | limit 20
```

- ERROR 만 필터
```
fields @timestamp, @message | filter @message like /ERROR/ | sort @timestamp desc | limit 50
```

- JSON 로그에서 특정 필드 기준 필터 (구조화 로그)
```
fields @timestamp, level, msg | filter level = "ERROR" | sort @timestamp desc
```

- 5분 단위 에러 건수 추이 (시계열 집계)
```
filter level = "ERROR" | stats count() as errors by bin(5m)
```

- 상태 코드별 요청 수 (필드 값별 집계)
```
stats count() as cnt by status | sort cnt desc
```

- 경로별 평균/최대 응답시간 (숫자 집계)
```
stats avg(latency) as avg_ms, max(latency) as max_ms, count() as n by path | sort avg_ms desc
```

- p95 / p99 지연 (백분위)
```
stats pct(latency, 95) as p95, pct(latency, 99) as p99 by path | sort p99 desc
```

- 정규식으로 비구조화 로그 필드 추출 (parse)
```
parse @message /(?<ip>\d+\.\d+\.\d+\.\d+) .* "(?<verb>\w+) (?<url>\S+)" (?<code>\d+)/
| stats count() as hits by code, verb | sort hits desc
```

- IP 별 요청 Top 20 (누가 많이 때리나)
```
parse @message /(?<ip>\d+\.\d+\.\d+\.\d+)/
| stats count() as hits by ip | sort hits desc | limit 20
```

- 5xx 응답만 추려 상세 (장애 조사)
```
fields @timestamp, path, status, latency
| filter status >= 500 | sort @timestamp desc | limit 100
```

- 에러율 (%) — 전체 대비 에러 비율
```
stats sum(status >= 500) * 100.0 / count() as error_pct by bin(5m)
```

- Lambda 실행시간·메모리 (REPORT 라인 파싱 — /aws/lambda/* 로그그룹)
```
filter @type = "REPORT"
| stats max(@duration) as max_ms, avg(@duration) as avg_ms, max(@maxMemoryUsed/1000000) as max_mem_mb by bin(5m)
```

- Lambda 콜드스타트 횟수·시간 (Init Duration)
```
filter @message like /Init Duration/
| parse @message /Init Duration: (?<init>[\d.]+) ms/
| stats count() as cold_starts, avg(init) as avg_init_ms by bin(1h)
```

- 특정 요청 ID 추적 (분산 로그에서 한 요청 흐름)
```
fields @timestamp, @message | filter @requestId = "abc-123" | sort @timestamp asc
```

- 고유 사용자 수 (distinct 근사)
```
stats count_distinct(user_id) as uniq_users by bin(1h)
```

- 느린 요청만 (임계 초과)
```
fields @timestamp, path, latency | filter latency > 1000 | sort latency desc | limit 50
```

- 메시지별 빈도 (동일 에러 메시지 뭉치 찾기)
```
stats count() as cnt by @message | sort cnt desc | limit 20
```

- VPC Flow Logs: 거부(REJECT) 트래픽 Top (보안 조사 — flow log 그룹)
```
filter action = "REJECT"
| stats count() as rejects by srcAddr, dstAddr, dstPort | sort rejects desc | limit 20
```

> ★ **자동 필드 주의**: `@type`·`@duration`·`@maxMemoryUsed`·`@requestId`(Lambda 로그), `action`·`srcAddr`(VPC Flow Log)는 CW Logs 가 **해당 로그 그룹**에서만 자동 파싱해 부여한다. 임의 로그그룹에선 없으니, 위 3개(Lambda REPORT/콜드스타트/Flow)는 실제 `/aws/lambda/*`·flow log 그룹에서 써야 한다. (parse 로 원문에서 직접 뽑는 콜드스타트 쿼리는 아무 그룹에서나 동작 — 실검증됨)
