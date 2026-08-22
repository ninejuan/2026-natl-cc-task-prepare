# PromQL 쿼리 사전

과제지 문구 → 쿼리로 바로 넘어가기 위한 표. `kube-prometheus-stack` 기본 설치
(node-exporter + kube-state-metrics + cAdvisor)에서 나오는 메트릭 이름 기준이다.

> 이 문서의 모든 표현식은 `promtool check rules` 로 **문법 검증을 통과**했다.
> 메트릭 이름은 kube-prometheus-stack 기본 구성 기준이며, 앱 메트릭(`http_requests_total` 등)은
> 앱이 실제로 무엇을 노출하는지 먼저 확인하고 이름을 바꿔 쓴다.

---

## 0. 시작하기 전에 — 30초 정찰

이름을 추측하지 마라. 실제로 있는 메트릭·라벨을 먼저 본다.

```bash
kubectl -n monitoring port-forward svc/kps-kube-prometheus-stack-prometheus 9090:9090 &

# 메트릭 이름 찾기 (부분 문자열)
curl -s localhost:9090/api/v1/label/__name__/values | jq -r '.data[]' | grep -i cpu

# 특정 메트릭이 가진 라벨과 값
curl -s -G localhost:9090/api/v1/series --data-urlencode 'match[]=kube_pod_status_phase' | jq '.data[0]'

# 쿼리 한 방
curl -s -G localhost:9090/api/v1/query --data-urlencode 'query=up{job="app-metrics"}' | jq '.data.result'

# 타깃이 살아 있나 (여기가 0 이면 쿼리를 아무리 고쳐도 소용없다)
curl -s 'localhost:9090/api/v1/targets?state=active' \
  | jq -r '.data.activeTargets[] | "\(.scrapePool)\t\(.health)\t\(.lastError)"'
```

**빈 결과가 나오면 순서대로 의심한다: ① 타깃이 down ② 메트릭 이름 오타 ③ 라벨 값 오타
④ 시간 범위 밖(`[5m]` 안에 샘플이 2개 미만) ⑤ NetworkPolicy 가 스크레이프를 막음.**

---

## 1. 문법 최소 세트

```promql
http_requests_total                          # instant vector: 모든 시계열의 현재 값
http_requests_total{namespace="app"}         # 라벨 완전일치
http_requests_total{namespace!="kube-system"}# 부정
http_requests_total{pod=~"app-.*"}           # 정규식 일치 (앵커가 자동으로 붙는다)
http_requests_total{status_code!~"2.."}      # 정규식 부정
http_requests_total[5m]                      # range vector: 5분치 원시 샘플 (함수 인자로만 쓴다)
http_requests_total offset 1h                # 1시간 전 값
```

- **counter**(계속 증가): `_total` 접미사. 반드시 `rate()`/`increase()` 를 씌운다. 그냥 쓰면 무의미.
- **gauge**(오르내림): 그대로 쓴다.
- **histogram**: `_bucket` / `_sum` / `_count` 3종이 같이 나온다. 백분위는 `histogram_quantile()`.

## 2. 함수 — 이것만 알면 대부분 된다

| 함수 | 쓰는 곳 |
|---|---|
| `rate(x[5m])` | counter 의 **초당 평균 증가율**. 그래프·알림 기본값 |
| `irate(x[5m])` | 마지막 두 샘플만 본 순간 변화율. **알림에 쓰지 마라**(튄다). 급변 관찰용 |
| `increase(x[5m])` | 5분 동안 **얼마나 늘었나**(건수). `rate * 초` 와 같다 |
| `avg_over_time(x[5m])` | gauge 의 구간 평균. `max_over_time`, `min_over_time`, `stddev_over_time` |
| `histogram_quantile(0.95, ...)` | p95 지연시간 |
| `predict_linear(x[1h], 4*3600)` | 4시간 뒤 예측 (디스크 소진 알림) |
| `delta(x[5m])` | gauge 의 구간 변화량 (counter 에는 `increase`) |
| `changes(x[1h])` | 값이 몇 번 바뀌었나 (재시작 횟수 등) |
| `absent(x)` | 시계열이 **아예 없을 때** 1. "메트릭이 사라졌다" 알림 |
| `clamp_max(x, 100)` | 상한 고정 (퍼센트가 100 넘어 보일 때) |

