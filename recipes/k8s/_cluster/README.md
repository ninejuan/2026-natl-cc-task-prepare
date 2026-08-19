# 클러스터 최단 생성

**컨트롤플레인 10~15분 + 노드그룹 3~5분.** 추가과제에서 가장 오래 걸리는 작업이다. 문제를 읽자마자 던져놓고 대기 중에 즉시 생성되는 것(S3·DynamoDB·Lambda·IAM·SQS·Step Functions)을 처리한다.

```bash
./up.sh                             # 새 VPC
./up.sh -f cluster-existing-vpc.yaml  # 기존 VPC 안에 추가
./up.sh --karpenter --gateway-api
./up.sh --only-addons               # 클러스터는 있고 후속만 (재실행 안전)
./up.sh --down
```

## 파일

| 파일 | 용도 |
|---|---|
| `cluster.yaml` | 새 VPC. 클러스터 + 노드그룹 2개 + 애드온 6개 + IRSA Role 2개 |
| `cluster-existing-vpc.yaml` | 기존 VPC 안에 클러스터 추가 (1과제 추가 항목의 흔한 형태) |
| `up.sh` | 생성 + LBC 설치. `--karpenter`, `--gateway-api` 옵션 |

## 왜 eksctl ClusterConfig 한 장인가

`aws eks create-cluster` → `create-nodegroup` → `create-addon` 을 손으로 순서대로 부르면 대기가 직렬로 쌓인다. eksctl 은 CloudFormation 스택을 병렬로 돌려 노드그룹 2개를 동시에 만들고, **애드온과 IRSA Role 을 클러스터 생성 과정에 끼워 넣는다.**

특히 `iam.serviceAccounts[].wellKnownPolicies` 가 크다. 보통 LBC 를 깔려면

```
IAM 정책 JSON 다운로드 → create-policy → create iamserviceaccount → helm install
```

인데, `wellKnownPolicies: {awsLoadBalancerController: true}` 한 줄이 앞의 세 단계를 없앤다. 정책 JSON 을 받아올 필요도 없다.

## 과제지에 맞춰 바꿀 것

`cluster.yaml` 에서 이것만 고치면 된다.

| 항목 | 위치 |
|---|---|
| 클러스터 이름 | `metadata.name` (+ `tags.karpenter.sh/discovery` 도 같은 값으로) |
| 리전 | `metadata.region` |
| k8s 버전 | `metadata.version` |
| 인스턴스 타입·대수 | `managedNodeGroups[].instanceType` / `desiredCapacity` |
| **노드 라벨** | `managedNodeGroups[].labels` — 채점이 `kubectl get nodes -l` 로 찾는다 |
| 노드 태그 | `managedNodeGroups[].tags.Name` — 채점이 `describe-instances` 로 찾는다 |

## 자주 요구되는 변형

**Private-only 컨트롤플레인** (`"Control Plane 은 외부에서 접근이 가능해서는 안됩니다"`)

```yaml
vpc:
  clusterEndpoints:
    publicAccess: false
    privateAccess: true
```

이렇게 하면 **CloudShell 에서 kubectl 이 안 된다.** 채점이 kubectl 을 쓰므로 VPC 내부에 CloudShell VPC environment 나 bastion 이 필요하다. 과제지가 채점용 쉘 위치를 지정하는 경우가 많으니 확인하라.

**Secrets 봉투 암호화** (`"Etcd 에 저장되는 Secrets 를 CMK 로 암호화"`)

```yaml
secretsEncryption:
  keyARN: arn:aws:kms:ap-northeast-2:000000000000:key/xxxx
```

**Fargate 프로필**

```yaml
fargateProfiles:
  - name: fp-default
    selectors:
      - namespace: keda
      - namespace: karpenter
```

**노드 타임존 KST** — 노드그룹에 `preBootstrapCommands` 를 넣는다.

