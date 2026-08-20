# Container Logging 플레이북 (2026 #11)

**가이드 원문(2026 #11)** — "**Loki + Grafana** 베이스 로깅 시스템을 EKS 에 배포. 컨테이너 로그 수집, 대시보드에서 쿼리 확인."
- 필수: VPC, Loki, Grafana, EKS, EC2 / 선택: Fluentbit, OpenTelemetry

**트리거 문구** — "Loki 로그 수집", "Grafana 로 로그 쿼리", "컨테이너 로그 대시보드", "LogQL", "Fluent Bit → Loki".

**리전 격리** — 전용 클러스터. EKS 1.35.

**기반 카드**: Loki `../../cncf/loki/`, Grafana `../../cncf/grafana/`, Fluent Bit(k8s) `../../k8s/logging/`, Fluentd `../../cncf/fluentd/`, OTel `../../cncf/opentelemetry/`.

> ECS 중앙 로깅(2025 #9, awslogs/FireLens/CloudWatch)과 **다르다**. 이건 **EKS + Loki/Grafana**(CNCF 스택).

---

## 파이프라인

```
Pod stdout ──> Fluent Bit(DaemonSet) ──push──> Loki(로그 저장/인덱스) <──query── Grafana(LogQL 대시보드)
                 또는 OTel Collector
```

## 케이스 인덱스

| # | 케이스 | 수집기 | 기반 |
|---|---|---|---|
| 01 | Fluent Bit → Loki → Grafana | Fluent Bit DaemonSet | cncf/loki + k8s/logging |
| 02 | Grafana datasource + LogQL 대시보드 | Grafana | cncf/grafana |
| 03 | OTel Collector → Loki | OpenTelemetry | cncf/opentelemetry |
| 04 | 멀티테넌트(X-Scope-OrgID) | Loki tenant | `cases/04-multitenant/` |

## LogQL 쿼리 예시 (Grafana Explore)

```logql
{namespace="app"} |= "ERROR"                          # ERROR 포함 로그
{namespace="app"} | json | level="error"              # JSON 파싱 후 필터
sum(rate({namespace="app"}[5m])) by (pod)             # pod 별 로그율
count_over_time({app="web"} |= "5xx" [1m])            # 1분당 5xx 수
{app="web"} | json | line_format "{{.msg}}"           # 포맷팅
```

## 검증 (채점자 문체)

```bash
aws eks update-kubeconfig --region $R --name lab-eks
kubectl get pods -n loki -o jsonpath='{.items[*].status.phase}'      # Running
kubectl get pods -n monitoring -l app.kubernetes.io/name=grafana -o jsonpath='{.items[0].status.phase}'
# Grafana datasource 로 Loki 등록 확인 + LogQL 결과 (대시보드는 브라우저)
kubectl get daemonset -n logging fluent-bit -o jsonpath='{.status.numberReady}'  # 노드 수만큼
# 로그 실제 수집: 테스트 Pod 로그 발생 → Loki 조회
```

## 함정

- **Fluent Bit 는 DaemonSet**(노드마다) — Loki push output 설정(host/port/labels).
- **Loki 는 스토리지 백엔드**(S3 또는 로컬 PVC) — 멀티테넌트면 X-Scope-OrgID.
- **Grafana datasource = Loki URL** — `http://loki.loki.svc:3100`. LogQL 로 쿼리.
- **flush interval 짧게** — 채점 3분 안에 로그가 Loki 에 도달해야(Fluent Bit flush 1~5초).
- 라벨 카디널리티 주의(pod/namespace OK, 고유값 라벨 금지).
- ECS 로깅(2025 #9)과 혼동 말 것 — 그건 awslogs/FireLens.

## context7 참고

- Loki: https://grafana.com/docs/loki/latest/
- LogQL: https://grafana.com/docs/loki/latest/query/
- Fluent Bit Loki output: https://docs.fluentbit.io/manual/pipeline/outputs/loki
