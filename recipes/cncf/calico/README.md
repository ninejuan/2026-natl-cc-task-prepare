# Calico

네트워크 폴리시. EKS 에서는 **policy-only 모드**로 쓴다 — VPC CNI 가 IP 를 계속 할당하고 Calico 는 정책만 집행한다.

## 어느 걸 쓸지

| 요구 | 답 |
|---|---|
| 표준 NetworkPolicy 만 필요 | [`../../k8s/netpol/`](../../k8s/netpol/) + VPC CNI 내장 정책 기능. 아무것도 설치하지 않는다 |
| HTTP 경로/메서드 단위 (L7) | [`../cilium/`](../cilium/) |
| 클러스터 전역 정책, 정책 순서(order), 로그 액션 | **Calico** |

VPC CNI 가 NetworkPolicy 를 지원하므로 표준 정책만 필요하면 Calico 를 깔 이유가 없다. 애드온 설정만 켜면 된다.

```bash
aws eks update-addon --cluster-name skills-eks --addon-name vpc-cni \
  --region ap-northeast-2 --resolve-conflicts PRESERVE \
  --configuration-values '{"enableNetworkPolicy":"true"}'
```

## 설치 (policy-only)

Tigera Operator 를 쓰되 `cni.type: AmazonVPC` 로 지정해 IP 할당은 VPC CNI 에 맡긴다. 이게 EKS 에서 안전한 조합이다.

```bash
kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/v3.31.0/manifests/tigera-operator.yaml
kubectl apply -f installation-policy-only.yaml
kubectl -n calico-system get pods
```

Helm 으로:

```bash
helm repo add projectcalico https://docs.tigera.io/calico/charts && helm repo update
helm upgrade --install calico projectcalico/tigera-operator \
  -n tigera-operator --create-namespace --version v3.31.0 \
  -f values-policy-only.yaml --wait
```

## 파일

| 파일 | 케이스 |
|---|---|
| [`installation-policy-only.yaml`](installation-policy-only.yaml) | Operator 용 Installation CR. VPC CNI 유지 |
| [`values-policy-only.yaml`](values-policy-only.yaml) | Helm 설치 값 |
| [`networkpolicy-calico.yaml`](networkpolicy-calico.yaml) | Calico NetworkPolicy — `order` 와 `Log` 액션 |
| [`globalnetworkpolicy.yaml`](globalnetworkpolicy.yaml) | 클러스터 전역 기본 차단 |
| [`globalnetworkset.yaml`](globalnetworkset.yaml) | IP 대역 묶음을 이름으로 참조 (차단 목록) |

## 표준 NetworkPolicy 와 다른 점

Calico 정책만 할 수 있는 것.

```yaml
order: 100          # 정책 평가 순서. 낮은 값이 먼저. 표준 정책엔 순서 개념이 없다
action: Log         # 허용/거부 외에 "로그만 남기기". 무엇이 막힐지 미리 관찰할 때
action: Pass        # 다음 정책 계층으로 넘긴다
namespaceSelector   # 네임스페이스를 선택자로 직접 지정
serviceAccounts     # ServiceAccount 기준 정책
```

## 확인

```bash
kubectl -n calico-system get pods
kubectl get installation default -o jsonpath='{.spec.cni.type}{"\n"}'      # AmazonVPC 여야 한다
kubectl get networkpolicies.projectcalico.org -A
kubectl get globalnetworkpolicies.projectcalico.org

# 정책이 실제로 막는지
kubectl run probe --rm -it -n app --image=curlimages/curl --restart=Never -- \
  curl -s -m 5 -o /dev/null -w '%{http_code}\n' http://app-svc:8080/health
```

`kubectl get networkpolicy` (표준) 와 `kubectl get networkpolicies.projectcalico.org` (Calico) 는 **다른 리소스**다. 헷갈리면 정책이 없다고 착각한다.

## 함정

- **`cni.type: Calico` 로 설치하면 VPC CNI 를 대체한다.** EKS 에서 이러면 기존 파드 IP 체계가 깨진다. **반드시 `AmazonVPC`.**
- **Calico 와 VPC CNI 내장 정책을 동시에 켜면 충돌한다.** 하나만 쓴다.
- **표준 NetworkPolicy 와 Calico 정책은 함께 적용된다.** 둘 다 있으면 교집합만 통과한다.
- **`order` 를 안 주면 기본값(1000)** 이라 의도한 순서가 안 나온다.
- Tigera Operator 설치 후 `Installation` CR 을 안 넣으면 아무것도 안 뜬다. 두 단계다.
- 삭제할 때 Operator 를 먼저 지우면 CR 이 남아 finalizer 에 걸린다. CR → Operator 순서.
