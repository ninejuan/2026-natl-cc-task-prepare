# Cilium

eBPF 기반 네트워킹·보안·관측. **표준 NetworkPolicy 로 안 되는 L7 규칙**(HTTP 메서드·경로 단위 허용)이 필요할 때 꺼낸다.

표준 NetworkPolicy 로 충분한 문제라면 [`../../k8s/netpol/`](../../k8s/netpol/) 만 쓰고 Cilium 은 건드리지 마라. EKS 에서 CNI 를 바꾸는 건 클러스터를 깨뜨릴 수 있는 작업이다.

---

## 실검증 결과 (EKS 1.35 / Cilium 1.20.1 / aws-cni 체이닝)

**깨끗한 클러스터에서는 공식 문서 그대로 잘 동작한다.** 아래 4가지를 실제로 확인했다.

```bash
helm install cilium cilium/cilium --version 1.20.1 -n kube-system \
  --set cni.chainingMode=aws-cni --set cni.exclusive=false \
  --set enableIPv4Masquerade=false --set routingMode=native
```

| 정책 | 결과 |
|---|---|
| L3/L4 (`ciliumnetworkpolicy-l3-l4.yaml`) | frontend 200 / 그 외 타임아웃 |
| L7 HTTP (`ciliumnetworkpolicy-l7-http.yaml`) | `GET /health` 10/10 **200**, `GET /v1/book/` 10/10 **200**, `GET /admin/` 5/5 **403**, `DELETE /v1/book/` **403** |
| FQDN (`ciliumnetworkpolicy-dns-fqdn.yaml`) | 허용 도메인 307, `google.com` 타임아웃, `cilium-dbg fqdn cache list` 에 조회 기록 |
| Clusterwide | 클러스터 내부 200 / 외부 타임아웃, 해제 후 즉시 복구 |

`cilium-dbg status` 확인값: `CNI Chaining: aws-cni`, `Routing: Native`, `Masquerading: Disabled`,
`KubeProxyReplacement: False`, `Proxy Status: OK ... Envoy: external`.

### 🚨 그런데 여기서 클러스터를 한 번 죽였다 — 원인은 "CNI 갈아타기"

처음 시도는 **Calico 를 깔았다 지운 노드 위에** Cilium 을 설치한 것이었다. 결과:

- CoreDNS 가 VPC 리졸버로 못 나가 `0/1` 무한 재시작
  (`HINFO: read udp ...->192.168.0.2:53: i/o timeout`)
- 파드 안에서 `apk add curl` 조차 실패 → **"정책이 막았나" 로 착각하기 딱 좋다**
- `endpointRoutes.enabled`, `ipam.mode=delegated-plugin`, `--local-router-ipv4` 를 더해도 그대로

**노드그룹을 새로 만들어 옛 노드를 버리자마자 같은 값으로 정상 동작했다.**
즉 문제는 Cilium 이 아니라 **이전 CNI 플러그인이 노드에 남긴 잔재**였다.

> **규칙: CNI 정책 엔진을 바꿀 때는 노드를 교체한다.** helm uninstall 만으로는 안 지워진다.
> ```bash
> eksctl create nodegroup -f new-ng.yaml            # 새 노드그룹
> eksctl delete nodegroup --cluster <CL> --name <old> --drain=false
> ```

### 🚨 제거해도 안 돌아온다 — `05-cilium.conflist` 잔재

`helm uninstall cilium` 후에도 노드에 CNI 설정이 남아 **새 파드가 아예 안 뜬다**:

```
Failed to create pod sandbox: plugin type="cilium-cni" failed (add):
  unable to connect to Cilium agent: ... dial unix /var/run/cilium/cilium.sock: no such file or directory
```

CNI 가 죽었으니 복구용 파드도 못 띄운다. **hostNetwork 로 우회**한다:

```yaml
apiVersion: apps/v1
kind: DaemonSet
metadata: {name: cni-cleanup, namespace: kube-system}
spec:
  selector: {matchLabels: {app: cni-cleanup}}
  template:
    metadata: {labels: {app: cni-cleanup}}
    spec:
      hostNetwork: true          # ★ CNI 를 안 거치므로 CNI 가 망가져도 뜬다
      tolerations: [{operator: Exists}]
      containers:
        - name: c
          image: public.ecr.aws/docker/library/alpine:3.21
          securityContext: {privileged: true}
          command: ["sh","-c","rm -f /host/etc/cni/net.d/*cilium*; ls /host/etc/cni/net.d/; sleep 3600"]
          volumeMounts: [{name: cni, mountPath: /host/etc/cni/net.d}]
      volumes:
        - name: cni
          hostPath: {path: /etc/cni/net.d}
```

conflist 를 지워도 eBPF/iptables 잔재까지는 안 없어진다. **확실한 복구는 노드 교체.**

### 현장 판단

| 요구 | 답 |
|---|---|
| 표준 NetworkPolicy (L3/L4) | VPC CNI 내장 정책 → [`../../k8s/netpol/`](../../k8s/netpol/). 설치할 것 없음 |
| 전역 정책 / order / Log 액션 | Calico policy-only → [`../calico/`](../calico/) |
| HTTP 경로·메서드 단위(L7) | Cilium (검증 통과) 또는 Istio AuthorizationPolicy |
| FQDN 기반 egress 제한 | **Cilium 만 된다** (검증 통과) |

CNI 를 아직 안 건드린 클러스터라면 Cilium 체이닝은 안전하게 넣을 수 있다.
이미 다른 정책 엔진을 깔았다 지운 클러스터라면 **먼저 노드를 갈아라.**
CNI 를 건드릴 여유가 없으면 Istio AuthorizationPolicy
([`../istio/authorizationpolicy.yaml`](../istio/authorizationpolicy.yaml))로 L7 요구를 대신할 수 있다.



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
