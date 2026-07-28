# CNCF 프로젝트

직종설명서가 대회에서 사용 가능하다고 명시한 프로젝트 목록이다. **여기 없는 서드파티 툴은 쓰지 않는다.**

> CNCF 프로젝트 중 Calico, Cilium, Istio, ArgoCD, Helm, KEDA, Prometheus, Grafana, Loki, Falco,
> Fluentbit/Fluentd, Open Telemetry, Jaeger, CrossPlane, Keycloak, Kyverno, ExternalSecrets 를
> 대회에서 사용할 수 있다.

## 어디에 뭐가 있나

CRD를 들고 오는 프로젝트는 이 디렉토리, 코어 k8s API만 쓰는 건 `../k8s/` 에 있다.

| 프로젝트 | 위치 | 언제 꺼내나 |
|---|---|---|
| Helm | [`helm/`](helm/) | 아래 프로젝트 대부분의 설치 수단. 명령 형태를 먼저 익혀둔다 |
| KEDA | [`keda/`](keda/) | SQS 큐 길이·cron·Prometheus 메트릭으로 파드 스케일 |
| Prometheus | [`prometheus/`](prometheus/) | 메트릭 수집, ServiceMonitor, 알림 규칙 |
| Grafana | [`grafana/`](grafana/) | 대시보드, 데이터소스, 패널 구성 채점 |
| Loki | [`loki/`](loki/) | 로그를 대시보드에서 LogQL로 쿼리 |
| Fluentd | [`fluentd/`](fluentd/) | 로그 **형식 변환**·라우팅이 필요할 때 (Fluent Bit보다 필터가 강함) |
| Fluent Bit | [`../k8s/logging/`](../k8s/logging/) | CRD 없이 ConfigMap+DaemonSet. 로그를 CloudWatch로 흘리는 기본 경로 |
| OpenTelemetry | [`opentelemetry/`](opentelemetry/) | 트레이스/메트릭/로그 수집을 한 콜렉터로 |
| Jaeger | [`jaeger/`](jaeger/) | 분산 트레이싱 UI |
| Kyverno | [`kyverno/`](kyverno/) | 정책으로 파드 차단·변형·생성. VAP로 안 되는 mutate/generate가 필요할 때 |
| Falco | [`falco/`](falco/) | 런타임 침입 탐지, 이상 syscall 감지 |
| ExternalSecrets | [`external-secrets/`](external-secrets/) | Secrets Manager / SSM 값을 k8s Secret으로 동기화 |
| ArgoCD | [`argocd/`](argocd/) | GitOps 배포. CI/CD 모듈에 나옴 |
| Crossplane | [`crossplane/`](crossplane/) | k8s 매니페스트로 AWS 리소스를 만든다 |
| Istio | [`istio/`](istio/) | 서비스 메시, mTLS, 트래픽 분할·재시도·서킷브레이커 |
| Cilium | [`cilium/`](cilium/) | eBPF CNI, L7 네트워크 폴리시, Hubble 관측 |
| Calico | [`calico/`](calico/) | 네트워크 폴리시 (EKS 기본 VPC CNI와 병행 설치) |
| Keycloak | [`keycloak/`](keycloak/) | SAML/OIDC SSO. AWS 콘솔 로그인 연동 |

코어 k8s 쪽에 있는 것: [`../k8s/admission/`](../k8s/admission/) ValidatingAdmissionPolicy(Kyverno 없이 차단),
[`../k8s/scaling/`](../k8s/scaling/) HPA·Karpenter, [`../k8s/netpol/`](../k8s/netpol/) 표준 NetworkPolicy.

## 선택 기준

같은 요구를 두 프로젝트로 풀 수 있을 때.

| 요구 | 먼저 | 대신 쓸 때 |
|---|---|---|
| 파드 생성 차단 | ValidatingAdmissionPolicy (설치 불필요, 1.30+ 내장) | Kyverno — 값을 **변형**하거나 리소스를 **생성**해야 할 때 |
| 파드 스케일 | HPA (metrics-server만) | KEDA — 트리거가 CPU/메모리가 아닐 때 (큐 길이 등) |
| 로그 수집 | Fluent Bit (가볍다) | Fluentd — 형식 변환·조건 분기·다중 목적지가 필요할 때 |
| 네트워크 폴리시 | VPC CNI 내장 NetworkPolicy | Cilium/Calico — L7 규칙이나 클러스터 전역 정책이 필요할 때 |
| 트레이싱 | OpenTelemetry Collector → X-Ray | Jaeger — UI에서 트레이스를 보여줘야 할 때 |
| 시크릿 주입 | Secrets Store CSI Driver | ExternalSecrets — k8s Secret 객체 자체가 필요할 때 |

## 설치 공통

거의 전부 Helm이다. 인터넷이 되는 환경이므로 chart를 바로 당긴다.

```bash
helm repo add <name> <url> && helm repo update
helm upgrade --install <release> <repo>/<chart> -n <ns> --create-namespace -f values.yaml
```

각 디렉토리 `README.md`에 해당 프로젝트의 repo/chart/필수 값이 적혀 있다.

**IRSA가 필요한 프로젝트**(KEDA, ExternalSecrets, Loki, Fluent Bit/Fluentd, Crossplane, OTel)는
Helm 설치 전에 IAM Role을 먼저 만들고 `serviceAccount.annotations` 로 넣는다. 순서를 바꾸면 재설치해야 한다.
