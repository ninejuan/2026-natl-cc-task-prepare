# `recipes/k8s` · `recipes/cncf` 파일별 검증 등급

2026-08-22 기준. **"전부 완벽히 검증" 이 아니다.** 등급을 나눠 정직하게 적는다.

| 등급 | 뜻 |
|---|---|
| **A** | 실제 EKS 에서 **기능까지** 확인 (요청 200/차단, 스케일, 로그·트레이스 도달 등) |
| **B** | 실제 클러스터에 **apply 는 됐고 리소스도 생성**됐지만, 그 리소스의 **동작을 따로 증명하지는 않음** |
| **C** | server-side dry-run 또는 `helm template` 만 통과 (스키마·문법은 맞음, 실행은 안 해봄) |
| **D** | 동등한 리소스로 우회 검증 (카드 파일 자체를 그대로 적용하진 않음) |

등급 A 가 아닌 항목은 **현장에서 쓸 때 한 번 더 확인**하라는 뜻이다.

---

## recipes/k8s

| 파일 | 등급 | 근거 |
|---|---|---|
| `_cluster/cluster.yaml` | **A** | 이 파일로 검증 클러스터를 실제 생성 (Name 태그 함정도 여기서 발견) |
| `_cluster/cluster-existing-vpc.yaml` | **C** | 같은 수정만 반영. 기존 VPC 에 실제 생성은 안 해봄 |
| `admission/vap-*.yaml` (6) | **A** | 이전 세션에서 검증 — 바인딩 누락(무동작)을 그때 발견해 파일 추가 |
| `gateway-alb/gatewayclass·gateway·httproute·loadbalancerconfiguration·targetgroupconfiguration` | **A** | ALB 생성 + curl 200. `TargetGroupConfiguration` 누락 시 실패도 재현 |
| `gateway-alb/httproute-header-match.yaml` | **C** | dry-run 통과. 헤더 분기 실호출은 Istio 쪽에서만 검증 |
| `identity/serviceaccount-irsa.yaml` | **A** | assumed-role 확인, S3 허용 / EC2 거부 |
| `ingress-alb/*` (3) | **A** | curl 200, TargetGroupBinding 에 파드 IP 2개 등록 |
| `logging/*` (5) | **A** | Fluent Bit → CloudWatch 레코드 도달. 무음 실패 2건도 여기서 발견 |
| `netpol/*` (3) | **A** | deny → allow → re-deny |
| `nlb/service.yaml` | **A** | curl 200 |
| `rbac/role.yaml`, `rolebinding.yaml` | **A** | 이전 세션 `kubectl auth can-i` 로 확인 |
| `scaling/hpa.yaml` | **A** | 396% → 2→4→8→10 |
| `scaling/karpenter-*.yaml` (2) | **A** | t3.small 80초 프로비저닝, consolidation 180초 |
| `storage/*` (5) | **A** | EBS 암호화 gp3 마운트·읽기쓰기, EFS PVC RWX |
| `workload/deployment·service·configmap·serviceaccount·00-namespace` | **A** | 배포·probe·롤링 확인 |
| `workload/pdb.yaml` | **B** | 생성은 확인. 실제 drain 시 차단 동작은 미검증 |

## recipes/cncf

프로젝트 17개 **전부 설치·핵심 동작 확인(A)**. 아래는 그 안에서 **A 가 아닌 개별 파일**만 나열한다.

