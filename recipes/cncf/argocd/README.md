# Argo CD

GitOps 배포. 2025 가이드 "CI/CD" 모듈의 배포 단계에 나온다 (GitHub Actions로 빌드·푸시 → Argo CD가 클러스터에 반영).

## 설치

```bash
helm repo add argo https://argoproj.github.io/argo-helm && helm repo update
helm upgrade --install argocd argo/argo-cd -n argocd --create-namespace --version 8.6.1 \
  --set configs.params."server\.insecure"=true \
  --wait --timeout 10m
```

`server.insecure=true` 를 켜는 이유: ALB에서 HTTP로 받으면 Argo CD 서버가 gRPC/HTTPS 리다이렉트 루프를 만든다. ALB 뒤에 둘 때는 이게 가장 짧은 길이다.

초기 비밀번호:

```bash
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d; echo
```

CLI:

```bash
kubectl port-forward -n argocd svc/argocd-server 8080:80 &
argocd login localhost:8080 --username admin --password "$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d)" --insecure
argocd app list
```

## 파일

| 파일 | 케이스 |
|---|---|
| [`application-directory.yaml`](application-directory.yaml) | Git 디렉토리의 평범한 매니페스트를 그대로 배포 |
| [`application-kustomize.yaml`](application-kustomize.yaml) | kustomize overlay + 이미지 태그 오버라이드 |
| [`application-helm.yaml`](application-helm.yaml) | Helm 차트 + values 인라인 |
| [`application-multisource.yaml`](application-multisource.yaml) | 차트는 업스트림, values 는 우리 Git |
| [`appproject.yaml`](appproject.yaml) | 배포 가능한 repo·네임스페이스·리소스 종류 제한 |
| [`applicationset-git-directory.yaml`](applicationset-git-directory.yaml) | Git 디렉토리마다 Application 자동 생성 |
| [`applicationset-list.yaml`](applicationset-list.yaml) | 목록으로 환경별(dev/stg/prod) Application 생성 |
| [`repository-secret.yaml`](repository-secret.yaml) | 프라이빗 GitHub repo 자격증명 |
| [`ingress-alb.yaml`](ingress-alb.yaml) | ALB로 UI 외부 노출 |

## 확인

```bash
kubectl get application -n argocd
kubectl get application app -n argocd -o jsonpath='{.status.sync.status} {.status.health.status}{"\n"}'   # Synced Healthy
argocd app get app
argocd app sync app                      # 수동 동기화
argocd app history app
```

`Synced` + `Healthy` 가 목표 상태다. `OutOfSync` 로 멈춰 있으면:

```bash
kubectl describe application app -n argocd | tail -30
kubectl logs -n argocd deploy/argocd-repo-server --tail=50      # repo 접근·렌더링 실패
kubectl logs -n argocd statefulset/argocd-application-controller --tail=50
```

## 배포 시간

채점 항목당 5분을 넘길 수 없다는 조건이 2025 가이드에 있다. 기본 폴링 주기가 3분이라 그대로 두면 위험하다.

```bash
# 폴링 주기를 30초로
kubectl -n argocd patch cm argocd-cm --type merge -p '{"data":{"timeout.reconciliation":"30s"}}'
kubectl -n argocd rollout restart deploy/argocd-repo-server
```

또는 GitHub webhook 을 붙이면 즉시 반영된다. 시간 압박이 있으면 폴링 주기 단축이 더 빠르다.

## 함정

- **`syncPolicy.automated` 가 없으면 자동 배포가 안 된다.** "커밋하면 자동으로 반영" 요구에는 `automated: {prune: true, selfHeal: true}` 가 필수.
- **`selfHeal: true` 면 `kubectl edit` 한 변경이 되돌려진다.** 손으로 고쳐서 채점을 통과시키려 하면 Argo CD가 원복시킨다.
- **`CreateNamespace=true`** 없으면 대상 네임스페이스가 없어 실패한다.
- **`targetRevision: HEAD`** 는 기본 브랜치를 따른다. 특정 브랜치면 이름을 명시.
- Application 은 **`argocd` 네임스페이스**에 만든다. 다른 곳에 만들면 무시된다(`sourceNamespaces` 설정 없이는).
- ALB로 노출할 때 `server.insecure` 를 안 켜면 502 또는 리다이렉트 루프가 난다.
- 프라이빗 repo 자격증명 Secret 은 `argocd.argoproj.io/secret-type: repository` label 이 있어야 인식된다.
