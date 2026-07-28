# 2026 전국기능경기대회 클라우드컴퓨팅 — 추가과제 스피드런

추가과제는 경기 시작 10분 전에 공개된다. 미리 코드를 못 짜오고, 현장에서 AI 툴이 차단된다.
그래서 이 레포는 **문제 문구 → 디렉토리 → 복붙**으로 끝나게 만든 매니페스트·스크립트 모음이다.

**급하면 여기부터:** [`FIELD-RUNBOOK.md`](FIELD-RUNBOOK.md) (현장 절차·자가채점·체크리스트) · [`WAIT-TIMES.md`](WAIT-TIMES.md) (착수 순서)

## 규약

```bash
export P=<비번호>          # 리소스 이름에 들어가는 비번호
export R=ap-northeast-2    # 해당 항목/모듈이 지정한 리전
```

- **리소스 1개 = 파일 1개.** `---` 로 여러 리소스를 한 파일에 넣지 않는다.
- 디렉토리마다 `README.md` 에 설치 명령·확인 명령·함정이 있다.
- 확인 명령은 실제 채점 스크립트와 같은 문체(`aws --query` + `jq` + `kubectl jsonpath` + `curl`)로 썼다. 근거는 [`_analysis/MARK-PATTERNS.md`](_analysis/MARK-PATTERNS.md).

## 결정 트리 — 문제에 이 단어가 보이면

### 쿠버네티스 (코어) → [`recipes/k8s/`](recipes/k8s/)

| 문구 키워드 | 위치 |
|---|---|
| Deployment, Service, probe, graceful shutdown, topologySpread, PDB | [`k8s/workload/`](recipes/k8s/workload/) |
| Ingress, ALB 연결, TargetGroupBinding | [`k8s/ingress-alb/`](recipes/k8s/ingress-alb/) |
| Gateway API, GatewayClass, HTTPRoute, 메서드·헤더 라우팅 | [`k8s/gateway-alb/`](recipes/k8s/gateway-alb/) |
| Service type LoadBalancer, NLB, TCP 그대로 | [`k8s/nlb/`](recipes/k8s/nlb/) |
| HPA, CPU 기준 스케일, Karpenter, 노드 자동 증설 | [`k8s/scaling/`](recipes/k8s/scaling/) |
| 이미지 태그 제한, 필수 label 강제, Pod 생성 차단 | [`k8s/admission/`](recipes/k8s/admission/) |
| PVC, StatefulSet, EBS, EFS, 볼륨 공유 | [`k8s/storage/`](recipes/k8s/storage/) |
| NetworkPolicy, 파드 간 통신 제한 | [`k8s/netpol/`](recipes/k8s/netpol/) |
| RBAC, Role, Access Entry, 최소권한 | [`k8s/rbac/`](recipes/k8s/rbac/) |
| IRSA, Pod Identity, 파드가 AWS 호출 | [`k8s/identity/`](recipes/k8s/identity/) |
| Fluent Bit, 컨테이너 로그 → CloudWatch, 로그 제외 | [`k8s/logging/`](recipes/k8s/logging/) |
| 클러스터 생성, 애드온, LBC 설치, 파드가 안 뜬다 | [`k8s/README.md`](recipes/k8s/README.md) |

### CNCF 프로젝트 → [`recipes/cncf/`](recipes/cncf/)

직종설명서가 허용한 17개 프로젝트. 전체 목록·선택 기준은 [`cncf/README.md`](recipes/cncf/README.md).

| 문구 키워드 | 위치 |
|---|---|
| SQS 큐 길이로 스케일, cron 스케일, 이벤트 기반 증설 | [`cncf/keda/`](recipes/cncf/keda/) |
| 정책으로 차단·**변형**·**생성**, mutate, generate | [`cncf/kyverno/`](recipes/cncf/kyverno/) |
| Secrets Manager / SSM 값을 k8s Secret 으로 | [`cncf/external-secrets/`](recipes/cncf/external-secrets/) |
| GitOps, 커밋하면 자동 배포, CI/CD 배포 단계 | [`cncf/argocd/`](recipes/cncf/argocd/) |
| Prometheus, 메트릭 수집, ServiceMonitor, 알림 규칙 | [`cncf/prometheus/`](recipes/cncf/prometheus/) |
| Grafana, 대시보드 패널, 데이터소스 | [`cncf/grafana/`](recipes/cncf/grafana/) |
| Loki, LogQL, 로그를 대시보드에서 쿼리 | [`cncf/loki/`](recipes/cncf/loki/) |
| 로그 **형식 변환**, 여러 목적지로 분기 | [`cncf/fluentd/`](recipes/cncf/fluentd/) |
| OpenTelemetry, 트레이스, X-Ray, 자동 계측 | [`cncf/opentelemetry/`](recipes/cncf/opentelemetry/) |
| Jaeger, 트레이스를 화면에서 | [`cncf/jaeger/`](recipes/cncf/jaeger/) |
| 런타임 침입 탐지, 이상 행위 감지 | [`cncf/falco/`](recipes/cncf/falco/) |
| HTTP 경로/메서드 단위 네트워크 정책, FQDN 제한, Hubble | [`cncf/cilium/`](recipes/cncf/cilium/) |
| 클러스터 전역 네트워크 정책, 정책 순서(order) | [`cncf/calico/`](recipes/cncf/calico/) |
| 서비스 메시, mTLS, 카나리, 서킷브레이커, 장애 주입 | [`cncf/istio/`](recipes/cncf/istio/) |
| 매니페스트로 AWS 리소스 생성, 커스텀 API | [`cncf/crossplane/`](recipes/cncf/crossplane/) |
| SAML/OIDC SSO, AWS 콘솔 로그인 연동 | [`cncf/keycloak/`](recipes/cncf/keycloak/) |
| Helm 설치·values 디버깅·rollback | [`cncf/helm/`](recipes/cncf/helm/) |

### AWS 기반

| 문구 키워드 | 위치 |
|---|---|
| VPC, 서브넷, NAT, Flow Log, VPC Endpoint | [`base/vpc-fast.md`](recipes/base/vpc-fast.md) |

## 아직 없음

2과제 모듈 플레이북(Client VPN, RDS Connection, MSK, Managed Flink, VPC Lattice, Step Functions, Network Firewall 등)과 AWS 서비스별 스니펫은 아직 작성하지 않았다. 필요한 것부터 채운다.

## 헬퍼

```bash
bin/bootstrap.sh          # CloudShell/EC2 에 툴 설치 (tf, kubectl, helm, eksctl, jq, yq, psql, mongosh)
bin/discover.sh           # 기존 스택 리소스 ID 전수 스캔 → addon.env (1과제 추가 항목용)
bin/mark-self.sh --foul   # 금지조항 위반 검사
bin/build-all.sh          # ALL.md 재생성 (전체 검색용)
```

## 배경 자료

`_task_sub_guide/` 출제가이드 (2025·2026) · `_additional_task_case/` 과거 추가과제 (재현 대상이 아니라 난이도·채점방식 캘리브레이션용) · `verify/RESULTS.md` 실검증 기록
