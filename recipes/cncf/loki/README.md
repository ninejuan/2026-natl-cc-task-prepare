# Loki

컨테이너 로그를 모아 Grafana 에서 LogQL 로 쿼리한다. 2026 가이드 "Container logging" 모듈(Loki + Grafana + EKS)에 명시돼 있다.

## 설치

**차트 12.0.0 부터 `deploymentMode: SingleBinary` 가 `Monolithic` 으로 이름이 바뀌었다.** 옛 이름은 deprecated 다. 대회 규모에선 Monolithic 1레플리카로 충분하다.

```bash
helm repo add grafana https://grafana.github.io/helm-charts && helm repo update
helm search repo grafana/loki --versions | head -3       # 버전 확인 후 아래 --version 을 맞춘다

helm upgrade --install loki grafana/loki \
  -n monitoring --create-namespace \
  -f values-loki-monolithic-s3.yaml --wait --timeout 10m
```

로그 수집 에이전트는 별도다. Loki 는 저장·쿼리만 한다.

```bash
helm upgrade --install alloy grafana/alloy -n monitoring -f values-alloy.yaml --wait
```

## S3 백엔드 준비

```bash
export P=<비번호> R=ap-northeast-2
aws s3api create-bucket --bucket skills-loki-$P --region $R \
  --create-bucket-configuration LocationConstraint=$R
```

Loki ServiceAccount 에 붙일 IAM 정책:

```json
{"Version":"2012-10-17","Statement":[{"Effect":"Allow",
 "Action":["s3:ListBucket","s3:GetObject","s3:PutObject","s3:DeleteObject"],
 "Resource":["arn:aws:s3:::skills-loki-*","arn:aws:s3:::skills-loki-*/*"]}]}
```

MinIO 서브차트로 때울 수도 있지만(`minio.enabled: true`), 2026-10-31 에 제거 예정이고 파드가 하나 더 뜬다. S3 가 낫다.

## 파일

| 파일 | 케이스 |
|---|---|
| [`values-loki-monolithic-s3.yaml`](values-loki-monolithic-s3.yaml) | Monolithic 1레플리카 + S3. 대회용 최소 구성 |
| [`values-loki-minio.yaml`](values-loki-minio.yaml) | S3 없이 클러스터 내부 스토리지로 끝낼 때 |
| [`values-alloy.yaml`](values-alloy.yaml) | Grafana Alloy 로 컨테이너 로그 수집 → Loki (Promtail 후속) |
| [`serviceaccount.yaml`](serviceaccount.yaml) | Loki 용 IRSA |
| [`../grafana/configmap-datasource-loki.yaml`](../grafana/configmap-datasource-loki.yaml) | Grafana 데이터소스 |

## LogQL

Grafana Explore 나 API 로 확인한다. 채점이 특정 로그를 쿼리해 보라고 하는 경우가 있다.

LogQL 은 **두 부분**이다: `{라벨 셀렉터}` + `| 파이프라인`.
라벨 셀렉터는 **반드시 있어야 하고**, 인덱싱된 라벨만 쓸 수 있다.

### ① 라벨 셀렉터 (인덱스 — 여기서 최대한 좁혀라)

```logql
{namespace="app"}                                   네임스페이스 전체
{namespace="app", container="web"}                  라벨 AND
{namespace="app", pod=~"app-deploy-.*"}             정규식
{namespace=~"app|prod"}                             여러 값
{namespace="app", level!="info"}                    부정
```

어떤 라벨이 있는지 모를 때:

```bash
curl -s localhost:3100/loki/api/v1/labels | jq -r '.data[]'
curl -s localhost:3100/loki/api/v1/label/namespace/values | jq -r '.data[]'
```

### ② 라인 필터 (문자열 — 빠르다. 파싱 전에 걸러라)

```logql
{namespace="app"} |= "error"            포함
{namespace="app"} != "/health"          제외
{namespace="app"} |~ "5[0-9]{2}"        정규식 포함
{namespace="app"} !~ "GET /(health|ready)"   정규식 제외
{namespace="app"} |= "error" != "timeout"    체이닝 (앞에서부터 순서대로)
```

### ③ 파서 (구조화)

```logql
{namespace="app"} | json                                JSON 한 줄 로그
{namespace="app"} | logfmt                              key=value 로그
{namespace="app"} | json level="lvl", code="status_code"   필드 이름 바꿔 추출
{namespace="app"} | pattern `<ip> - - <_> "<method> <path> <_>" <status> <_>`   nginx 액세스 로그
{namespace="app"} | regexp `(?P<method>\w+) (?P<path>\S+) (?P<status>\d+)`
{namespace="app"} | unpack                              Promtail/Alloy 가 pack 한 로그
```

### ④ 라벨 필터 (파싱 후 조건)

```logql
{namespace="app"} | json | level="ERROR"
{namespace="app"} | json | status_code >= 500
{namespace="app"} | json | status_code=~"5.."
{namespace="app"} | logfmt | duration > 1s
{namespace="app"} | json | level="ERROR" and path=~"/v1/.*"
{namespace="app"} | json | __error__=""                 파싱 실패한 줄만 버린다
```

파싱 실패한 줄은 `__error__="JSONParserErr"` 가 붙는다. **`| __error__=""` 를 붙이지 않으면
JSON 이 아닌 줄까지 섞여 나온다.**

### ⑤ 포맷 (출력 정리 — 채점 화면용)

