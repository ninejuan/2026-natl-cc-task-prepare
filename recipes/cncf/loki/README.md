# Loki

컨테이너 로그를 모아 Grafana 에서 LogQL 로 쿼리한다. 2026 가이드 "Container logging" 모듈(Loki + Grafana + EKS)에 명시돼 있다.

## 설치

**차트 12.0.0 부터 `deploymentMode: SingleBinary` 가 `Monolithic` 으로 이름이 바뀌었다.** 옛 이름은 deprecated 다. 대회 규모에선 Monolithic 1레플리카로 충분하다.

```bash
helm repo add grafana https://grafana.github.io/helm-charts && helm repo update
helm search repo grafana/loki --versions | head -3       # 버전 확인 후 아래 --version 을 맞춘다

helm upgrade --install loki grafana/loki \
  -n monitoring --create-namespace \
  -f values-loki-monolithic-s3.yaml --wait --timeout 10m
```

로그 수집 에이전트는 별도다. Loki 는 저장·쿼리만 한다.

```bash
helm upgrade --install alloy grafana/alloy -n monitoring -f values-alloy.yaml --wait
```

## S3 백엔드 준비

```bash
export P=<비번호> R=ap-northeast-2
aws s3api create-bucket --bucket skills-loki-$P --region $R \
  --create-bucket-configuration LocationConstraint=$R
```

Loki ServiceAccount 에 붙일 IAM 정책:

```json
{"Version":"2012-10-17","Statement":[{"Effect":"Allow",
 "Action":["s3:ListBucket","s3:GetObject","s3:PutObject","s3:DeleteObject"],
 "Resource":["arn:aws:s3:::skills-loki-*","arn:aws:s3:::skills-loki-*/*"]}]}
```

MinIO 서브차트로 때울 수도 있지만(`minio.enabled: true`), 2026-10-31 에 제거 예정이고 파드가 하나 더 뜬다. S3 가 낫다.

## 파일

| 파일 | 케이스 |
|---|---|
| [`values-loki-monolithic-s3.yaml`](values-loki-monolithic-s3.yaml) | Monolithic 1레플리카 + S3. 대회용 최소 구성 |
| [`values-loki-minio.yaml`](values-loki-minio.yaml) | S3 없이 클러스터 내부 스토리지로 끝낼 때 |
| [`values-alloy.yaml`](values-alloy.yaml) | Grafana Alloy 로 컨테이너 로그 수집 → Loki (Promtail 후속) |
| [`serviceaccount.yaml`](serviceaccount.yaml) | Loki 용 IRSA |
| [`../grafana/configmap-datasource-loki.yaml`](../grafana/configmap-datasource-loki.yaml) | Grafana 데이터소스 |

## LogQL

Grafana Explore 나 API 로 확인한다. 채점이 특정 로그를 쿼리해 보라고 하는 경우가 있다.

```
{namespace="app"}                                        네임스페이스 전체
{namespace="app", pod=~"app-deploy-.*"}                  파드 이름 패턴
{namespace="app"} |= "error"                             문자열 포함
{namespace="app"} != "/health"                           문자열 제외
{namespace="app"} | json | level="ERROR"                 JSON 파싱 후 필드 조건
{namespace="app"} | json | status_code >= 500            숫자 비교
{namespace="app"} | logfmt | duration > 1s
sum(rate({namespace="app"} |= "error" [1m]))             에러 로그 발생률
count_over_time({namespace="app"}[5m])                   5분간 로그 건수
topk(5, sum by (pod) (count_over_time({namespace="app"}[5m])))
```

CLI 로 확인:

```bash
kubectl port-forward -n monitoring svc/loki 3100:3100 &
curl -s -G http://localhost:3100/loki/api/v1/labels | jq -r '.data[]'
curl -s -G http://localhost:3100/loki/api/v1/label/namespace/values | jq -r '.data[]'
curl -s -G http://localhost:3100/loki/api/v1/query_range \
  --data-urlencode 'query={namespace="app"} | json | level="ERROR"' \
  --data-urlencode "start=$(( $(date +%s) - 300 ))000000000" \
  --data-urlencode "end=$(date +%s)000000000" \
  --data-urlencode 'limit=20' | jq -r '.data.result[].values[][1]'
```

`/loki/api/v1/labels` 가 빈 배열이면 **수집 에이전트가 로그를 안 보내고 있다.** Loki 문제가 아니라 Alloy 문제다.

## 확인

```bash
kubectl get pods -n monitoring -l app.kubernetes.io/name=loki
kubectl get svc -n monitoring | grep loki                      # 데이터소스 URL 확인용
curl -s http://localhost:3100/ready
kubectl logs -n monitoring -l app.kubernetes.io/name=alloy --tail=30 | grep -i error
```

## 함정

- **`deploymentMode` 를 지정하지 않으면** 차트 기본값(SimpleScalable)으로 read/write/backend 파드가 여러 개 뜬다. 대회에선 낭비다.
- **다른 모드의 replicas 를 0 으로 내려야 한다.** Monolithic 을 켜도 `read`/`write`/`backend` 기본값이 남아 파드가 같이 뜬다. values 에 전부 0 으로 명시했다.
- **`replication_factor: 1`** 로 둬라. 기본 3 이면 1레플리카에서 쓰기가 실패한다.
- **schema `v13` + `tsdb`** 를 쓴다. 옛 boltdb-shipper 예제를 복사하면 안 맞는다.
- **`allow_structured_metadata: true`** 가 없으면 최신 에이전트가 보낸 메타데이터가 거부된다.
- **Promtail 은 유지보수 종료**됐다. 새로 짤 거면 Alloy 를 쓴다.
- Loki 는 로그를 **label 로만 인덱싱**한다. label 을 파드/네임스페이스 수준으로만 두고, 내용 필터는 `|=` 나 `| json` 으로 한다. 고카디널리티 label 을 만들면 느려진다.
