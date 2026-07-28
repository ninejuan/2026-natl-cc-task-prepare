# Kyverno

정책으로 리소스를 **차단(validate) / 변형(mutate) / 생성(generate)** 한다.

**차단만 필요하면 [`../../k8s/admission/`](../../k8s/admission/) 의 ValidatingAdmissionPolicy 를 먼저 써라** — 1.30+ 내장이라 설치가 없다.
Kyverno 를 꺼내는 이유는 셋 중 하나다: ① 값을 자동으로 **채워 넣어야** 한다 ② 네임스페이스 생성 시 리소스를 **자동 생성**해야 한다 ③ 이미지 서명 검증.

## 설치

```bash
helm repo add kyverno https://kyverno.github.io/kyverno && helm repo update
helm upgrade --install kyverno kyverno/kyverno -n kyverno --create-namespace --version 3.6.4 --wait
kubectl get pods -n kyverno
```

파드가 Running 이 되기까지 웹훅 등록이 끝나야 한다. 바로 정책을 넣으면 첫 요청이 실패할 수 있으니 `--wait` 후 10초 정도 둔다.

## 파일

| 파일 | 케이스 |
|---|---|
| [`clusterpolicy-disallow-latest-tag.yaml`](clusterpolicy-disallow-latest-tag.yaml) | `latest` 태그 차단 (pattern 방식) |
| [`clusterpolicy-require-label.yaml`](clusterpolicy-require-label.yaml) | 필수 label 강제 |
| [`clusterpolicy-allowed-registry.yaml`](clusterpolicy-allowed-registry.yaml) | 허용 레지스트리만 (CEL 방식) |
| [`clusterpolicy-mutate-add-label.yaml`](clusterpolicy-mutate-add-label.yaml) | label 을 **자동으로 붙여준다** (VAP 로 불가) |
| [`clusterpolicy-mutate-nodeselector.yaml`](clusterpolicy-mutate-nodeselector.yaml) | 특정 네임스페이스 파드에 nodeSelector·toleration 자동 주입 |
| [`clusterpolicy-generate-configmap.yaml`](clusterpolicy-generate-configmap.yaml) | 네임스페이스가 생기면 ConfigMap 을 **자동 생성** |
| [`clusterpolicy-require-resources.yaml`](clusterpolicy-require-resources.yaml) | requests/limits 없는 파드 차단 |
| [`policyexception.yaml`](policyexception.yaml) | 특정 워크로드만 정책에서 제외 |
| [`test-pod-pass.yaml`](test-pod-pass.yaml) · [`test-pod-fail.yaml`](test-pod-fail.yaml) | 자가검증용. 하나는 통과, 하나는 거부되어야 정상 |

## 자가검증

채점이 실제로 하는 방식이 이것이다 — 통과해야 하는 파드와 거부돼야 하는 파드를 각각 넣어본다.

```bash
kubectl create ns prod && kubectl label ns prod kubernetes.io/metadata.name=prod --overwrite
kubectl apply -f test-pod-pass.yaml    # created 되어야 한다
kubectl apply -f test-pod-fail.yaml    # admission webhook 이 거부해야 한다
kubectl get pods -n prod
```

거부 메시지가 안 나오고 그냥 생성되면 정책이 안 걸린 것이다. 확인:

```bash
kubectl get clusterpolicy
kubectl get clusterpolicy disallow-latest-tag -o jsonpath='{.spec.rules[0].validate.failureAction}'; echo
kubectl get policyreport -A
kubectl logs -n kyverno -l app.kubernetes.io/component=admission-controller --tail=50
```

## 함정

- **`failureAction` 위치가 버전마다 다르다.** 1.13+ 는 `spec.rules[].validate.failureAction`, 그 이전은 `spec.validationFailureAction`. **`Audit` 이면 경고만 하고 통과시킨다** — 차단이 목적이면 반드시 `Enforce`.
- **`background: true` 인 정책은 기존 리소스도 검사**해서 PolicyReport 를 만든다. 신규 생성만 막으려면 `false`.
- **Deployment 로 넣으면 autogen 규칙이 파드에 적용된다.** Kyverno 는 Deployment/DaemonSet/Job 용 규칙을 자동 생성한다. 반대로 `Pod` 만 match 했는데 Deployment 가 막히는 이유가 이것.
- **정책 이름·label 키의 대소문자**가 채점 대상이다.
- `latest` 를 `!*:latest` 패턴으로 막으면 **태그가 아예 없는 이미지**(`nginx`)는 통과한다. 태그 없음도 막아야 하면 CEL 로 `contains(':')` 를 같이 검사한다.
- Kyverno 웹훅이 죽으면 클러스터 전체 파드 생성이 막힐 수 있다. `failurePolicy` 는 기본 Fail 이다.