**`[5m]` 은 스크레이프 간격의 최소 4배로 잡아라.** 15초 간격이면 `[1m]` 이 하한이고,
샘플이 2개 미만이면 `rate()` 가 **아무것도 안 돌려준다**(빈 결과의 흔한 원인).

## 3. 집계

```promql
sum(rate(http_requests_total[5m]))                       # 전부 합
sum by (pod) (rate(http_requests_total[5m]))             # pod 별로 합 (나머지 라벨은 버림)
sum without (instance) (rate(http_requests_total[5m]))   # instance 만 빼고 합
avg by (instance) (node_load5)                            # 평균
max by (namespace) (kube_pod_status_phase{phase="Pending"})
min by (instance) (node_filesystem_avail_bytes{mountpoint="/"})
count by (namespace) (kube_pod_info)                     # 시계열 개수
topk(5, sum by (pod) (rate(http_requests_total[5m])))    # 상위 5개
bottomk(3, sum by (pod) (rate(http_requests_total[5m]))) # 하위 3개
count(up{job="app-metrics"} == 1)                        # 조건을 만족하는 시계열 수
```

`by` 에 안 적은 라벨은 **사라진다.** Grafana 범례가 비면 대개 이것.

---

## 4. 노드 (node-exporter)

```promql
# CPU 사용률 (%) — 노드별
100 - (avg by (instance) (rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100)

# CPU 사용률 — 클러스터 전체 평균
100 - (avg(rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100)

# 메모리 사용률 (%)
100 * (1 - node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes)

# 디스크 사용률 (%) — 루트 파일시스템
100 - (node_filesystem_avail_bytes{mountpoint="/",fstype!="tmpfs"}
       / node_filesystem_size_bytes{mountpoint="/",fstype!="tmpfs"} * 100)

# 4시간 뒤 디스크가 다 찰 노드
predict_linear(node_filesystem_avail_bytes{mountpoint="/"}[1h], 4*3600) < 0

# 네트워크 수신/송신 (bytes/s)
sum by (instance) (rate(node_network_receive_bytes_total{device!~"lo|veth.*"}[5m]))
sum by (instance) (rate(node_network_transmit_bytes_total{device!~"lo|veth.*"}[5m]))

# 로드애버리지 / CPU 코어 수
node_load5 / on(instance) count by (instance) (node_cpu_seconds_total{mode="idle"})

# 노드가 살아 있나 (node-exporter 기준)
up{job="node-exporter"} == 0
```

## 5. 파드·컨테이너 (cAdvisor)

`container=""`(pause 컨테이너)와 `image=""` 를 빼지 않으면 값이 두 배로 보인다.

```promql
# 파드 CPU 사용량 (코어)
sum by (namespace, pod) (rate(container_cpu_usage_seconds_total{container!="",image!=""}[5m]))

# 파드 메모리 사용량 (bytes) — working set 이 실사용에 가깝다
sum by (namespace, pod) (container_memory_working_set_bytes{container!="",image!=""})

# requests 대비 CPU 사용률 (%) — HPA 가 보는 것과 같은 개념
100 * sum by (namespace, pod) (rate(container_cpu_usage_seconds_total{container!=""}[5m]))
    / sum by (namespace, pod) (kube_pod_container_resource_requests{resource="cpu"})

# limits 대비 메모리 사용률 (%) — OOM 예측
100 * sum by (namespace, pod) (container_memory_working_set_bytes{container!=""})
    / sum by (namespace, pod) (kube_pod_container_resource_limits{resource="memory"})

# CPU 스로틀링 비율 (limits 가 너무 낮은지)
sum by (namespace, pod) (rate(container_cpu_cfs_throttled_periods_total{container!=""}[5m]))
  / sum by (namespace, pod) (rate(container_cpu_cfs_periods_total{container!=""}[5m]))

# 컨테이너 재시작 횟수 (최근 1시간)
increase(kube_pod_container_status_restarts_total[1h]) > 0
```

## 6. 워크로드 상태 (kube-state-metrics)

