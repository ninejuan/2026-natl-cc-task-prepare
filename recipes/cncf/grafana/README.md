# Grafana

1과제 Observability 항목에서 **대시보드 패널 구성 자체가 채점 대상**이다. 2026 후보 과제지는 패널 타입(Time series / Stat)·이름·배치를 이미지와 똑같이 맞추라고 요구한다.

## 설치

kube-prometheus-stack 에 포함된 Grafana 를 쓰는 게 가장 빠르다 ([`../prometheus/`](../prometheus/) 참조). 별도로 깔아야 하면:

```bash
helm repo add grafana https://grafana.github.io/helm-charts && helm repo update
helm upgrade --install grafana grafana/grafana \
  -n monitoring --create-namespace --version 10.1.2 \
  -f values-grafana.yaml --wait
```

비밀번호 확인:

```bash
kubectl get secret grafana -n monitoring -o jsonpath='{.data.admin-password}' | base64 -d; echo
```

## 파일

| 파일 | 케이스 |
|---|---|
| [`values-grafana.yaml`](values-grafana.yaml) | 설치 값. 데이터소스·사이드카·ALB 노출·계정 |
| [`secret-admin.yaml`](secret-admin.yaml) | 과제지가 지정한 ID/PW 를 Secret 으로 (비번호 포함) |
| [`configmap-datasource-prometheus.yaml`](configmap-datasource-prometheus.yaml) | Prometheus 데이터소스 (사이드카 자동 로드) |
| [`configmap-datasource-loki.yaml`](configmap-datasource-loki.yaml) | Loki 데이터소스 |
| [`configmap-datasource-cloudwatch.yaml`](configmap-datasource-cloudwatch.yaml) | CloudWatch 데이터소스 (IRSA 인증) |
| [`configmap-dashboard.yaml`](configmap-dashboard.yaml) | 대시보드 JSON. 노드 CPU/메모리·파드 상태·Ready 수·응답시간 4패널 |
| [`ingress-alb.yaml`](ingress-alb.yaml) | ALB 로 외부 노출 |

## 대시보드를 만드는 두 가지 길

**① UI 로 만들고 JSON 을 내려받는다** — 패널 배치를 이미지와 똑같이 맞춰야 할 때 이게 빠르다.
대시보드 → Share → Export → View JSON. 그 JSON 을 `configmap-dashboard.yaml` 의 `data` 에 넣으면 재현 가능해진다.

**② ConfigMap 으로 넣는다** — `grafana_dashboard: "1"` label 이 붙은 ConfigMap 을 사이드카가 자동으로 로드한다.
`kubectl apply` 후 30초 이내에 UI 에 나타난다.

시간이 없으면 ①로 만들고 마지막에 JSON 을 ConfigMap 으로 굳혀라. UI 로 만든 대시보드는 파드가 재시작되면 사라진다(SQLite 가 emptyDir 일 때).

## 확인

채점이 실제로 하는 방식 — API 로 대시보드·데이터소스 존재를 확인한다.

```bash
LB=$(kubectl get svc grafana -n monitoring -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
curl -s -u admin:'ChangeMe1234!' "http://$LB/api/health" | jq
curl -s -u admin:'ChangeMe1234!' "http://$LB/api/datasources" | jq -r '.[] | "\(.name) \(.type)"'
curl -s -u admin:'ChangeMe1234!' "http://$LB/api/search?query=" | jq -r '.[].title'
curl -s -u admin:'ChangeMe1234!' "http://$LB/api/dashboards/uid/skills-main" \
  | jq -r '.dashboard.panels[] | "\(.type)\t\(.title)"'
```

마지막 명령이 패널 타입과 제목을 뽑는다. **과제지 이미지의 패널 이름·타입과 한 글자씩 비교**하는 데 쓴다.

## 함정

- **대시보드가 사라진다.** 영속 스토리지 없이 UI 로 만들면 파드 재시작에 날아간다. ConfigMap 으로 굳히거나 PVC 를 붙여라.
- **사이드카 label 은 값이 문자열 `"1"`** 이다. `1` (숫자)로 쓰면 안 붙는다.
- **데이터소스 URL.** kube-prometheus-stack 의 Prometheus 서비스는 `prometheus-operated:9090`, Loki 는 `<release>-loki:3100` 이다. 이름을 추측하지 말고 `kubectl get svc -n monitoring` 으로 확인.
- **ALB 로 노출할 때 `root_url`**. 서브패스로 붙이면 리다이렉트가 깨진다. 루트 경로로 붙이는 게 안전하다.
- **패널 타입 이름**: 과제지의 "Time Series" 는 JSON 에서 `timeseries`, "Stat" 은 `stat`, "Gauge" 는 `gauge` 다.
- **익명 접근을 켜지 마라.** 과제지가 관리자 로그인을 요구하면 로그인 화면이 나와야 한다.
- 계정에 비번호가 들어가는 경우가 많다 (`skills<비번호>` / `HelloKrSkills!<비번호>@`). `$P` 로 조립하고 하드코딩하지 않는다.