| 파일 | 등급 | 이유 |
|---|---|---|
| `argocd/repository-secret.yaml` | **C** | 프라이빗 레포 자격증명이 필요. 공개 레포로만 검증 |
| `argocd/ingress-alb.yaml` | **C** | ALB Ingress 패턴 자체는 keycloak 으로 A 검증 |
| `grafana/ingress-alb.yaml` | **C** | 위와 같음 |
| `grafana/secret-admin.yaml` | **D** | 차트가 만든 admin secret 으로 로그인·API 호출까지 확인 |
| `grafana/values-grafana.yaml` | **C** | `helm template` 통과. 단독 grafana 차트는 미설치(kube-prometheus-stack 내장본으로 검증) |
| `prometheus/values-kube-prometheus-stack.yaml` | **C** | `helm template` 통과. 설치는 `--set` 조합으로 함 |
| `prometheus/podmonitor.yaml` | **B** | 생성 확인. 타깃 up 검증은 ServiceMonitor 로만 |
| `prometheus/scrapeconfig.yaml` | **B** | 생성 확인. ec2SD 타깃 발견은 미검증(EC2 노출 앱이 없었음) |
| `loki/values-loki-minio.yaml` | **C** | `helm template` 통과. S3 백엔드 쪽만 A 검증 |
| `loki/serviceaccount.yaml` | **D** | 차트가 만든 동등 SA + IRSA 로 S3 기록까지 확인 |
| `opentelemetry/serviceaccount.yaml` | **D** | 위와 같음 |
| `opentelemetry/deployment-instrumented.yaml` | **D** | ECR 이미지 자리표시자라 동등 python 앱으로 자동계측 → X-Ray 도달 확인 |
| `opentelemetry/values-collector-agent.yaml` | **A** | DaemonSet 설치·기동 확인 |
| `jaeger/ingress-alb.yaml` | **C** | Jaeger CR 의 ingress 로 ALB 생성은 확인 |
| `jaeger/otel-exporter-patch.yaml` | **C** | 콜렉터 config 조각. 병합 후 동작은 미검증 |
| `keda/scaledobject-dynamodb-stream.yaml` | **C** | dry-run 통과. Stream 켜진 테이블이 없어 실동작 미검증 |
| `external-secrets/secretstore-namespaced.yaml` | **C** | dry-run 통과. ClusterSecretStore 경로만 A 검증 |
| `crossplane/providerconfig-secret.yaml` | **C** | 액세스 키 방식. IRSA 방식만 A 검증 |
| `crossplane/bucket.yaml`, `dynamodb-table.yaml` | **D** | 동등 MR 로 실제 S3/DynamoDB 생성 확인. 카드 파일 자체는 dry-run |
| `falco/configmap-custom-rules.yaml` | **B** | ConfigMap 생성 확인. 룰 로드는 `values.customRules` 경로로만 A 검증 |
| `falco/values-falco-sidekick-sns.yaml` | **C** | `helm template` 통과. SNS 연동 미검증 |
| `fluentd/configmap-route-multi-output.yaml` | **C** | `-cloudwatch-` 이미지에 opensearch/s3 플러그인이 없다는 사실을 확인(=이 설정은 그 이미지로는 못 쓴다) |
| `istio/destinationrule-circuitbreaker.yaml` | **B** | 생성 확인. 부하를 걸어 차단 동작까지는 미검증 |
| `kyverno/clusterpolicy-require-label.yaml` | **B** | 정책 Ready 확인. 다른 정책이 먼저 걸려 단독 거부 케이스는 미분리 |
| `cilium/values-eks-eni.yaml` | **C** | 의도적. 전면 교체 모드는 위험해서 `helm template` 까지만 |
| `keycloak/realm-import-aws-saml.json`, `setup-aws-saml.sh`, `ec2-userdata.sh` | **A** | 이전 세션에서 IAM SAML 페더레이션까지 확인 |

### 요약

- `recipes/k8s` 45개 yaml 중 **A 42 / B 1 / C 2**
- `recipes/cncf` 125개 yaml 중 **A 100 / B 5 / C 15 / D 5** (대략치)
- **17개 CNCF 프로젝트는 전부 설치되고 핵심 시나리오가 A 등급으로 동작**했다.
  A 가 아닌 것은 대부분 "자격증명/외부 리소스가 필요해 이 계정에서 재현이 어려운 변형" 이다.
