# 스케일링

파드를 늘리는 것(HPA)과 노드를 늘리는 것(Karpenter)은 다른 문제다. 보통 둘이 함께 필요하다.

**트리거가 CPU/메모리가 아니면**(SQS 큐 길이, Prometheus 쿼리, cron) → [`../../cncf/keda/`](../../cncf/keda/).

## 파일

| 파일 | 리소스 |
|---|---|
| `hpa.yaml` | HorizontalPodAutoscaler v2. CPU 기준 + behavior 튜닝 |
| `karpenter-ec2nodeclass.yaml` | EC2NodeClass — AMI·서브넷·SG·볼륨 |
| `karpenter-nodepool.yaml` | NodePool — 인스턴스 타입·라벨·통합 정책 |

## HPA 전제

`metrics-server` 가 있어야 한다. 없으면 HPA 가 `<unknown>` 으로 남는다.

```bash
aws eks create-addon --cluster-name $CLUSTER --addon-name metrics-server --region $R --resolve-conflicts OVERWRITE
kubectl top nodes            # 값이 나오면 준비됨
kubectl apply -f hpa.yaml
kubectl get hpa -n app -w
```

컨테이너에 `resources.requests.cpu` 가 없으면 사용률 계산이 불가능해 HPA 가 동작하지 않는다.

## Karpenter 설치

```bash
export CLUSTER=skills-eks R=ap-northeast-2
ACCOUNT=$(aws sts get-caller-identity --query Account --output text)

# 서브넷·SG 에 발견용 태그를 먼저 붙인다. 없으면 EC2NodeClass 가 아무것도 못 찾는다.
aws ec2 create-tags --region $R --resources $PRIVATE_SUBNETS \
  --tags Key=karpenter.sh/discovery,Value=$CLUSTER
aws ec2 create-tags --region $R --resources $NODE_SG \
  --tags Key=karpenter.sh/discovery,Value=$CLUSTER

helm registry logout public.ecr.aws 2>/dev/null || true
helm upgrade --install karpenter oci://public.ecr.aws/karpenter/karpenter \
  --version 1.8.1 -n kube-system \
  --set "settings.clusterName=$CLUSTER" \
  --set "serviceAccount.annotations.eks\.amazonaws\.com/role-arn=arn:aws:iam::$ACCOUNT:role/KarpenterControllerRole-$CLUSTER" \
  --wait

kubectl apply -f karpenter-ec2nodeclass.yaml
kubectl apply -f karpenter-nodepool.yaml
```

노드 IAM Role(`KarpenterNodeRole-$CLUSTER`)이 EKS Access Entry 에 등록돼야 노드가 클러스터에 합류한다.

```bash
aws eks create-access-entry --cluster-name $CLUSTER --region $R \
  --principal-arn arn:aws:iam::$ACCOUNT:role/KarpenterNodeRole-$CLUSTER \
  --type EC2_LINUX
```

## 확인

```bash
kubectl get hpa -n app
kubectl get nodepool,ec2nodeclass
kubectl get nodeclaims                                    # Karpenter 가 요청한 노드
kubectl get nodes -l skills/nodepool=worker -o wide       # 라벨로 찾는다. 채점도 이렇게 한다
kubectl -n kube-system logs deploy/karpenter --tail=50 | grep -iE 'error|launched|nodeclaim'
```

스케일아웃을 실제로 유발해 보기:

```bash
kubectl scale deploy app-deploy -n app --replicas=20
kubectl get pods -n app -o wide | grep -c Pending
kubectl get nodeclaims -w                                 # 새 노드가 뜨는지
```

## 함정

- **`karpenter.sh/discovery` 태그가 없으면** EC2NodeClass 가 서브넷/SG 를 못 찾아 노드가 안 뜬다. 가장 흔한 실패.
- **NodePool `template.metadata.labels` 를 반드시 채워라.** 채점이 `kubectl get nodes -l ...` 로 노드를 찾는다. 라벨이 없으면 0개로 나와 0점이다.
- **`limits.cpu` 가 너무 작으면** Karpenter 가 노드를 더 안 만든다. 스케일아웃이 멈추면 여기를 본다.
- **`consolidationPolicy: WhenEmptyOrUnderutilized`** 는 노드를 적극적으로 줄인다. 채점 중 노드가 사라져 항목이 실패할 수 있다. 채점 직전에는 `WhenEmpty` 로 두거나 `consolidateAfter` 를 길게 잡아라.
- **HPA 와 KEDA 를 같은 Deployment 에 동시에 걸면 충돌**한다. KEDA 가 자체 HPA 를 만들기 때문이다. 하나만 쓴다.
- **`behavior.scaleUp.stabilizationWindowSeconds: 0`** 을 넣어야 3분 채점 대기 안에 스케일아웃이 관측된다. 기본값은 즉시지만 scaleDown 기본은 300초다.
- Karpenter 는 **managed node group 과 공존 가능**하다. 기존 노드그룹을 지우지 않아도 된다.