```yaml
    preBootstrapCommands:
      - timedatectl set-timezone Asia/Seoul
```

**Access Entry** (`aws-auth` 금지 요구 시). eksctl 은 기본적으로 `API_AND_CONFIG_MAP` 으로 만든다. `API` 전용이 필요하면:

```yaml
accessConfig:
  authenticationMode: API
```

## 기존 VPC 쓸 때 — 서브넷 태그가 먼저

`cluster-existing-vpc.yaml` 을 쓰기 전에 태그를 붙여야 한다. 없으면 eksctl 이 거부하거나, 만들어져도 ALB 가 서브넷을 못 골라 Ingress 가 안 붙는다.

```bash
source ../../../addon.env    # bin/discover.sh 결과
export CLUSTER=skills-eks2

aws ec2 create-tags --resources $SUBNET_PRIV_A $SUBNET_PRIV_B \
  --tags Key=kubernetes.io/role/internal-elb,Value=1 \
         Key=karpenter.sh/discovery,Value=$CLUSTER
aws ec2 create-tags --resources $SUBNET_PUB_A $SUBNET_PUB_B \
  --tags Key=kubernetes.io/role/elb,Value=1

envsubst < cluster-existing-vpc.yaml > /tmp/c.yaml
./up.sh -f /tmp/c.yaml
```

`nat.gateway: Disable` 로 둬야 eksctl 이 NAT 를 새로 만들지 않는다. 기존 VPC 의 NAT 를 그대로 쓴다 — 미사용 리소스 감점을 피하는 지점이다.

## 진행 상황 보기

`eksctl create cluster` 가 도는 동안 다른 탭에서:

```bash
aws eks describe-cluster --name $CLUSTER --region $R --query cluster.status --output text
aws cloudformation describe-stacks --region $R \
  --query 'Stacks[?contains(StackName,`eksctl`)].[StackName,StackStatus]' --output table
```

실패하면 CloudFormation 이벤트에 이유가 있다.

```bash
aws cloudformation describe-stack-events --region $R --stack-name eksctl-$CLUSTER-cluster \
  --query 'StackEvents[?ResourceStatus==`CREATE_FAILED`].[LogicalResourceId,ResourceStatusReason]' --output text
```

## 함정

- **`iam.withOIDC: true` 를 빼면** `serviceAccounts` 블록이 동작하지 않고 IRSA 를 쓰는 모든 것(LBC, EBS CSI, KEDA, Loki)이 막힌다.
- **노드 라벨을 안 넣으면** 채점의 `kubectl get nodes -l ...` 이 0개를 반환해 0점이다. 나중에 `kubectl label node` 로 붙일 수는 있지만 노드가 교체되면 사라진다.
- **Karpenter 를 eksctl `karpenter:` 블록으로 묶지 마라.** 버전 비호환으로 실패하면 클러스터 생성 전체가 롤백되어 15분을 잃는다. `up.sh --karpenter` 는 클러스터 생성 후 별도로 깐다.
- **삭제 시 ALB/NLB 가 남아 막힌다.** `up.sh --down` 이 Ingress/Service 를 먼저 지운다. 그래도 남으면 `aws elbv2 describe-load-balancers` 로 확인해 수동 삭제.
- **`amiFamily: AmazonLinux2023`** 을 쓴다. AL2 는 지원 종료 방향이고 containerd 버전 차이로 Fluent Bit 파서가 어긋난다.
- **`disableIMDSv1: true`** 는 파드가 노드 Role 로 폴백하는 것을 줄인다. 최소권한 채점 항목이 있으면 켜라. 단 의도적으로 노드 Role 을 쓰는 구성이면 끄거나 hop limit 을 조정해야 한다.
- eksctl 은 CloudFormation 스택을 남긴다. 클러스터를 콘솔에서 지우면 스택이 고아가 되어 재생성이 충돌한다. 반드시 `eksctl delete` 로 지워라.
