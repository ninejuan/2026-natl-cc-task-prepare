# Helm

대부분의 CNCF 프로젝트 설치 수단. 현장에서 실제로 치는 명령만 모았다.

## 설치

```bash
curl -sL https://get.helm.sh/helm-v3.19.0-linux-amd64.tar.gz | tar xz
sudo install -m755 linux-amd64/helm /usr/local/bin/helm
helm version
```

## 기본 흐름

```bash
helm repo add <name> <url>
helm repo update
helm upgrade --install <release> <repo>/<chart> \
  -n <ns> --create-namespace \
  --version <chart-version> \
  -f values.yaml \
  --wait --timeout 10m
```

`upgrade --install` 을 쓴다. `install` 은 두 번째 실행에서 이미 존재한다며 실패해서, 현장에서 값을 고쳐 다시 넣을 때 걸린다.

## 값 확인·디버깅

```bash
helm search repo <repo>/<chart> --versions | head          # 설치 가능한 차트 버전
helm show values <repo>/<chart> > /tmp/default-values.yaml # 기본값 전체 (여기서 필요한 키만 골라 쓴다)
helm show values <repo>/<chart> | grep -A5 serviceAccount  # 특정 키만
helm template <release> <repo>/<chart> -f values.yaml      # 실제로 나갈 매니페스트를 눈으로 확인
helm get values <release> -n <ns>                          # 지금 적용된 값
helm get manifest <release> -n <ns>                        # 지금 클러스터에 들어간 매니페스트
helm list -A                                              # 전체 릴리스
```

값 키 이름이 기억 안 나면 `helm show values ... | grep`. 추측해서 넣으면 조용히 무시된다 — Helm은 오타 난 키를 오류로 알려주지 않는다.

## 되돌리기

```bash
helm history <release> -n <ns>
helm rollback <release> <revision> -n <ns>
helm uninstall <release> -n <ns>
```

## CLI 로 값 주기

values 파일 없이 한 줄로 끝낼 때.

```bash
helm upgrade --install argocd argo/argo-cd -n argocd --create-namespace \
  --set server.service.type=LoadBalancer \
  --set-string 'controller.podAnnotations.foo=bar' \
  --set 'serviceAccount.annotations.eks\.amazonaws\.com/role-arn=arn:aws:iam::000000000000:role/x'
```

키에 점이 있으면 `\.` 로 escape한다. IRSA annotation을 `--set` 으로 줄 때 항상 걸리는 지점.

## 함정

- **차트 버전을 고정하라.** `--version` 없이 설치하면 다음에 다른 버전이 깔려서 필드 이름이 바뀐다.
- **CRD는 helm uninstall로 안 지워진다.** 차트를 지웠는데 CRD가 남아 다음 설치가 충돌하면 `kubectl delete crd <name>`.
- **CRD가 차트에 포함 안 된 프로젝트가 있다.** Gateway API, Prometheus Operator 일부 구성은 CRD를 따로 넣어야 한다.
- **`--wait` 는 타임아웃되면 실패로 롤백한다.** LoadBalancer 프로비저닝 때문에 오래 걸릴 수 있으니 `--timeout` 을 넉넉히.
- **네임스페이스는 `--create-namespace`** 로 만든다. 없으면 설치가 실패한다.