```promql
# Ready 파드 수 / 목표 수
kube_deployment_status_replicas_ready{namespace="app",deployment="app-deploy"}
kube_deployment_spec_replicas{namespace="app",deployment="app-deploy"}

# 목표에 못 미치는 Deployment
kube_deployment_status_replicas_available < kube_deployment_spec_replicas

# Ready 파드가 0 인 Deployment (알림 단골)
kube_deployment_status_replicas_ready{namespace="app"} < 1

# Pending 파드
sum by (namespace) (kube_pod_status_phase{phase="Pending"})

# 안 뜨는 파드 (Waiting 사유별) — CrashLoopBackOff / ImagePullBackOff 를 여기서 본다
sum by (namespace, pod, reason) (kube_pod_container_status_waiting_reason) > 0

# 노드가 Ready 가 아님
kube_node_status_condition{condition="Ready",status="true"} == 0

# 실패한 Job
kube_job_status_failed > 0

# DaemonSet 이 안 뜬 노드 수
kube_daemonset_status_desired_number_scheduled - kube_daemonset_status_number_ready > 0

# PVC 가 Bound 가 아님
kube_persistentvolumeclaim_status_phase{phase!="Bound"} == 1

# HPA 가 최대치에 붙었나
kube_horizontalpodautoscaler_status_current_replicas
  >= kube_horizontalpodautoscaler_spec_max_replicas
```

## 7. 앱 메트릭 (RED — Rate / Errors / Duration)

앱이 노출하는 이름은 프레임워크마다 다르다. 먼저 `/metrics` 를 눈으로 보고 이름을 맞춰라.

```promql
# RPS
sum(rate(http_requests_total{namespace="app"}[5m]))
sum by (path) (rate(http_requests_total{namespace="app"}[5m]))

# 5xx 에러 비율 (0~1)
sum(rate(http_requests_total{namespace="app",status_code=~"5.."}[5m]))
  / sum(rate(http_requests_total{namespace="app"}[5m]))

# 에러 비율 (%) — 분모가 0 일 때 결과가 사라지는 걸 피하려면
100 * sum(rate(http_requests_total{namespace="app",status_code=~"5.."}[5m]))
    / clamp_min(sum(rate(http_requests_total{namespace="app"}[5m])), 0.001)

# p50 / p95 / p99 지연시간 (histogram)
histogram_quantile(0.50, sum by (le) (rate(http_request_duration_seconds_bucket[5m])))
histogram_quantile(0.95, sum by (le) (rate(http_request_duration_seconds_bucket[5m])))
histogram_quantile(0.99, sum by (le, path) (rate(http_request_duration_seconds_bucket[5m])))

# 평균 지연시간 (sum/count) — 백분위가 없을 때
rate(http_request_duration_seconds_sum[5m]) / rate(http_request_duration_seconds_count[5m])

# Apdex 비슷한 것: 0.5초 안에 처리된 비율
sum(rate(http_request_duration_seconds_bucket{le="0.5"}[5m]))
  / sum(rate(http_request_duration_seconds_count[5m]))
```

`histogram_quantile` 은 **`by (le)` 를 반드시 포함**해야 한다. 빼면 결과가 `NaN`.

## 8. 알림 룰 패턴

`for` 는 **조건이 유지돼야 하는 시간**이다. 채점 대기가 3분이면 `for: 1m` 이하로 둔다.

```yaml
groups:
  - name: app.rules
    interval: 15s
    rules:
      - alert: AppPodNotReady
        expr: kube_deployment_status_replicas_ready{namespace="app",deployment="app-deploy"} < 1
        for: 1m
        labels: {severity: critical}
        annotations:
          summary: "{{ $labels.deployment }} 에 Ready 파드가 없습니다"
          description: "현재 {{ $value }} 개"

      - alert: HighErrorRate
        expr: |
          sum(rate(http_requests_total{namespace="app",status_code=~"5.."}[5m]))
            / sum(rate(http_requests_total{namespace="app"}[5m])) > 0.05
        for: 1m
        labels: {severity: warning}

      - alert: PodCrashLooping
        expr: increase(kube_pod_container_status_restarts_total[10m]) > 3
        for: 1m
        labels: {severity: critical}

      - alert: NodeCpuHigh
        expr: 100 - (avg by (instance) (rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100) > 80
        for: 1m
        labels: {severity: warning}

      - alert: NodeMemoryHigh
        expr: 100 * (1 - node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes) > 85
        for: 1m
        labels: {severity: warning}

      - alert: PvcAlmostFull
        expr: |
          100 * kubelet_volume_stats_used_bytes / kubelet_volume_stats_capacity_bytes > 85
        for: 2m
        labels: {severity: warning}

      - alert: TargetDown
        expr: up == 0
        for: 1m
        labels: {severity: critical}

      - alert: MetricMissing            # 메트릭 자체가 사라진 경우
        expr: absent(http_requests_total{namespace="app"})
        for: 2m
        labels: {severity: critical}
```

