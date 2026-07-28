# Gateway API → ALB

Ingress 의 후속 규격. **경로 외에 메서드·헤더로 라우팅**해야 하거나 과제지가 Gateway API 를 명시하면 쓴다. 단순 진입점이면 [`../ingress-alb/`](../ingress-alb/) 가 짧다.

## ★ 설치 순서 — CRD 를 먼저

**LBC 를 깔아도 Gateway API core CRD 는 안 따라온다.** 이걸 모르면 `resource mapping not found for kind "Gateway"` 로 막힌다.

```bash
# 1) Gateway API core CRD (별도)
kubectl apply -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.5.0/standard-install.yaml
kubectl get crd | grep gateway.networking.k8s.io
#   gatewayclasses / gateways / httproutes / grpcroutes / referencegrants 가 보여야 한다

# 2) LBC v2.14 이상 (v3.0.0 부터 Gateway API GA)
helm upgrade --install aws-load-balancer-controller eks/aws-load-balancer-controller \
  -n kube-system --set clusterName=$CLUSTER \
  --set serviceAccount.create=false --set serviceAccount.name=aws-load-balancer-controller --wait
kubectl -n kube-system get deploy aws-load-balancer-controller \
  -o jsonpath='{.spec.template.spec.containers[0].image}{"\n"}'   # 버전 확인
```

LBC 가 설치되면 `loadbalancerconfigurations.gateway.k8s.aws` 등 LBC 쪽 CRD 가 함께 등록된다. 이건 core CRD 와 별개다.

## 적용

```bash
kubectl apply -f gatewayclass.yaml               # 클러스터 스코프. 한 번만
kubectl apply -f loadbalancerconfiguration.yaml  # Gateway 보다 먼저 (Gateway 가 참조한다)
kubectl apply -f gateway.yaml
kubectl apply -f httproute.yaml
kubectl get gateway app-gw -n app -w             # ADDRESS 에 ALB DNS
```

## 파일

| 파일 | 리소스 |
|---|---|
| `gatewayclass.yaml` | GatewayClass — `controllerName: gateway.k8s.aws/alb` |
| `loadbalancerconfiguration.yaml` | LBC 고유 설정 (scheme·이름·인증서) |
| `gateway.yaml` | Gateway — 리스너 정의 |
| `httproute.yaml` | HTTPRoute — 경로 라우팅 |
| `httproute-header-match.yaml` | 메서드·헤더 분기 (GET/POST 를 다른 백엔드로) |

## Ingress 와의 대응

| Ingress | Gateway API |
|---|---|
| IngressClass | GatewayClass |
| Ingress (리스너 + 규칙 한 덩어리) | Gateway (리스너) + HTTPRoute (규칙) — **분리된다** |
| 어노테이션으로 ALB 설정 | `LoadBalancerConfiguration` CR + `spec.infrastructure.parametersRef` |
| 경로 매칭만 | 경로 + 메서드 + 헤더 + 쿼리 + 가중치 |

리스너와 규칙이 분리되는 게 핵심 차이다. 여러 팀이 같은 Gateway 에 각자 HTTPRoute 를 붙이는 구조를 만들 수 있다.

## 확인

```bash
kubectl get gatewayclass
kubectl get gateway -n app -o jsonpath='{.items[0].status.addresses[0].value}'; echo
kubectl get httproute -n app

# 조건이 True 여야 실제로 ALB 가 붙었다
kubectl get gateway app-gw -n app -o jsonpath='{.status.conditions}' | jq -r '.[] | "\(.type)=\(.status)"'
kubectl get httproute app-route -n app -o jsonpath='{.status.parents[0].conditions}' | jq -r '.[] | "\(.type)=\(.status)"'

GW=$(kubectl get gateway app-gw -n app -o jsonpath='{.status.addresses[0].value}')
curl -s -o /dev/null -w '%{http_code}\n' "http://$GW/health"
```

`HTTPRoute` 의 `ResolvedRefs=False` 면 백엔드 Service 이름·포트가 틀렸다.
`Gateway` 의 `Programmed=False` 면 ALB 프로비저닝이 실패했다 — LBC 로그를 본다.

## 함정

- **core CRD 를 안 깔면 아무것도 안 된다.** 위 설치 순서 1번.
- **`sectionName`** 은 Gateway 리스너의 `name` 을 가리킨다. 오타면 HTTPRoute 가 어디에도 붙지 않는다.
- **`allowedRoutes.namespaces.from: Same`** 이면 Gateway 와 다른 네임스페이스의 HTTPRoute 는 거부된다. 크로스 네임스페이스가 필요하면 `All` + `ReferenceGrant`.
- **`LoadBalancerConfiguration` 은 네임스페이스 스코프**다. Gateway 와 같은 네임스페이스에 둬라.
- **`apiVersion`**: core 리소스는 `gateway.networking.k8s.io/v1`, LBC 확장은 `gateway.k8s.aws/v1beta1`. 섞이기 쉽다.
- **match 규칙은 위에서부터 평가**된다. 구체적인 규칙(메서드 지정)을 먼저, 포괄 규칙을 나중에 둔다.
- 서브넷 태그 요구사항은 Ingress 와 동일하다 — `kubernetes.io/role/elb`.
