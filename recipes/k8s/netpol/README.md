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
