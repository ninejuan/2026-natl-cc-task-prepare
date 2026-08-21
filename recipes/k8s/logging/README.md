# Fluent Bit → CloudWatch Logs

컨테이너 로그를 CloudWatch 로 보낸다. CRD 가 없어 ConfigMap + DaemonSet 만으로 끝나는 가장 가벼운 경로.

- 로그 **형식을 재조립**하거나 여러 목적지로 분기해야 하면 → [`../../cncf/fluentd/`](../../cncf/fluentd/)
- Grafana 에서 **LogQL 로 쿼리**해야 하면 → [`../../cncf/loki/`](../../cncf/loki/)

## IAM 먼저

```bash
export CLUSTER=skills-eks R=ap-northeast-2
ACCOUNT=$(aws sts get-caller-identity --query Account --output text)

cat > /tmp/fb-policy.json <<'JSON'
{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Action":[
  "logs:CreateLogGroup","logs:CreateLogStream","logs:PutLogEvents",
  "logs:DescribeLogStreams","logs:DescribeLogGroups","logs:PutRetentionPolicy"
],"Resource":"*"}]}
JSON
aws iam create-policy --policy-name skills-fluentbit-policy --policy-document file:///tmp/fb-policy.json

eksctl create iamserviceaccount --cluster $CLUSTER --region $R \
  --namespace logging --name fluent-bit \
  --attach-policy-arn arn:aws:iam::$ACCOUNT:policy/skills-fluentbit-policy \
  --approve --override-existing-serviceaccounts
```

`eksctl create iamserviceaccount` 가 네임스페이스와 SA 를 함께 만든다. 그 경우 `00-namespace.yaml`·`serviceaccount.yaml` 은 생략한다.

## 적용

```bash
kubectl apply -f 00-namespace.yaml
kubectl apply -f fluentbit-serviceaccount.yaml    # eksctl 로 만들었으면 생략
kubectl apply -f fluentbit-clusterrole.yaml
kubectl apply -f fluentbit-clusterrolebinding.yaml
kubectl apply -f fluentbit-configmap.yaml
kubectl apply -f fluentbit-daemonset.yaml
kubectl -n logging rollout status ds/fluent-bit
```

## 파일

| 파일 | 리소스 |
|---|---|
| `00-namespace.yaml` | Namespace `logging` |
| `fluentbit-serviceaccount.yaml` | SA + IRSA annotation |
| `fluentbit-clusterrole.yaml` · `-clusterrolebinding.yaml` | 파드 메타데이터 조회 권한 |
| `fluentbit-configmap.yaml` | 파이프라인 — tail → kubernetes → parser → grep → record_modifier → cloudwatch |
| `fluentbit-daemonset.yaml` | DaemonSet (모든 노드) |

## 파이프라인 구성

과제지가 형식과 제외 조건을 지정하는 경우가 많다. ConfigMap 의 필터 순서가 그 답이다.

```
[INPUT tail]          /var/log/containers/app-*.log 를 읽는다 (Parser cri)
[FILTER kubernetes]   네임스페이스·파드·컨테이너 메타데이터를 붙인다
[FILTER parser]       앱이 찍은 JSON 한 줄을 필드로 펼친다
[FILTER grep]         Exclude path ^/health$   ← "/health 로그는 전달하지 않는다"
[FILTER record_modifier]  Whitelist_key 로 요구된 필드만 남긴다
[OUTPUT cloudwatch_logs]  Flush 5 → 10초 내 전달 요구 만족
```

**`record_modifier` 의 `Whitelist_key` 가 형식 일치의 핵심**이다. 이걸 안 쓰면 `kubernetes` 메타데이터 블록이 그대로 나가서 과제지 스키마와 안 맞는다.

## 확인

```bash
kubectl -n logging get ds fluent-bit \
  -o jsonpath='{.status.numberReady}/{.status.desiredNumberScheduled}{"\n"}'
kubectl -n logging logs ds/fluent-bit --tail=50 | grep -iE 'error|warn'

# 로그 그룹·스트림 도착
aws logs describe-log-groups --region $R --log-group-name-prefix /skills/eks \
  --query 'logGroups[].logGroupName' --output text
STREAM=$(aws logs describe-log-streams --region $R --log-group-name /skills/eks/app \
  --order-by LastEventTime --descending --max-items 1 \
  --query 'logStreams[0].logStreamName' --output text)

# ★ 실제 메시지 형식을 눈으로 확인한다. 과제지 스키마와 비교하는 지점.
aws logs get-log-events --region $R --log-group-name /skills/eks/app \
  --log-stream-name "$STREAM" --limit 5 --query 'events[].message' --output text

# /health 가 제외됐는지
aws logs filter-log-events --region $R --log-group-name /skills/eks/app \
  --filter-pattern '"/health"' --max-items 5 --query 'events[].message' --output text
```

마지막 명령이 아무것도 반환하지 않아야 제외가 동작한 것이다.

## 로그가 안 오면

```bash
kubectl -n logging logs ds/fluent-bit --tail=100
kubectl -n logging exec ds/fluent-bit -- ls /var/log/containers | head
kubectl -n logging get sa fluent-bit -o jsonpath='{.metadata.annotations.eks\.amazonaws\.com/role-arn}'; echo
```

1. **IRSA 미설정** — 로그에 `AccessDeniedException`.
2. **`Path` 패턴 불일치** — 컨테이너 로그 파일 이름이 `<pod>_<ns>_<container>-<id>.log` 다. 패턴이 안 맞으면 아무것도 안 읽는다.
3. **`Parser cri` 아님** — containerd 노드에서 `docker` 파서를 쓰면 파싱 실패.
4. **`Mem_Buf_Limit` 초과** — 로그가 많으면 드롭된다.

## 함정

- **DaemonSet 은 모든 노드에 떠야 한다.** `tolerations: [{operator: Exists}]` 를 넣어라. 안 뜬 노드의 로그는 유실된다. 과제지가 "애드온 노드에서만" 을 요구해도 **DaemonSet 은 예외**인 경우가 많다 — 과제지 문구를 확인하라.
- **AL2023/containerd 는 `Parser cri`** 다. `docker` 파서 예제를 복사하면 로그가 원문 그대로 나간다.
- **`Merge_Log On` + `Keep_Log Off`** 를 쓰면 원본 `log` 필드가 사라지고 JSON 필드만 남는다. 원문도 필요하면 `Keep_Log On`.
- **`Flush` 기본값이 크면** 채점 대기(3분) 안에 로그가 안 도착한다. 5초로.
- **`auto_create_group true`** 가 없으면 로그 그룹이 없다고 실패한다. 또는 미리 `create-log-group` 을 해둔다.
- **pos DB 파일**(`/var/log/flb_*.db`)이 hostPath 에 있어야 재시작 후 중복 수집이 없다.
- 로그 그룹 이름이 과제지 지정과 정확히 같아야 한다. `/` 로 시작하는 형태에 주의.
