# Fluentd

Fluent Bit 과 같은 자리(로그 수집)지만 **형식 변환·조건 분기·다중 목적지**가 필요할 때 이쪽을 쓴다.

| | Fluent Bit | Fluentd |
|---|---|---|
| 메모리 | ~수십 MB | ~수백 MB |
| 필터 | 제한적 (grep, record_modifier, lua) | Ruby 로 뭐든 (`record_transformer` + `enable_ruby`) |
| 목적지 분기 | 어려움 | `<match>` 태그로 자연스럽게 |
| 언제 | 그냥 CloudWatch 로 흘릴 때 | **필드를 재조립**하거나 로그를 여러 곳으로 나눠 보낼 때 |

Fluent Bit 구성은 [`../../k8s/logging/`](../../k8s/logging/) 에 있다.

## 설치

DaemonSet 매니페스트를 직접 넣는 게 빠르다. Helm 도 있다:

```bash
helm repo add fluent https://fluent.github.io/helm-charts && helm repo update
helm upgrade --install fluentd fluent/fluentd -n logging --create-namespace --version 0.5.3
```

이미지는 목적지 플러그인이 포함된 태그를 골라야 한다. CloudWatch 로 보낼 거면 `fluent-plugin-cloudwatch-logs` 가 들어간 이미지가 필요하다.
`fluent/fluentd-kubernetes-daemonset:v1.17-debian-cloudwatch-1` 처럼 목적지가 이름에 붙은 태그를 쓴다. `-s3-`, `-opensearch-`, `-cloudwatch-` 등이 있다.

## 파일

| 파일 | 케이스 |
|---|---|
| [`00-namespace.yaml`](00-namespace.yaml) | logging 네임스페이스 |
| [`serviceaccount.yaml`](serviceaccount.yaml) | IRSA |
| [`clusterrole.yaml`](clusterrole.yaml) · [`clusterrolebinding.yaml`](clusterrolebinding.yaml) | 파드 메타데이터 조회 권한 |
| [`configmap-reformat-cloudwatch.yaml`](configmap-reformat-cloudwatch.yaml) | **로그 형식 변환** — 중첩 필드를 평탄화하고 지정된 스키마로 재조립 |
| [`configmap-route-multi-output.yaml`](configmap-route-multi-output.yaml) | 에러는 OpenSearch, 나머지는 S3 로 분기 |
| [`daemonset.yaml`](daemonset.yaml) | DaemonSet |

## 형식 변환의 핵심

과제지가 "로그가 아래 형식으로 저장되어야 한다" 며 스키마를 주면 이 세 가지를 조합한다.

```
<filter>
  @type parser            # 문자열 log 필드를 JSON 으로 파싱
</filter>
<filter>
  @type record_transformer
  enable_ruby true        # Ruby 식으로 필드를 새로 만든다
  <record>
    client_ip ${record["kubernetes"]["pod_ip"]}
  </record>
  remove_keys kubernetes,docker,stream    # 요구되지 않은 필드는 지운다
</filter>
```

`remove_keys` 를 빠뜨리면 `kubernetes` 같은 거대한 메타데이터 블록이 그대로 나가서 채점 시 형식 불일치가 된다. **요구된 필드만 남기는 것**이 포인트.

## 확인

```bash
kubectl get pods -n logging -o wide
kubectl logs -n logging -l app=fluentd --tail=50            # 설정 오류는 여기서 바로 보인다
kubectl exec -n logging ds/fluentd -- fluentd --dry-run -c /fluentd/etc/fluent.conf

# CloudWatch 도착 확인
aws logs describe-log-streams --log-group-name /skills/eks/app \
  --order-by LastEventTime --descending --max-items 1 \
  --query 'logStreams[0].logStreamName' --output text
aws logs get-log-events --log-group-name /skills/eks/app \
  --log-stream-name <위 결과> --limit 5 --query 'events[].message' --output text
```

마지막 명령의 출력이 과제지 스키마와 **키 순서까지** 비슷한지 본다. JSON 이면 키 순서는 무관하지만 키 이름·타입은 정확해야 한다.

## 함정

- **이미지 태그에 목적지 플러그인이 없으면** `Unknown output plugin` 으로 죽는다. 로그를 보면 바로 나온다.
- **`@type parser` 에 `reserve_data true`** 를 안 주면 파싱 후 원래 필드가 사라진다.
- **`enable_ruby true`** 없이 `${record[...]}` 를 쓰면 문자열 그대로 나간다.
- **버퍼 flush 주기**. 기본값이 크면 채점 대기(3분) 안에 로그가 안 도착한다. `flush_interval 5s`.
- **position 파일**을 emptyDir 에 두면 파드 재시작 시 로그를 처음부터 다시 읽어 중복이 생긴다. hostPath 로.
- CloudWatch 로 보낼 때 `auto_create_stream true` 가 없으면 스트림이 없다고 실패한다.
- IAM 권한: `logs:CreateLogStream`, `logs:PutLogEvents`, `logs:CreateLogGroup`, `logs:DescribeLogStreams`.
