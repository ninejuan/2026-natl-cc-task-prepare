# Istio

서비스 메시. **mTLS, 트래픽 분할(카나리), 재시도·타임아웃·서킷브레이커, 장애 주입**이 필요할 때 꺼낸다.

단순히 외부에서 앱으로 트래픽을 넣는 문제라면 [`../../k8s/ingress-alb/`](../../k8s/ingress-alb/) 나 [`../../k8s/gateway-alb/`](../../k8s/gateway-alb/) 로 끝난다. Istio 는 **서비스 간 통신**을 제어할 때 값을 한다.

## 설치

Helm 3단계. 순서가 정해져 있다.

```bash
helm repo add istio https://istio-release.storage.googleapis.com/charts && helm repo update

# 1. CRD
helm upgrade --install istio-base istio/base -n istio-system --create-namespace --version 1.29.1 --wait
# 2. 컨트롤 플레인
helm upgrade --install istiod istio/istiod -n istio-system --version 1.29.1 --wait
# 3. 인그레스 게이트웨이 (외부 진입이 필요할 때만)
helm upgrade --install istio-ingress istio/gateway -n istio-ingress --create-namespace --version 1.29.1 \
  -f values-ingressgateway-nlb.yaml --wait

kubectl -n istio-system get pods
```

`istioctl` 이 있으면 더 짧다:

```bash
curl -sL https://istio.io/downloadIstio | ISTIO_VERSION=1.29.1 sh -
./istio-1.29.1/bin/istioctl install --set profile=minimal -y
```

## 사이드카 주입

**네임스페이스에 label 을 붙이고 워크로드를 재시작해야** 사이드카가 들어간다. 이걸 빠뜨리면 Istio 리소스가 전부 무력하다.

```bash
kubectl label namespace app istio-injection=enabled --overwrite
kubectl rollout restart deploy -n app
kubectl get pods -n app -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{len(.spec.containers)}{"\n"}{end}'
# 컨테이너가 2개(앱 + istio-proxy)여야 한다
```

## 파일

| 파일 | 케이스 |
|---|---|
| [`00-namespace-injection.yaml`](00-namespace-injection.yaml) | 주입 label 이 붙은 네임스페이스 |
| [`values-ingressgateway-nlb.yaml`](values-ingressgateway-nlb.yaml) | 인그레스 게이트웨이를 NLB 로 노출 |
| [`gateway.yaml`](gateway.yaml) | Istio Gateway (외부 진입점) |
| [`virtualservice-basic.yaml`](virtualservice-basic.yaml) | 경로 기반 라우팅 |
| [`virtualservice-canary.yaml`](virtualservice-canary.yaml) | **가중치 트래픽 분할** 90/10 |
| [`virtualservice-header-route.yaml`](virtualservice-header-route.yaml) | 헤더 기반 분기 + 재시도 + 타임아웃 |
| [`virtualservice-fault-injection.yaml`](virtualservice-fault-injection.yaml) | **장애 주입** — 지연·오류를 인위적으로 |
| [`destinationrule-subsets.yaml`](destinationrule-subsets.yaml) | v1/v2 서브셋 정의 (카나리의 전제) |
| [`destinationrule-circuitbreaker.yaml`](destinationrule-circuitbreaker.yaml) | 서킷브레이커 + 커넥션 풀 |
| [`peerauthentication-mtls.yaml`](peerauthentication-mtls.yaml) | **mTLS 강제** |
| [`authorizationpolicy.yaml`](authorizationpolicy.yaml) | 서비스 간 접근 제어 (L7) |

## 확인

```bash
istioctl proxy-status                          # 사이드카가 컨트롤플레인과 동기화됐는지
istioctl analyze -n app                        # 설정 오류를 미리 잡는다. 가장 먼저 돌려볼 것
istioctl proxy-config routes deploy/app-deploy.app
istioctl proxy-config cluster deploy/app-deploy.app

kubectl get gateway,virtualservice,destinationrule,peerauthentication -n app

# mTLS 가 실제로 걸렸는지
istioctl x describe pod -n app $(kubectl get pod -n app -l app=app -o jsonpath='{.items[0].metadata.name}')
```

카나리 비율 확인 — 100번 호출해 분포를 센다.

```bash
GW=$(kubectl -n istio-ingress get svc istio-ingress -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
for i in $(seq 1 100); do curl -s "http://$GW/version"; echo; done | sort | uniq -c
```

## 함정

- **`istio-injection=enabled` label 을 빼먹으면** 사이드카가 없어 VirtualService·DestinationRule 이 전부 무시된다. Istio 문제의 절반이 이것이다.
- **label 을 붙인 뒤 워크로드를 재시작**해야 한다. 기존 파드에는 소급 적용되지 않는다.
- **`istioctl analyze` 를 먼저 돌려라.** 호스트 이름 오타, DestinationRule 누락 같은 걸 즉시 잡아준다.
- **카나리는 DestinationRule 의 subset 이 먼저 있어야 한다.** VirtualService 만 쓰면 `subset not found` 로 503 이 난다.
- **Gateway 의 `selector` 는 게이트웨이 파드의 label** 이다. Helm `gateway` 차트는 `istio: ingress` 가 아니라 릴리스 이름 기반 label 을 쓸 수 있다. `kubectl get pod -n istio-ingress --show-labels` 로 확인하라.
- **PeerAuthentication `STRICT` 를 네임스페이스 전체에 걸면** 사이드카 없는 파드(예: 채점용 임시 파드)가 통신을 못 한다. 채점이 파드를 띄워 curl 하는 항목이 있으면 주의.
- **ALB 는 Istio Gateway 와 잘 안 맞는다.** NLB 로 노출하거나, ALB → Istio Gateway Service(NodePort/ClusterIP) 로 두 단 구성을 한다. 시간 없으면 NLB.
- 사이드카가 메모리를 먹는다. t3.small 노드에서 사이드카까지 뜨면 리소스가 빡빡하다.
