# Falco

런타임 보안. 컨테이너 안에서 벌어지는 수상한 syscall(쉘 실행, `/etc/shadow` 읽기, 패키지 설치 등)을 감지해 알린다.

## 설치

**EKS 에서는 `driver.kind=modern_ebpf` 를 쓴다.** 커널 모듈을 빌드하지 않아 노드에 아무것도 안 남기고, AL2023 커널에서 바로 동작한다. `kmod` 는 노드마다 모듈 빌드를 시도해서 느리고 실패하기 쉽다.

```bash
helm repo add falcosecurity https://falcosecurity.github.io/charts && helm repo update
helm upgrade --install falco falcosecurity/falco \
  -n falco --create-namespace --version 6.4.2 \
  -f values-falco.yaml --wait --timeout 10m
kubectl get pods -n falco
```

Web UI 까지 한 줄로:

```bash
helm upgrade --install falco falcosecurity/falco -n falco --create-namespace \
  --set driver.kind=modern_ebpf \
  --set tty=true \
  --set falcosidekick.enabled=true \
  --set falcosidekick.webui.enabled=true --wait
```

## 파일

| 파일 | 케이스 |
|---|---|
| [`values-falco.yaml`](values-falco.yaml) | 설치 값. modern_ebpf + JSON 출력 + 커스텀 룰 |
| [`values-falco-sidekick-sns.yaml`](values-falco-sidekick-sns.yaml) | 탐지 이벤트를 SNS/CloudWatch 로 전달 |
| [`configmap-custom-rules.yaml`](configmap-custom-rules.yaml) | 커스텀 룰을 ConfigMap 으로 (values 대신) |
| [`test-pod-trigger.yaml`](test-pod-trigger.yaml) | 일부러 룰을 발동시키는 파드. 자가검증용 |

## 룰 작성

`condition` / `output` / `priority` 세 줄이 핵심이다.

```yaml
- rule: Shell in container
  desc: 컨테이너 안에서 대화형 쉘이 실행됨
  condition: >
    spawned_process and container
    and proc.name in (bash, sh, zsh)
  output: "쉘 실행됨 (user=%user.name container=%container.name cmd=%proc.cmdline)"
  priority: WARNING
  tags: [container, shell]
```

자주 쓰는 필드: `proc.name` `proc.cmdline` `fd.name`(파일 경로) `container.name` `k8s.ns.name` `k8s.pod.name` `user.name` `evt.type`.
매크로: `spawned_process` `container` `open_write` `open_read` `never_true`.

기본 룰셋을 **끄지 말고 덧붙여라.** 기본 룰이 이미 대부분을 잡는다. 커스텀 룰은 과제지가 특정 행위를 지목했을 때만 추가한다.

## 자가검증

```bash
kubectl apply -f test-pod-trigger.yaml
kubectl exec -n app -it falco-trigger -- sh -c 'cat /etc/shadow; id'

# 탐지 로그 확인 (JSON 출력이면 jq 로 바로 파싱된다)
kubectl logs -n falco -l app.kubernetes.io/name=falco -c falco --tail=50 | grep -i 'shadow\|shell'
kubectl logs -n falco -l app.kubernetes.io/name=falco -c falco --tail=100 \
  | grep '^{' | jq -r '"\(.priority)\t\(.rule)\t\(.output_fields."k8s.pod.name")"'
```

로그가 안 나오면 이 순서로 본다.

```bash
kubectl get pods -n falco -o wide                     # 모든 노드에 떠 있나
kubectl logs -n falco -l app.kubernetes.io/name=falco -c falco --tail=30 | head   # 드라이버 로딩 성공했나
kubectl get ds falco -n falco -o jsonpath='{.status.numberReady}/{.status.desiredNumberScheduled}{"\n"}'
```

## 함정

- **`driver.kind` 를 안 정하면** 차트가 환경을 추측한다. EKS 에서는 `modern_ebpf` 를 명시하는 게 확실하다. 커널이 너무 낮으면 `ebpf`(레거시) 로 내려간다.
- **DaemonSet 이라 모든 노드에 떠야 한다.** taint 가 걸린 노드가 있으면 `tolerations: [{operator: Exists}]` 를 넣어라. 안 뜬 노드의 이벤트는 잡히지 않는다.
- **`json_output: true` 를 켜라.** 텍스트 출력은 grep 으로 파싱하기 나쁘고, 채점 시 필드 확인이 어렵다.
- **privileged 컨테이너가 필요하다.** PodSecurity 가 `restricted` 인 네임스페이스에는 못 뜬다. `falco` 네임스페이스를 따로 쓴다.
- **커스텀 룰 파일 이름이 `custom-rules.yaml`** 같은 형태로 `customRules` 키 아래 들어간다. 룰 문법 오류가 있으면 파드가 CrashLoop 이다 — 로그 첫 줄에 이유가 나온다.
- 룰이 너무 넓으면 노이즈로 로그가 폭주한다. `container` 매크로로 호스트 이벤트를 걸러내라.
