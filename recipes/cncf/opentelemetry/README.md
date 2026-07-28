# OpenTelemetry

트레이스·메트릭·로그를 한 파이프라인으로 받아 여러 목적지로 내보낸다. AWS 쪽으로 보낼 때는 X-Ray(트레이스) / CloudWatch EMF(메트릭) 익스포터를 쓴다.

## 세 가지 설치 경로

**① ADOT 애드온 — EKS 라면 가장 빠르다.** AWS 가 관리하는 배포판이고 EKS 애드온으로 한 줄이다. 단 Operator 가 같이 깔려서 `OpenTelemetryCollector` CR 로 설정한다.

```bash
aws eks create-addon --cluster-name skills-eks --addon-name adot \
  --region ap-northeast-2 --resolve-conflicts OVERWRITE
kubectl get pods -n opentelemetry-operator-system
```

**② Helm Collector — 설정을 values 로 끝내고 싶을 때.**

```bash
helm repo add open-telemetry https://open-telemetry.github.io/opentelemetry-helm-charts && helm repo update
helm upgrade --install otel-gateway open-telemetry/opentelemetry-collector \
  -n monitoring --create-namespace -f values-collector-gateway.yaml --wait
```

**③ Helm Operator — 자동 계측(Instrumentation)이 필요할 때.** 앱 코드를 안 고치고 트레이스를 뽑아야 하면 이것뿐이다.

```bash
helm upgrade --install otel-operator open-telemetry/opentelemetry-operator \
  -n opentelemetry-operator-system --create-namespace \
  --set "manager.collectorImage.repository=otel/opentelemetry-collector-k8s" --wait
```

## 파일

| 파일 | 케이스 |
|---|---|
| [`values-collector-gateway.yaml`](values-collector-gateway.yaml) | Deployment 형태 게이트웨이. OTLP 수신 → X-Ray + EMF |
| [`values-collector-agent.yaml`](values-collector-agent.yaml) | DaemonSet 형태 에이전트. 노드/컨테이너 메트릭 수집 |
| [`collector-cr-sidecar.yaml`](collector-cr-sidecar.yaml) | Operator 용 CR. 사이드카 모드 |
| [`instrumentation.yaml`](instrumentation.yaml) | **자동 계측** — annotation 만 붙이면 앱이 트레이스를 보낸다 |
| [`deployment-instrumented.yaml`](deployment-instrumented.yaml) | 자동 계측 annotation 을 붙인 앱 |
| [`serviceaccount.yaml`](serviceaccount.yaml) | X-Ray·CloudWatch 쓰기용 IRSA |

## 익스포터 고르기

| 목적지 | 익스포터 | 필요 IAM |
|---|---|---|
| X-Ray (트레이스) | `awsxray` | `xray:PutTraceSegments`, `xray:PutTelemetryRecords` |
| CloudWatch Metrics | `awsemf` | `cloudwatch:PutMetricData` |
| CloudWatch Logs | `awscloudwatchlogs` | `logs:PutLogEvents` 등 |
| Prometheus (긁히게 노출) | `prometheus` | 없음 |
| Jaeger / 다른 콜렉터 | `otlp` / `otlphttp` | 없음 |
| 디버깅 (stdout) | `debug` | 없음 |

`logging` 익스포터는 `debug` 로 이름이 바뀌었다. 옛 예제를 복사하면 시작 시 죽는다.

## 확인

```bash
kubectl get pods -n monitoring -l app.kubernetes.io/name=opentelemetry-collector
kubectl logs -n monitoring deploy/otel-gateway-opentelemetry-collector --tail=50

# 콜렉터 자체 메트릭으로 실제로 스팬이 들어오고 나가는지 본다
kubectl port-forward -n monitoring deploy/otel-gateway-opentelemetry-collector 8888:8888 &
curl -s localhost:8888/metrics | grep -E 'otelcol_receiver_accepted_spans|otelcol_exporter_sent_spans|otelcol_exporter_send_failed'

# X-Ray 도착 확인
aws xray get-trace-summaries --region ap-northeast-2 \
  --start-time "$(date -u -v-5M +%s 2>/dev/null || date -u -d '5 min ago' +%s)" \
  --end-time "$(date -u +%s)" --query 'TraceSummaries[].Id' --output text
```

`accepted_spans` 가 0 이면 앱이 안 보내는 것, `send_failed` 가 오르면 권한이나 리전 문제다. 이 두 메트릭으로 어느 쪽 문제인지 바로 갈린다.

## 함정

- **`debug` 익스포터를 파이프라인에 하나 넣어두면 디버깅이 빨라진다.** 스팬이 콜렉터까지 왔는지 로그로 바로 보인다.
- **`awsxray` 는 리전을 자동으로 못 찾는 경우가 있다.** `region: ap-northeast-2` 를 명시하라.
- **자동 계측 annotation 은 파드 재생성 시점에 적용된다.** Deployment 에 붙이고 `kubectl rollout restart` 를 해야 사이드카/초기화 컨테이너가 붙는다.
- **자동 계측은 언어별 annotation 이 다르다.** `instrumentation.opentelemetry.io/inject-python`, `-java`, `-nodejs`. 값은 Instrumentation CR 이름 또는 `"true"`.
- **`memory_limiter` 프로세서를 파이프라인 첫 번째에** 둬라. 없으면 트래픽이 몰릴 때 OOM 으로 죽는다.
- 트레이스가 X-Ray 에 뜨는 데 **최대 1분** 걸린다. 채점 대기 3분 안이지만 바로 안 보인다고 설정을 고치지 마라.
