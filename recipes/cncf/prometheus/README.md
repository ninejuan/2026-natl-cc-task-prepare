# Prometheus (kube-prometheus-stack)

Prometheus + Alertmanager + Grafana + node-exporter + kube-state-metrics 를 한 번에 깐다. 1과제 Observability 항목의 기본 경로.

## 설치

```bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts && helm repo update
helm upgrade --install kps prometheus-community/kube-prometheus-stack \
  -n monitoring --create-namespace --version 78.1.0 \
  -f values-kube-prometheus-stack.yaml --wait --timeout 15m
```

## ★ EKS 에서 반드시 끄는 것

EKS 는 관리형 컨트롤플레인이라 `kube-controller-manager` / `kube-scheduler` / `etcd` / `kube-proxy` 메트릭 엔드포인트가 **노출되지 않는다.** 기본값으로 깔면 이 ServiceMonitor 들이 영구 `Down` 상태로 남고, 과제지가 "노출되지 않는 컴포넌트 수집은 비활성화" 를 요구하면 감점이다.

실제 채점 스크립트가 이걸 센다:

```bash
kubectl get servicemonitor -A -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' \
  | grep -iE "kube-controller-manager|kube-scheduler|kube-etcd" | wc -l    # 0 이어야 한다
```

`values-kube-prometheus-stack.yaml` 에 이미 `enabled: false` 로 넣어뒀다.

## 파일

| 파일 | 케이스 |
|---|---|
| [`values-kube-prometheus-stack.yaml`](values-kube-prometheus-stack.yaml) | 설치 값. EKS 비노출 컴포넌트 비활성 + 보존기간 + 스토리지 |
| [`servicemonitor.yaml`](servicemonitor.yaml) | Service 를 통해 앱 메트릭 수집 |
| [`podmonitor.yaml`](podmonitor.yaml) | Service 없이 파드 직접 수집 |
| [`scrapeconfig.yaml`](scrapeconfig.yaml) | 클러스터 밖 타깃(EC2 등) 수집 |
| [`prometheusrule.yaml`](prometheusrule.yaml) | 알림 규칙 + 기록 규칙 |
| [`service-metrics.yaml`](service-metrics.yaml) | 메트릭 포트를 가진 Service (ServiceMonitor 가 붙을 대상) |

## 확인

```bash
kubectl get pods -n monitoring
kubectl get servicemonitor -A
kubectl get prometheusrule -A

# 타깃이 실제로 UP 인지
kubectl port-forward -n monitoring svc/prometheus-operated 9090:9090 &
curl -s localhost:9090/api/v1/targets | jq -r '.data.activeTargets[] | "\(.labels.job) \(.health)"' | sort -u
curl -s --data-urlencode 'query=up' localhost:9090/api/v1/query | jq -r '.data.result[].metric.job' | sort -u
```

`activeTargets` 에 내 앱 job 이 `up` 으로 없으면 수집이 안 되는 것이다.

## ServiceMonitor 가 안 잡힐 때

이 순서로 본다. 90%가 아래 둘 중 하나다.

1. **`release` label 이 없다.** kube-prometheus-stack 은 기본적으로 자기 release 이름 label 이 붙은 ServiceMonitor 만 본다.
   ```yaml
   metadata:
     labels:
       release: kps        # helm release 이름과 일치해야 한다
   ```
   또는 values 에서 셀렉터를 끈다: `prometheus.prometheusSpec.serviceMonitorSelectorNilUsesHelmValues: false`
2. **포트 이름이 안 맞는다.** ServiceMonitor 의 `endpoints[].port` 는 **Service 의 포트 `name`** 이다. 포트 번호가 아니다.

```bash
kubectl logs -n monitoring prometheus-kps-kube-prometheus-stack-prometheus-0 -c prometheus --tail=50
kubectl get prometheus -n monitoring -o yaml | grep -A5 serviceMonitorSelector
```

## 함정

- **PVC 없이 깔면 파드 재시작에 데이터가 날아간다.** 대회 시간 내라면 `emptyDir` 로도 충분하지만, 채점 중 재시작되면 그래프가 빈다. gp3 StorageClass 가 있으면 붙여라.
- **`retention` 기본 10일.** 대회에선 무의미하니 짧게 두고 메모리를 아낀다.
- **kube-state-metrics 가 파드 상태 메트릭의 출처다.** Grafana 에서 "Pod 상태" 패널을 요구하면 이게 떠 있어야 한다.
- **`prometheus-operated` 가 실제 서비스 이름**이다. Grafana 데이터소스 URL 에 쓸 때 헷갈리기 쉽다.
- **애드온 노드에만 두라는 요구**가 있으면 values 의 각 컴포넌트에 `nodeSelector` 를 넣어야 한다. 컴포넌트가 많아서 하나씩 빠뜨리기 쉽다.
