# Cilium

eBPF 기반 네트워킹·보안·관측. **표준 NetworkPolicy 로 안 되는 L7 규칙**(HTTP 메서드·경로 단위 허용)이 필요할 때 꺼낸다.

표준 NetworkPolicy 로 충분한 문제라면 [`../../k8s/netpol/`](../../k8s/netpol/) 만 쓰고 Cilium 은 건드리지 마라. EKS 에서 CNI 를 바꾸는 건 클러스터를 깨뜨릴 수 있는 작업이다.

## ★ EKS 설치는 두 갈래 — 체이닝을 택하라

| | 체이닝 (권장) | ENI 모드 (전면 교체) |
|---|---|---|
| VPC CNI | 그대로 둔다 | `aws-node` 를 비활성/삭제 |
| IP 할당 | VPC CNI 가 계속 담당 | Cilium 이 ENI 관리 |
| 위험 | 낮다. 되돌리기 쉽다 | **높다.** 잘못하면 전체 파드 통신이 끊긴다 |
| 얻는 것 | L7 정책, Hubble | + 성능, kube-proxy 대체 |

대회에서는 **체이닝만 쓴다.** 얻을 점수 대비 전면 교체의 위험이 압도적으로 크다.

```bash
helm repo add cilium https://helm.cilium.io && helm repo update
helm upgrade --install cilium cilium/cilium --version 1.19.5 \
  -n kube-system -f values-eks-chaining.yaml --wait --timeout 10m

kubectl -n kube-system rollout status ds/cilium
kubectl -n kube-system get pods -l k8s-app=cilium
```

기존 파드는 체이닝 설정을 적용받지 않는다. 정책을 걸 워크로드를 재시작해야 한다.

```bash
kubectl rollout restart deploy -n app
```

## 파일

| 파일 | 케이스 |
|---|---|
| [`values-eks-chaining.yaml`](values-eks-chaining.yaml) | VPC CNI 유지 + Cilium 정책/Hubble. 대회용 |
| [`values-eks-eni.yaml`](values-eks-eni.yaml) | 전면 교체 (참고용, 위험) |
| [`ciliumnetworkpolicy-l7-http.yaml`](ciliumnetworkpolicy-l7-http.yaml) | **HTTP 메서드·경로 단위 허용** — 표준 NetworkPolicy 로 불가 |
| [`ciliumnetworkpolicy-l3-l4.yaml`](ciliumnetworkpolicy-l3-l4.yaml) | 라벨 기반 L3/L4 |
| [`ciliumnetworkpolicy-dns-fqdn.yaml`](ciliumnetworkpolicy-dns-fqdn.yaml) | **FQDN 기반 egress 허용** — 도메인 이름으로 제한 |
| [`ciliumclusterwidenetworkpolicy.yaml`](ciliumclusterwidenetworkpolicy.yaml) | 클러스터 전역 정책 (네임스페이스 무관) |

## Hubble — 통신 흐름 관측

정책이 왜 막았는지 눈으로 확인하는 도구. 디버깅 속도가 완전히 달라진다.

```bash
# values 에서 hubble.relay.enabled=true, hubble.ui.enabled=true 로 켜둠
kubectl -n kube-system port-forward svc/hubble-relay 4245:80 &
hubble observe --namespace app --last 50
hubble observe --namespace app --verdict DROPPED       # 막힌 것만
hubble observe --to-pod app/app-deploy --protocol http

# UI
kubectl -n kube-system port-forward svc/hubble-ui 12000:80 &
```

## 확인

```bash
kubectl -n kube-system exec ds/cilium -- cilium-dbg status --brief
kubectl -n kube-system exec ds/cilium -- cilium-dbg endpoint list | head
kubectl get ciliumnetworkpolicy -A
kubectl describe cnp allow-l7 -n app | tail -20

# 정책이 실제로 막는지
kubectl run probe --rm -it -n app --image=curlimages/curl --restart=Never -- \
  curl -s -o /dev/null -w '%{http_code}\n' -m 5 http://app-svc:8080/admin    # 403 이어야 한다
```

L7 정책이 걸리면 **차단이 TCP 리셋이 아니라 HTTP 403** 으로 온다. 이게 L7 정책이 동작하는 증거다.

## 함정

- **`cni.exclusive=false` 를 빠뜨리면** Cilium 이 CNI 설정을 독점하려 해서 VPC CNI 와 충돌한다. 체이닝의 핵심 플래그다.
- **체이닝에서는 `routingMode=native` + `enableIPv4Masquerade=false`** 를 쓴다. ENI IP 가 VPC 에서 직접 라우팅되므로 터널링·마스커레이딩이 불필요하다.
- **재설치가 위험하다.** `aws-node` 가 라우팅 테이블을 flush 해서 통신이 끊긴다. 재설치할 거면 모든 파드를 재시작할 준비를 하라. 대회 중엔 한 번에 성공시키는 게 낫다.
- **기존 파드는 정책이 안 걸린다.** apply 후 워크로드를 재시작해야 엔드포인트가 Cilium 관리로 들어온다.
- **L7 정책은 `toPorts.rules.http` 안에 넣는다.** `toPorts` 없이 `http` 만 쓰면 무시된다.
- **CiliumNetworkPolicy 와 표준 NetworkPolicy 를 섞으면** 둘 다 적용되어(AND) 예상보다 많이 막힌다. 한쪽으로 통일하라.
- FQDN 정책은 DNS 프록시를 거친다. `toFQDNs` 를 쓰면 **DNS egress(53) 를 반드시 함께 허용**해야 한다.
