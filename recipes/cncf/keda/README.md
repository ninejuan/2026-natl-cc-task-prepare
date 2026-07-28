# KEDA

이벤트 기반 파드 스케일링. **CPU/메모리가 아닌 것**으로 스케일해야 하면 KEDA다. 2026 가이드 "EKS Scaling" 모듈에 SQS 큐 길이 케이스가 명시돼 있다.

## 설치

```bash
helm repo add kedacore https://kedacore.github.io/charts && helm repo update
helm upgrade --install keda kedacore/keda -n keda --create-namespace --version 2.17.2 --wait
kubectl get pods -n keda        # keda-operator, keda-operator-metrics-apiserver, keda-admission-webhooks
```

AWS 트리거(SQS 등)를 쓰면 **`keda-operator` ServiceAccount에 IAM 권한이 붙어야 한다.** 설치 시 함께 넣는다.

```bash
helm upgrade --install keda kedacore/keda -n keda --create-namespace \
  --set 'serviceAccount.operator.annotations.eks\.amazonaws\.com/role-arn=arn:aws:iam::000000000000:role/skills-keda-role'
```

또는 Pod Identity:

```bash
aws eks create-pod-identity-association --cluster-name skills-eks \
  --namespace keda --service-account keda-operator \
  --role-arn arn:aws:iam::000000000000:role/skills-keda-role
```

Role에 필요한 권한은 트리거에 따라 다르다. SQS면 `sqs:GetQueueAttributes`, `sqs:GetQueueUrl` 만.

## 파일

| 파일 | 케이스 |
|---|---|
| [`triggerauthentication-aws.yaml`](triggerauthentication-aws.yaml) | AWS 자격증명을 트리거에 연결 (Pod Identity / IRSA) |
| [`scaledobject-sqs.yaml`](scaledobject-sqs.yaml) | SQS 큐 길이로 Deployment 스케일 (0→N) |
| [`scaledobject-cron.yaml`](scaledobject-cron.yaml) | 시간대별로 최소 파드 수 변경 |
| [`scaledobject-prometheus.yaml`](scaledobject-prometheus.yaml) | Prometheus 쿼리 결과로 스케일 (RPS·큐 지연 등) |
| [`scaledobject-cpu-memory.yaml`](scaledobject-cpu-memory.yaml) | KEDA로 CPU/메모리 (HPA 대신 한 곳에서 관리할 때) |
| [`scaledobject-dynamodb-stream.yaml`](scaledobject-dynamodb-stream.yaml) | DynamoDB Stream 샤드 수로 스케일 |
| [`scaledjob-sqs.yaml`](scaledjob-sqs.yaml) | 메시지 1건 = Job 1개. 배치 처리형 |
| [`worker-deployment.yaml`](worker-deployment.yaml) | 스케일 대상 워커 (replicas 를 KEDA가 관리하므로 매니페스트에 replicas 를 두지 않는다) |

## 적용 순서

```bash
kubectl apply -f worker-deployment.yaml
kubectl apply -f triggerauthentication-aws.yaml
kubectl apply -f scaledobject-sqs.yaml
```

`ScaledObject` 를 먼저 넣으면 대상 Deployment가 없어 에러 상태로 남는다. 워커부터.

## 확인

```bash
kubectl get scaledobject -n app
kubectl get hpa -n app                      # KEDA가 내부적으로 HPA를 만든다
kubectl describe scaledobject worker-scaledobject -n app | tail -20
kubectl logs -n keda -l app=keda-operator --tail=50 | grep -i error
```

`READY=True ACTIVE=True` 면 트리거가 값을 읽고 있다. `ACTIVE=False` 인데 큐에 메시지가 있으면 자격증명 문제다.

## 채점 관점

실제 채점 스크립트가 보는 것 (2026 후보 4모듈):

```bash
kubectl get scaledobject sqs-worker-scaledobject -n skills-sqs -o yaml
kubectl get triggerauthentication sqs-worker-trigger-auth -n skills-sqs -o yaml
kubectl get serviceaccount keda-operator -n keda -o jsonpath='{.metadata.annotations.eks\.amazonaws\.com/role-arn}'
```

CRD를 **통째로 덤프해서 필드 존재 여부**를 본다. 이름을 과제지대로 정확히 맞추고, 요구된 필드를 빠뜨리지 않는다.

## 함정

- **`pollingInterval` 기본값이 30초다.** 채점 대기가 항목당 3분이므로 10초 이하로 줄인다. 안 그러면 스케일아웃이 관측 전에 안 끝난다.
- **`cooldownPeriod` 기본 300초.** 스케일인을 보여줘야 하면 30~60초로 줄인다.
- **`minReplicaCount: 0` 은 scale-to-zero.** 채점이 "평상시 0개"를 요구하면 이걸 쓰고, "항상 1개 이상"이면 1로.
- **Deployment에 `replicas` 를 적어두면 충돌한다.** KEDA(HPA)가 관리하므로 매니페스트에서 빼라.
- **`queueLength` 는 파드당 목표 메시지 수**다. 메시지 12개 / `queueLength: 5` → 3파드. 채점 기대값에서 역산해 정한다.
- **`scaleOnInFlight`** 를 켜면 처리 중(NotVisible) 메시지도 센다. 워커가 오래 잡고 있으면 이걸 꺼야 스케일인이 된다.
- Karpenter와 같이 쓸 때: KEDA가 파드를 늘려도 노드가 없으면 Pending이다. NodePool의 `limits` 를 확인한다.