```logql
{namespace="app"} | json | line_format "{{.level}} {{.path}} {{.status_code}}"
{namespace="app"} | json | label_format svc=container
{namespace="app"} | json | drop __error__
{namespace="app"} | json | keep level, path, status_code
```

### ⑥ 메트릭 쿼리 (그래프·알림용)

```logql
count_over_time({namespace="app"}[5m])                      5분간 줄 수
sum(rate({namespace="app"} |= "error" [1m]))                에러 로그 발생률(초당)
sum by (pod) (rate({namespace="app"}[1m]))                  파드별 로그 발생률
topk(5, sum by (pod) (count_over_time({namespace="app"}[5m])))
bytes_over_time({namespace="app"}[5m])                      5분간 바이트 수

# 5xx 비율
sum(rate({namespace="app"} | json | status_code=~"5.." [5m]))
  / sum(rate({namespace="app"} | json [5m]))

# 숫자 필드를 값으로 뽑아 통계
avg_over_time({namespace="app"} | json | unwrap duration_ms [5m])
quantile_over_time(0.95, {namespace="app"} | json | unwrap duration_ms [5m]) by (path)
sum by (path) (max_over_time({namespace="app"} | json | unwrap status_code [5m]))
```

`unwrap` 은 **숫자 필드**에만 쓴다. 문자열이면 `__error__="SampleExtractionErr"` 로 빠진다.

### ⑦ 자주 나오는 요구 → 쿼리

| 요구 | 쿼리 |
|---|---|
| 에러 로그만 보여라 | `{namespace="app"} \| json \| level="ERROR"` |
| /health 는 빼고 | `{namespace="app"} != "/health"` |
| 5xx 응답만 | `{namespace="app"} \| json \| status_code >= 500` |
| 파드별 로그량 상위 5 | `topk(5, sum by (pod) (count_over_time({namespace="app"}[5m])))` |
| 분당 에러 건수 그래프 | `sum(count_over_time({namespace="app"} \|= "error" [1m]))` |
| 응답시간 p95 | `quantile_over_time(0.95, {namespace="app"} \| json \| unwrap duration_ms [5m])` |
| 특정 요청 ID 추적 | `{namespace="app"} \|= "req-abc123"` |

CLI 로 확인:

```bash
kubectl port-forward -n monitoring svc/loki 3100:3100 &
curl -s -G http://localhost:3100/loki/api/v1/labels | jq -r '.data[]'
curl -s -G http://localhost:3100/loki/api/v1/label/namespace/values | jq -r '.data[]'
curl -s -G http://localhost:3100/loki/api/v1/query_range \
  --data-urlencode 'query={namespace="app"} | json | level="ERROR"' \
  --data-urlencode "start=$(( $(date +%s) - 300 ))000000000" \
  --data-urlencode "end=$(date +%s)000000000" \
  --data-urlencode 'limit=20' | jq -r '.data.result[].values[][1]'
```

`/loki/api/v1/labels` 가 빈 배열이면 **수집 에이전트가 로그를 안 보내고 있다.** Loki 문제가 아니라 Alloy 문제다.

### LogQL 함정

- **라벨 셀렉터 없이는 쿼리가 안 된다.** `|= "error"` 만 쓰면 `parse error`.
- **고카디널리티 값을 라벨로 올리지 마라**(request_id, user_id). 인덱스가 폭발한다.
  라벨은 namespace/pod/container/level 정도까지. 나머지는 `| json` 으로 파싱해서 쓴다.
- **`|=` 는 파싱 전에** 두는 게 훨씬 빠르다. `| json | line=~"error"` 보다 `|= "error" | json`.
- **`| json` 뒤에 `__error__=""` 를 안 붙이면** 파싱 실패한 줄이 섞인다.
- **시간 범위 기본값이 짧다.** Grafana Explore 는 기본 1시간, API 는 start/end 를 **나노초**로 준다.
- **`unwrap` 대상은 숫자만.** 문자열 필드에 쓰면 결과가 조용히 빈다.

## 확인

```bash
kubectl get pods -n monitoring -l app.kubernetes.io/name=loki
kubectl get svc -n monitoring | grep loki                      # 데이터소스 URL 확인용
curl -s http://localhost:3100/ready
kubectl logs -n monitoring -l app.kubernetes.io/name=alloy --tail=30 | grep -i error
```

## 함정

- **`deploymentMode` 를 지정하지 않으면** 차트 기본값(SimpleScalable)으로 read/write/backend 파드가 여러 개 뜬다. 대회에선 낭비다.
- **다른 모드의 replicas 를 0 으로 내려야 한다.** Monolithic 을 켜도 `read`/`write`/`backend` 기본값이 남아 파드가 같이 뜬다. values 에 전부 0 으로 명시했다.
- **`replication_factor: 1`** 로 둬라. 기본 3 이면 1레플리카에서 쓰기가 실패한다.
- **schema `v13` + `tsdb`** 를 쓴다. 옛 boltdb-shipper 예제를 복사하면 안 맞는다.
- **`allow_structured_metadata: true`** 가 없으면 최신 에이전트가 보낸 메타데이터가 거부된다.
- **Promtail 은 유지보수 종료**됐다. 새로 짤 거면 Alloy 를 쓴다.
- Loki 는 로그를 **label 로만 인덱싱**한다. label 을 파드/네임스페이스 수준으로만 두고, 내용 필터는 `|=` 나 `| json` 으로 한다. 고카디널리티 label 을 만들면 느려진다.
