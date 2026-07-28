# 파드에 AWS 권한 주기 (IRSA / Pod Identity)

파드가 DynamoDB·S3·SQS 를 호출해야 할 때. 액세스 키를 컨테이너에 넣지 않는 방법.

## 둘 중 무엇을 쓰나

| | IRSA | Pod Identity |
|---|---|---|
| 사전 준비 | OIDC provider 등록 | `eks-pod-identity-agent` 애드온 |
| 연결 방식 | SA 의 annotation | AWS API 로 association 생성 |
| Trust policy | OIDC 조건 (클러스터마다 다름) | `pods.eks.amazonaws.com` (고정) |
| 재사용 | 클러스터별로 Role 이 갈린다 | 여러 클러스터가 한 Role 공유 |
| 언제 | 대부분. helm chart 들이 이걸 전제한다 | 과제지가 Pod Identity 를 명시할 때 |

2026 후보 과제지는 **Pod Identity 를 요구하고 trust policy 를 해당 클러스터로 한정**하라고 했다. 과제지가 지정하면 그쪽을 쓴다.

## IRSA

```bash
export CLUSTER=skills-eks R=ap-northeast-2
ACCOUNT=$(aws sts get-caller-identity --query Account --output text)

# 1) OIDC provider (한 번만)
eksctl utils associate-iam-oidc-provider --cluster $CLUSTER --region $R --approve
aws eks describe-cluster --name $CLUSTER --region $R \
  --query 'cluster.identity.oidc.issuer' --output text

# 2) Role + SA 를 한 번에
eksctl create iamserviceaccount --cluster $CLUSTER --region $R \
  --namespace app --name app-sa \
  --attach-policy-arn arn:aws:iam::$ACCOUNT:policy/skills-app-policy \
  --approve --override-existing-serviceaccounts
```

직접 만들려면 trust policy 가 이 형태다.

```bash
OIDC=$(aws eks describe-cluster --name $CLUSTER --region $R --query 'cluster.identity.oidc.issuer' --output text | sed 's|https://||')
cat > /tmp/irsa-trust.json <<JSON
{"Version":"2012-10-17","Statement":[{
  "Effect":"Allow",
  "Principal":{"Federated":"arn:aws:iam::$ACCOUNT:oidc-provider/$OIDC"},
  "Action":"sts:AssumeRoleWithWebIdentity",
  "Condition":{"StringEquals":{
    "$OIDC:aud":"sts.amazonaws.com",
    "$OIDC:sub":"system:serviceaccount:app:app-sa"
  }}
}]}
JSON
aws iam create-role --role-name skills-app-irsa-role --assume-role-policy-document file:///tmp/irsa-trust.json
```

`sub` 조건이 네임스페이스·SA 이름을 고정한다. 이게 없으면 클러스터의 아무 SA 가 이 Role 을 쓸 수 있다.

## Pod Identity

```bash
aws eks create-addon --cluster-name $CLUSTER --addon-name eks-pod-identity-agent \
  --region $R --resolve-conflicts OVERWRITE
aws eks wait addon-active --cluster-name $CLUSTER --addon-name eks-pod-identity-agent --region $R

# trust policy — 클러스터 한정 조건까지
cat > /tmp/pi-trust.json <<JSON
{"Version":"2012-10-17","Statement":[{
  "Effect":"Allow",
  "Principal":{"Service":"pods.eks.amazonaws.com"},
  "Action":["sts:AssumeRole","sts:TagSession"],
  "Condition":{"ArnEquals":{"aws:SourceArn":"arn:aws:eks:$R:$ACCOUNT:cluster/$CLUSTER"}}
}]}
JSON
aws iam create-role --role-name skills-app-pi-role --assume-role-policy-document file:///tmp/pi-trust.json
aws iam attach-role-policy --role-name skills-app-pi-role --policy-arn arn:aws:iam::$ACCOUNT:policy/skills-app-policy

# SA 에 annotation 이 필요 없다. association 으로 연결한다.
aws eks create-pod-identity-association --cluster-name $CLUSTER --region $R \
  --namespace app --service-account app-sa \
  --role-arn arn:aws:iam::$ACCOUNT:role/skills-app-pi-role
```

`sts:TagSession` 이 빠지면 association 이 동작하지 않는다. `aws:SourceArn` 조건이 "이 클러스터에서만" 을 만든다.

## 파일

| 파일 | 케이스 |
|---|---|
| `serviceaccount-irsa.yaml` | IRSA annotation 이 붙은 SA |

Pod Identity 는 매니페스트가 필요 없다 — 평범한 SA 에 association 만 만든다.

## 확인

```bash
# 채점이 보는 지점
kubectl get sa app-sa -n app -o jsonpath='{.metadata.annotations.eks\.amazonaws\.com/role-arn}'; echo
aws eks list-pod-identity-associations --cluster-name $CLUSTER --region $R \
  --namespace app --query 'associations[].[serviceAccount,roleArn]' --output text

# ★ 파드 안에서 실제로 되는지 — 이게 최종 검증이다
POD=$(kubectl get pod -n app -l app=app -o jsonpath='{.items[0].metadata.name}')
kubectl exec -n app $POD -- env | grep -E 'AWS_ROLE_ARN|AWS_WEB_IDENTITY|AWS_CONTAINER_CREDENTIALS'
kubectl exec -n app $POD -- aws sts get-caller-identity
```

`get-caller-identity` 의 ARN 이 `assumed-role/skills-app-...` 이면 성공이다. 노드 Role 이 나오면 IRSA/Pod Identity 가 안 걸렸고 파드가 노드 권한으로 동작하는 것이다 — 최소권한 위반이다.

## 함정

- **SA 를 만든 뒤 파드를 재시작해야 한다.** 기존 파드에는 자격증명이 주입되지 않는다.
- **`sub` 조건의 네임스페이스·SA 이름 오타** — 가장 흔한 실패. `AccessDenied` 만 나오고 이유를 안 알려준다.
- **파드가 노드 Role 로 동작해버리는 경우.** SDK 는 자격증명을 찾지 못하면 IMDS(노드 Role)로 폴백한다. 조용히 동작하지만 채점에서 "최소권한" 항목이 깨진다. 위 `get-caller-identity` 로 확인하라.
- **IMDS hop limit.** 노드에서 IMDS hop limit 이 1 이면 파드가 노드 Role 을 쓸 수 없다. 이건 보안상 바람직하지만, 의도적으로 노드 Role 을 쓰는 구성이면 2 로 올려야 한다.
- **Pod Identity 와 IRSA 를 같은 SA 에 동시에 걸면** Pod Identity 가 우선한다.
- **helm chart 들은 대부분 IRSA 를 전제**한다 (`serviceAccount.annotations`). Pod Identity 로 하려면 chart 설치 후 association 을 따로 만든다.
- Role 이름·External ID 에 비번호가 들어가는 경우가 있다. `$P` 로 조립하라.
