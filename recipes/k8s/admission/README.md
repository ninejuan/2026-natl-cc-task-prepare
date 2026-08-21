# ValidatingAdmissionPolicy

"특정 조건의 Pod 는 생성 불가" 요구의 답. **1.30+ 내장이라 컨트롤러 설치가 없다.** 2024 추가 1과제가 이 형태였다 (`latest` 태그 금지 / 필수 label 강제).

값을 **자동으로 채워야** 하거나 리소스를 **생성**해야 하면 VAP 로는 불가능하다 → [`../../cncf/kyverno/`](../../cncf/kyverno/).

## 적용

정책과 바인딩이 **쌍**이다. 바인딩이 없으면 정책은 아무것도 막지 않는다.

```bash
kubectl apply -f vap-disallow-latest-tag.yaml
kubectl apply -f vap-disallow-latest-tag-binding.yaml
kubectl apply -f vap-require-label.yaml
kubectl apply -f vap-require-label-binding.yaml
kubectl apply -f vap-allowed-registry.yaml
kubectl apply -f vap-allowed-registry-binding.yaml   # ★ 바인딩 없으면 정책이 무동작
```

네임스페이스 셀렉터를 쓰므로 대상 네임스페이스에 label 이 있어야 한다. `kubernetes.io/metadata.name` 은 k8s 가 자동으로 붙인다.

```bash
kubectl create ns prod
kubectl get ns prod -o jsonpath='{.metadata.labels}'; echo   # metadata.name=prod 확인
```

## 파일

| 파일 | 케이스 |
|---|---|
| `vap-disallow-latest-tag.yaml` + `-binding.yaml` | `:latest` 및 태그 없는 이미지 차단 |
| `vap-require-label.yaml` + `-binding.yaml` | 특정 label 존재 + 값까지 강제 |
| `vap-allowed-registry.yaml` + `-binding.yaml` | 허용 ECR 레지스트리만 |

## 자가검증 — 채점이 하는 방식 그대로

통과해야 하는 파드와 거부돼야 하는 파드를 각각 넣어본다. 2024 채점 스크립트가 정확히 이 방식이었다.

```bash
cat <<'EOF' | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: t-pass
  namespace: prod
  labels: { skills.kr/env: prod }
spec:
  containers: [{ name: c, image: "public.ecr.aws/docker/library/alpine:3.21", command: ["sleep","3600"] }]
EOF

cat <<'EOF' | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: t-fail
  namespace: prod
  labels: { skills.kr/env: prod }
spec:
  containers: [{ name: c, image: "public.ecr.aws/docker/library/alpine:latest", command: ["sleep","3600"] }]
EOF

kubectl get pods -n prod
kubectl delete pod t-pass t-fail -n prod --ignore-not-found
```

`t-pass` 는 created, `t-fail` 은 `admission webhook` 거부 메시지가 나와야 한다. 그냥 생성되면 정책이 안 걸린 것이다.

## 확인

```bash
kubectl get validatingadmissionpolicy
kubectl get validatingadmissionpolicybinding
kubectl get validatingadmissionpolicy disallow-latest-tag -o jsonpath='{.status}' | jq
```

`status.typeChecking` 에 CEL 표현식 타입 오류가 보고된다. 정책이 안 걸리면 여기를 먼저 본다.

## CEL 쓰기

`object` 가 검사 대상이다. 자주 쓰는 형태.

```
object.spec.containers.all(c, ...)                          모든 컨테이너
object.spec.containers.exists(c, ...)                       하나라도
!has(object.spec.initContainers) || object.spec.initContainers.all(c, ...)   있을 때만 검사
'key' in object.metadata.labels                             맵 키 존재
object.metadata.labels['skills.kr/env'] == 'prod'           값 비교
c.image.endsWith(':latest')  c.image.startsWith('...')  c.image.contains(':')
has(c.resources.requests) && has(c.resources.requests.cpu)
oldObject != null                                           UPDATE 인지 CREATE 인지
```

`variables` 블록으로 중간값을 만들면 표현식이 짧아진다. `has()` 로 감싸지 않고 없는 필드에 접근하면 평가 오류가 나고, `failurePolicy: Fail` 이면 **모든 요청이 거부된다.**

## 함정

- **바인딩 없이 정책만 넣으면 아무 일도 안 일어난다.** 정책 하나 = 파일 두 개.
- **`validationActions: ["Deny"]`** 를 안 주면 기본이 Deny 지만, `["Warn"]` 이나 `["Audit"]` 으로 잘못 쓰면 통과시킨다. 차단이 목적이면 명시하라.
- **`initContainers` 를 빼먹기 쉽다.** 사이드카/초기화 컨테이너로 `latest` 를 넣으면 통과해버린다.
- **태그 없는 이미지(`nginx`)** 는 `endsWith(':latest')` 로 안 걸린다. `contains(':')` 를 함께 검사해야 한다.
- **`failurePolicy: Fail` + 평가 오류** = 클러스터 전체 파드 생성 불가. `has()` 로 방어하라. 사고가 나면 바인딩을 지우면 즉시 풀린다.
- **Deployment 로 만든 파드도 막힌다.** 이때 Deployment 는 성공하고 ReplicaSet 이벤트에 에러가 남는다. `kubectl describe rs` 로 봐야 이유가 보인다.
- 네임스페이스 라벨 셀렉터를 쓰면 **대상 네임스페이스가 없을 때 정책이 조용히 무효**다.

## ★ 실검증 (kind v1.36.1, 2026-08-22)

정책 3개 + 바인딩 3개를 실제로 적용해 **강제 동작**까지 확인했다.

| 요청 | 결과 |
|---|---|
| `prod` 에 `nginx:latest` | ❌ `denied … 이미지에 명시적 태그가 있어야 하고 ':latest' 는 허용되지 않습니다` |
| `prod` 에 태그 없는 `nginx` | ❌ 위와 동일(`:` 미포함도 걸린다) |
| `prod` 에 `nginx:1.27` (라벨 없음) | ❌ `require-env-label` 이 거부 |
| `prod` 에 외부 레지스트리 이미지 | ❌ `allowed-registry` 가 거부 |
| `prod` 에 ECR 이미지 + `skills.kr/env` 라벨 | ✅ 생성됨 |
| `app`(셀렉터 불일치 ns) 에 `nginx:latest` | ✅ 생성됨 — 바인딩의 `namespaceSelector` 가 정상 작동 |

### ★ 놓치기 쉬운 것 — 정책과 바인딩은 반드시 짝
`allowed-registry` 는 원래 바인딩 파일이 없어서 **적용해도 아무것도 막지 않았다**.
`kubectl get validatingadmissionpolicy` 에는 멀쩡히 보이기 때문에 원인을 찾기 어렵다.
→ `vap-allowed-registry-binding.yaml` 을 추가했다. 정책을 만들면 바인딩도 반드시 같이 만든다.

```bash
# 짝이 맞는지 한 번에 확인
kubectl get validatingadmissionpolicybinding \
  -o jsonpath='{range .items[*]}{.spec.policyName} <- {.metadata.name}{"\n"}{end}'
```
