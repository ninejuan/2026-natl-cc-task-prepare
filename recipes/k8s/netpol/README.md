# 표준 NetworkPolicy

파드 간 통신 제한. **VPC CNI 의 네트워크 폴리시 기능을 켜야 실제로 차단된다.** 안 켜면 매니페스트는 받아들여지되 아무것도 막히지 않는다 — 조용히 실패하는 유형이라 위험하다.

L7(HTTP 경로·메서드) 규칙이나 클러스터 전역 정책이 필요하면 [`../../cncf/cilium/`](../../cncf/cilium/) 또는 [`../../cncf/calico/`](../../cncf/calico/).

## 먼저 기능을 켠다

```bash
export CLUSTER=skills-eks R=ap-northeast-2
aws eks update-addon --cluster-name $CLUSTER --addon-name vpc-cni --region $R \
  --resolve-conflicts PRESERVE \
  --configuration-values '{"enableNetworkPolicy":"true"}'
aws eks wait addon-active --cluster-name $CLUSTER --addon-name vpc-cni --region $R

# 켜졌는지 확인
kubectl -n kube-system get ds aws-node \
  -o jsonpath='{.spec.template.spec.containers[?(@.name=="aws-node")].args}{"\n"}'
kubectl -n kube-system get ds aws-node -o yaml | grep -i network-policy
```

## 적용

```bash
kubectl apply -f default-deny-ingress.yaml
kubectl apply -f allow-from-namespace.yaml
kubectl apply -f allow-egress-dns-and-aws.yaml
```

## 파일

| 파일 | 케이스 |
|---|---|
| `default-deny-ingress.yaml` | 네임스페이스 전체 인그레스 기본 차단 |
| `allow-from-namespace.yaml` | 특정 네임스페이스·파드에서만 허용 |
| `allow-egress-dns-and-aws.yaml` | 이그레스 차단 시 DNS + HTTPS 만 허용 |

## 동작 규칙

- **정책이 하나도 없으면 전부 허용.**
- **파드에 정책이 하나라도 걸리면**, 그 방향(`policyTypes`)은 **허용 목록에 없는 것이 전부 차단**된다.
- 여러 정책은 **합집합(OR)** 이다. 하나라도 허용하면 통과.
- 인그레스와 이그레스는 독립적이다. 양쪽을 다 잠그면 양쪽 규칙이 다 필요하다.

## ★ DNS 를 먼저 열어라

이그레스를 잠글 때 가장 자주 밟는 함정. DNS(53/UDP)를 허용하지 않으면 파드가 이름 해석을 못 해 **아무것도** 안 된다. 에러가 "connection refused" 가 아니라 "no such host" 로 나와서 원인을 찾기 어렵다.

```yaml
egress:
  - to:
      - namespaceSelector:
          matchLabels:
            kubernetes.io/metadata.name: kube-system
    ports:
      - { protocol: UDP, port: 53 }
      - { protocol: TCP, port: 53 }
```

## 확인

```bash
kubectl get networkpolicy -n app
kubectl describe networkpolicy default-deny-ingress -n app

# 차단되어야 하는 경로
kubectl run probe --rm -it -n default --image=curlimages/curl --restart=Never -- \
  curl -s -m 5 -o /dev/null -w '%{http_code}\n' http://app-svc.app:8080/health    # 실패해야 정상

# 허용되어야 하는 경로
kubectl run probe --rm -it -n frontend --image=curlimages/curl --restart=Never \
  --labels='app=frontend' -- \
  curl -s -m 5 -o /dev/null -w '%{http_code}\n' http://app-svc.app:8080/health    # 200

# DNS 가 되는지
kubectl run dnstest --rm -it -n app --image=busybox --restart=Never -- nslookup app-svc.app
```

`curlimages/curl` 은 Docker Hub 이라 익명 pull 제한에 걸릴 수 있다. ECR Public 만 쓰려면:

```bash
kubectl run probe --rm -it -n default --restart=Never \
  --image=public.ecr.aws/docker/library/alpine:3.21 -- \
  sh -c 'apk add --no-cache curl >/dev/null 2>&1; curl -s -m 5 -o /dev/null -w "%{http_code}\n" http://app-svc.app:8080/health'
```

`public.ecr.aws/docker/library/curlimages/curl` 은 **존재하지 않는다**(ImagePullBackOff, 실검증).
ECR Public 의 `docker/library/*` 는 Docker 공식 이미지만 미러한다 — `curlimages` 는 공식이 아니다.

## ★ 검증이 끝나면 NetworkPolicy 를 반드시 정리하라

`default-deny-ingress` 를 남겨 두면 그 네임스페이스에서 **다른 모든 것이 조용히 죽는다**(실검증).

