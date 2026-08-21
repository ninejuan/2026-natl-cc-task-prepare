# 워크로드 기본

과제지가 "Deployment 와 Service 를 구성하고 이름은 X, Y" 라고 하면 여기서 시작한다.

## 적용

```bash
kubectl apply -f 00-namespace.yaml
kubectl apply -f configmap.yaml
kubectl apply -f serviceaccount.yaml     # IRSA 가 필요하면 ../identity/ 쪽을 쓴다
kubectl apply -f deployment.yaml
kubectl apply -f service.yaml
kubectl apply -f pdb.yaml
```

네임스페이스가 먼저다. 없으면 나머지가 전부 NotFound 로 실패한다.

## 파일

| 파일 | 리소스 |
|---|---|
| `00-namespace.yaml` | Namespace |
| `configmap.yaml` | ConfigMap — 앱 환경변수 (`AWS_REGION`, `TABLE_NAME`) |
| `serviceaccount.yaml` | ServiceAccount |
| `deployment.yaml` | Deployment — probe·preStop·topologySpread·nodeSelector·resources |
| `service.yaml` | Service (ClusterIP) |
| `pdb.yaml` | PodDisruptionBudget |

## 채점이 보는 지점

실제 채점 스크립트가 이렇게 확인한다. `deployment.yaml` 에 이 필드들이 다 들어 있다.

```bash
kubectl get deploy app-deploy -n app -o custom-columns='NAME:.metadata.name,READY:.status.readyReplicas,AVAILABLE:.status.availableReplicas' --no-headers
kubectl get deploy app-deploy -n app -o jsonpath='liveness={.spec.template.spec.containers[0].livenessProbe.httpGet.path} readiness={.spec.template.spec.containers[0].readinessProbe.httpGet.path}{"\n"}graceful={.spec.template.spec.terminationGracePeriodSeconds} preStop={.spec.template.spec.containers[0].lifecycle.preStop}{"\n"}'
kubectl get deploy app-deploy -n app -o jsonpath='topo:{.spec.template.spec.topologySpreadConstraints[0].topologyKey} cpu:{.spec.template.spec.containers[0].resources.requests.cpu} mem:{.spec.template.spec.containers[0].resources.requests.memory}{"\n"}'
kubectl get svc app-svc -n app -o custom-columns='NAME:.metadata.name,TYPE:.spec.type' --no-headers
kubectl get pods -n app -l app=app -o jsonpath='{range .items[*]}{.spec.nodeSelector}{"\n"}{end}' | sort -u
kubectl exec -n app $(kubectl get pods -n app -l app=app -o jsonpath='{.items[0].metadata.name}') -c app -- printenv AWS_REGION TABLE_NAME
```

마지막 명령이 흔하다 — **컨테이너 안에서 환경변수를 실제로 읽어본다.** ConfigMap 을 만들어도 `envFrom` 으로 연결하지 않으면 0점이다.

## 세 가지 probe

| probe | 실패하면 | 언제 쓰나 |
|---|---|---|
| startup | 계속 재시작 | 기동이 느린 앱. 이게 성공할 때까지 liveness 가 대기한다 |
| readiness | 트래픽 제외 (죽이진 않음) | "준비되지 않은 파드에 트래픽이 가지 않아야 한다" |
| liveness | 컨테이너 재시작 | "비정상 상태에서 자동 복구되어야 한다" |

과제지가 "자동 복구" 와 "트래픽 차단" 을 함께 말하면 **liveness + readiness 둘 다** 필요하다. 하나만 넣으면 절반만 득점한다.

## graceful shutdown

"배포 또는 노드 교체 시 진행 중인 요청이 유실되지 않아야 한다" 요구의 답.

```yaml
terminationGracePeriodSeconds: 60
lifecycle:
  preStop:
    exec:
      command: ["sh", "-c", "sleep 15"]
```

`preStop` 의 sleep 이 필요한 이유: 파드가 Terminating 이 되어도 로드밸런서의 타깃 등록 해제가 몇 초 걸린다. 그동안 들어오는 요청을 받아줘야 유실이 없다. `terminationGracePeriodSeconds` 는 preStop + 앱 종료 시간보다 커야 한다.

## 함정

- **`nodeSelector` 라벨이 노드에 없으면 파드가 영구 Pending 이다.** `kubectl get nodes --show-labels` 로 확인. 노드그룹 생성 시 `--labels` 로 박아야 한다.
- **`topologySpreadConstraints` 의 `whenUnsatisfiable`**: `DoNotSchedule` 은 조건을 못 맞추면 파드가 안 뜬다. AZ 수보다 레플리카가 적으면 `ScheduleAnyway` 가 안전하다.
- **`maxUnavailable: 0`** 이면 롤링 업데이트 중 항상 최소 레플리카가 유지된다. 무중단 요구가 있으면 이걸 쓴다.
- **PDB 의 `minAvailable` 을 레플리카 수와 같게 두면** 노드 드레인이 영구 차단된다. Karpenter 가 노드를 정리하지 못한다.
- **`revisionHistoryLimit`** 을 안 줄이면 ReplicaSet 이 10개씩 쌓인다. 채점에 영향은 없지만 조회가 지저분하다.
- 이미지 태그를 `latest` 로 두면 `imagePullPolicy` 가 Always 가 되고, admission 정책(`../admission/`)에 막힐 수 있다.