알림이 안 뜨면 순서대로 본다:

```bash
# 1) 룰이 로드됐나 + health
curl -s localhost:9090/api/v1/rules | jq -r '.data.groups[].rules[] | "\(.name)\t\(.health)\t\(.state // "-")"'
# 2) expr 만 떼서 직접 쿼리 → 결과가 나오나
# 3) for 시간이 지났나 (state: pending → firing)
```

## 9. 레코딩 룰

무거운 쿼리를 미리 계산해 대시보드를 가볍게 한다. 이름은 `수준:메트릭:연산` 관례를 따른다.

```yaml
      - record: app:http_request_rate5m
        expr: sum(rate(http_requests_total{namespace="app"}[5m]))

      - record: app:http_error_ratio5m
        expr: |
          sum(rate(http_requests_total{namespace="app",status_code=~"5.."}[5m]))
            / sum(rate(http_requests_total{namespace="app"}[5m]))

      - record: node:cpu_utilization:ratio
        expr: 1 - avg by (instance) (rate(node_cpu_seconds_total{mode="idle"}[5m]))
```

레코딩 룰은 **정의된 뒤부터** 값이 쌓인다. 만들자마자 과거 구간을 조회하면 비어 있다.

## 10. 벡터 매칭 (두 메트릭을 나눌 때)

```promql
# 라벨 집합이 같아야 1:1 매칭이 된다. 안 맞으면 결과가 빈다.
sum by (pod) (a) / sum by (pod) (b)

# 한쪽에만 있는 라벨은 ignoring 으로 뺀다
rate(a[5m]) / ignoring(status_code) group_left sum without(status_code) (rate(b[5m]))

# 라벨이 다른 메트릭에서 정보만 가져오기 (예: 파드에 노드 라벨 붙이기)
sum by (pod) (rate(container_cpu_usage_seconds_total{container!=""}[5m]))
  * on(pod) group_left(node) kube_pod_info

# 라벨 이름 바꾸기
label_replace(up, "hostname", "$1", "instance", "([^:]+):.*")
```

`many-to-many matching not allowed` 오류가 나면 **한쪽에 `sum by (...)` 를 씌워 1:1 로 줄여라.**

## 11. Grafana 패널에서

```promql
# 대시보드 변수와 함께
sum by (pod) (rate(http_requests_total{namespace="$namespace",pod=~"$pod"}[$__rate_interval]))
```

- `$__rate_interval` 을 쓰면 패널 시간범위에 맞춰 자동으로 커진다. 고정 `[5m]` 보다 안전하다.
- Legend 는 `{{pod}}` / `{{instance}}` 처럼 라벨을 그대로 쓴다.
- 패널 단위(unit)를 `percent(0-100)` / `bytes(SI)` / `s` 로 맞춰야 화면이 과제지 그림과 같아진다.
- **패널의 `datasource.uid` 는 실제 데이터소스 uid 와 대소문자까지 같아야 한다**
  (`Prometheus` ≠ `prometheus`) — 안 맞으면 패널이 빈 채로 그려진다.

## 12. 함정 정리

- **counter 를 `rate()` 없이 쓴다** → 재시작 때마다 뚝 떨어지는 무의미한 그래프.
- **`[1m]` 인데 스크레이프 간격이 30초** → 샘플 2개 미만이면 `rate()` 가 빈 결과.
- **`by (le)` 누락** → `histogram_quantile` 이 `NaN`.
- **`container!=""` 누락** → cAdvisor pause 컨테이너까지 세어 값이 부풀려진다.
- **분모가 0** → 나눗셈 결과 시계열이 통째로 사라진다. `clamp_min(..., 0.001)` 로 방어.
- **라벨 집합 불일치** → 나눗셈 결과가 빈다. 양쪽에 같은 `by` 를 씌워라.
- **정규식은 완전일치로 앵커된다** → `pod=~"app"` 은 `app-abc` 를 **안** 잡는다. `pod=~"app.*"`.
- **NetworkPolicy** 가 걸린 네임스페이스는 스크레이프가 타임아웃한다(`up == 0`).
  쿼리를 고치기 전에 `/api/v1/targets` 부터 봐라.
- **레코딩 룰·알림은 만든 뒤부터** 평가된다. 과거 데이터로 소급되지 않는다.
- **kube-state-metrics 가 없으면** `kube_*` 메트릭이 전부 없다. `up{job=~".*kube-state-metrics.*"}` 확인.