- Prometheus 스크레이프 → 타깃 `down`, `context deadline exceeded`, `up == 0`
- Istio 게이트웨이 → 앱 경로만 타임아웃(없는 경로는 404 로 정상 응답해서 더 헷갈린다)
- 다른 네임스페이스의 검증용 파드 → 전부 연결 실패

```bash
kubectl -n app get netpol            # 남아 있는지 먼저 본다
kubectl -n app delete netpol --all   # 필요 없으면
```

정책 적용 로그:

```bash
kubectl -n kube-system logs ds/aws-node -c aws-network-policy-agent --tail=50
```

## 함정

- **기능을 안 켜면 조용히 무시된다.** 정책을 만들었는데 통신이 되면 이걸 먼저 확인하라.
- **`namespaceSelector` 와 `podSelector` 를 같은 `from` 항목의 리스트로 쓰면 OR** 이다. AND 로 묶으려면 **하나의 `from` 항목 안에 둘을 함께** 넣어야 한다.
  ```yaml
  # OR — frontend 네임스페이스의 모든 파드 또는 app=frontend 라벨의 모든 파드
  from:
    - namespaceSelector: {...}
    - podSelector: {...}
  # AND — frontend 네임스페이스의 app=frontend 파드만
  from:
    - namespaceSelector: {...}
      podSelector: {...}
  ```
  이 차이로 의도보다 넓게 열리는 실수가 가장 흔하다.
- **`policyTypes` 를 생략하면** 정의된 규칙에서 추론한다. `egress` 규칙 없이 `policyTypes: [Egress]` 를 쓰면 이그레스 전면 차단이다.
- **kube-system 을 차단하면** DNS·CNI·kubelet 통신이 깨진다. 네임스페이스 전역 정책을 만들 때 제외하라.
- **ALB target-type: ip** 는 ALB 가 파드에 직접 연결한다. 인그레스를 잠그면 ALB 트래픽도 막힌다 — VPC CIDR 을 `ipBlock` 으로 허용해야 한다.
- 채점이 임시 파드를 띄워 curl 하는 항목이 있으면, 그 파드가 정책에 막혀 실패할 수 있다.

## ★ 실검증 (EKS 1.35 + VPC CNI NetworkPolicy, 2026-08-22)

VPC CNI 의 NetworkPolicy 를 켜고 실제 차단/허용을 확인했다.

| 단계 | 결과 |
|---|---|
| 정책 없음 | `wget app-svc:8080/health` → **ok** |
| `default-deny-ingress.yaml` 적용 | **download timed out** (차단) |
| `allow-from-namespace.yaml` 적용 + 호출측에 `app=frontend` 라벨 | **ok** (허용) |
| 라벨 제거 | **timed out** (다시 차단) |

- 정책 반영에 **10~20초** 걸린다. 적용 직후 바로 테스트하면 아직 안 막힌 것처럼 보인다.
- EKS 기본 VPC CNI 는 **NetworkPolicy 를 강제하지 않는다.** 켜야 한다:
  `aws-node` DaemonSet 에 **`aws-eks-nodeagent`** 컨테이너가 생겼는지로 확인한다.
  ```bash
  kubectl -n kube-system get ds aws-node -o jsonpath='{.spec.template.spec.containers[*].name}'
  # aws-node aws-eks-nodeagent   ← nodeagent 가 있어야 정책이 먹는다
  ```

## ★★ NetworkPolicy 켜다가 클러스터를 죽인 실화

`aws eks update-addon --addon-name vpc-cni --configuration-values '{"enableNetworkPolicy":"true"}' --resolve-conflicts OVERWRITE`
를 **`--service-account-role-arn` 없이** 실행했더니:

1. `aws-node` ServiceAccount 의 `eks.amazonaws.com/role-arn` 어노테이션이 **지워졌다**
2. aws-node 가 IRSA 대신 **노드 인스턴스 role 로 폴백** (그 role 엔 CNI 권한이 없다)
3. `ipamd init: failed to retrieve attached ENIs info: UnauthorizedOperation …
   is not authorized to perform: ec2:DescribeNetworkInterfaces` → **CrashLoopBackOff**
4. 그 노드에서 새 파드가 IP 를 못 받는다. 애드온은 `UPDATING` 에서 멈춰 자가복구도 안 된다.

기존 aws-node 파드는 안 죽어서 **당장은 멀쩡해 보인다** — 노드가 재생성되거나 파드가 재시작되는 순간 터진다.

**예방**: 클러스터 만들 때 `cluster.yaml` 의 vpc-cni `configurationValues` 로 켠다.
**복구**:
```bash
RA=$(aws eks describe-addon --cluster-name <cl> --addon-name vpc-cni --query addon.serviceAccountRoleArn --output text)
kubectl -n kube-system annotate sa aws-node eks.amazonaws.com/role-arn="$RA" --overwrite
kubectl -n kube-system delete pod -l k8s-app=aws-node      # 재시작하면 3/3 로 돌아온다
```
