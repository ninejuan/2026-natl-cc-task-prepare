# Jaeger

분산 트레이싱 UI. 트레이스를 **화면에서 보여줘야** 할 때 쓴다. X-Ray 로 보내면 되는 문제라면 [`../opentelemetry/`](../opentelemetry/) 만으로 끝난다.

## 설치

대회 규모에선 all-in-one 이 정답이다. 메모리 저장이라 파드 하나로 끝나고 Elasticsearch 가 필요 없다.

```bash
kubectl apply -f 00-namespace.yaml
kubectl apply -f deployment-allinone.yaml
kubectl apply -f service.yaml
kubectl apply -f ingress-alb.yaml
```

Helm 으로:

```bash
helm repo add jaegertracing https://jaegertracing.github.io/helm-charts && helm repo update
helm upgrade --install jaeger jaegertracing/jaeger -n observability --create-namespace \
  --set allInOne.enabled=true \
  --set provisionDataStore.cassandra=false \
  --set storage.type=memory \
  --set agent.enabled=false \
  --set collector.enabled=false \
  --set query.enabled=false --wait
```

Operator 를 쓰는 경우 `Jaeger` CR 로 정의한다 ([`jaeger-cr.yaml`](jaeger-cr.yaml)).

## 파일

| 파일 | 케이스 |
|---|---|
| [`00-namespace.yaml`](00-namespace.yaml) | observability 네임스페이스 |
| [`deployment-allinone.yaml`](deployment-allinone.yaml) | all-in-one. OTLP 수신 + UI |
| [`service.yaml`](service.yaml) | UI(16686) + OTLP(4317/4318) |
| [`ingress-alb.yaml`](ingress-alb.yaml) | ALB 로 UI 노출 |
| [`jaeger-cr.yaml`](jaeger-cr.yaml) | Operator 를 깐 경우의 CR |
| [`otel-exporter-patch.yaml`](otel-exporter-patch.yaml) | OTel 콜렉터에서 Jaeger 로 내보내는 설정 조각 |

## 앱 → Jaeger 경로

**Jaeger 1.35 부터 OTLP 를 직접 받는다.** 예전처럼 별도 jaeger-agent 를 붙일 필요가 없다.

```
앱 (OTLP 4317)  →  Jaeger all-in-one  →  UI 16686
앱 (OTLP)  →  OTel Collector  →  Jaeger (otlp exporter)  →  UI      ← 이쪽이 유연하다
```

두 번째 경로를 쓰면 같은 트레이스를 X-Ray 로도 동시에 보낼 수 있다. `exporters: [awsxray, otlp/jaeger]`.

## 확인

```bash
kubectl get pods -n observability -l app=jaeger
ALB=$(kubectl get ingress jaeger -n observability -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')

# 서비스 목록 — 앱이 트레이스를 보내고 있으면 여기 나온다
curl -s "http://$ALB/api/services" | jq -r '.data[]'

# 특정 서비스의 트레이스
curl -s "http://$ALB/api/traces?service=skills-app&limit=5" | jq -r '.data[].traceID'

# 스팬 개수까지
curl -s "http://$ALB/api/traces?service=skills-app&limit=1" | jq '.data[0].spans | length'
```

`/api/services` 가 빈 배열이면 트레이스가 하나도 도착하지 않은 것이다. 앱의 `OTEL_EXPORTER_OTLP_ENDPOINT` 를 먼저 확인한다.

## 함정

- **메모리 저장은 파드 재시작에 전부 날아간다.** 채점 직전에 파드가 재시작되면 트레이스가 0 이다. 채점 전 부하를 한 번 흘려 트레이스를 다시 채워라.
- **`COLLECTOR_OTLP_ENABLED=true`** 가 없으면 4317/4318 을 안 연다 (버전에 따라 기본값이 다르다). 명시하는 게 안전하다.
- **UI 포트는 16686.** ALB healthcheck 경로는 `/` 로 둔다.
- **`--memory.max-traces`** 를 지정하지 않으면 무한히 쌓여 OOM 이 난다.
- 서비스 이름은 앱의 `OTEL_SERVICE_NAME` 에서 온다. 과제지가 서비스 이름을 지정하면 여기를 맞춘다.
