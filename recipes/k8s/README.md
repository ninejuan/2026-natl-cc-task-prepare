# 코어 쿠버네티스

컨트롤러 설치 없이 되는 것(코어 k8s API)과 EKS 애드온으로 되는 것. CRD 를 들고 오는 서드파티는 [`../cncf/`](../cncf/) 에 있다.

## 디렉토리

| 디렉토리 | 무엇 |
|---|---|
| [`workload/`](workload/) | Deployment·Service·probe·graceful shutdown·topologySpread·PDB |
| [`ingress-alb/`](ingress-alb/) | Ingress → ALB. 어노테이션 전집, TargetGroupBinding |
| [`gateway-alb/`](gateway-alb/) | Gateway API → ALB. GatewayClass·Gateway·HTTPRoute |
| [`nlb/`](nlb/) | Service type LoadBalancer → NLB |
| [`scaling/`](scaling/) | HPA, Karpenter (큐 기반은 [`../cncf/keda/`](../cncf/keda/)) |
| [`admission/`](admission/) | ValidatingAdmissionPolicy — 설치 없이 파드 차단 |
| [`storage/`](storage/) | EBS/EFS CSI, StorageClass·PVC·StatefulSet |
| [`netpol/`](netpol/) | 표준 NetworkPolicy (L7 은 [`../cncf/cilium/`](../cncf/cilium/)) |
| [`rbac/`](rbac/) | Role·RoleBinding, EKS Access Entry 연동 |
| [`identity/`](identity/) | IRSA / Pod Identity |
| [`logging/`](logging/) | Fluent Bit → CloudWatch Logs |

## 클러스터 준비

추가과제가 새 클러스터를 요구하면 **가장 오래 걸리는 작업이다** (컨트롤플레인 10~15분 + 노드그룹 3~5분). 문제를 읽자마자 던져놓고 대기 중에 다른 항목을 하러 간다.

```bash
export P=<비번호> R=ap-northeast-2 CLUSTER=skills-eks

# 가장 짧은 경로
eksctl create cluster --name $CLUSTER --region $R --version 1.35 \
  --nodegroup-name app --node-type t3.medium --nodes 2 \
  --with-oidc --managed

# 기존 VPC 안에 만들어야 하면 (1과제 추가 항목의 흔한 형태)
eksctl create cluster --name $CLUSTER --region $R --version 1.35 \
  --vpc-private-subnets=$SUBNET_A,$SUBNET_B \
  --nodegroup-name app --node-type t3.medium --nodes 2 --with-oidc --managed
```

서브넷 ID 는 `bin/discover.sh` 가 만든 `addon.env` 에서 가져온다.

## 애드온

```bash
aws eks update-kubeconfig --region $R --name $CLUSTER

for a in vpc-cni coredns kube-proxy aws-ebs-csi-driver eks-pod-identity-agent metrics-server; do
  aws eks create-addon --cluster-name $CLUSTER --addon-name $a --region $R \
    --resolve-conflicts OVERWRITE
done
aws eks wait addon-active --cluster-name $CLUSTER --addon-name aws-ebs-csi-driver --region $R
```

`metrics-server` 가 없으면 HPA 가 동작하지 않는다. `eks-pod-identity-agent` 가 없으면 Pod Identity 가 안 된다.

## AWS Load Balancer Controller

`ingress-alb/`, `gateway-alb/`, `nlb/` 를 쓰려면 이게 먼저다.

```bash
export CLUSTER=skills-eks R=ap-northeast-2
ACCOUNT=$(aws sts get-caller-identity --query Account --output text)

# 1) IAM 정책
curl -sO https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/main/docs/install/iam_policy.json
aws iam create-policy --policy-name AWSLoadBalancerControllerIAMPolicy-$CLUSTER \
  --policy-document file://iam_policy.json || true

# 2) IRSA
eksctl create iamserviceaccount --cluster $CLUSTER --region $R \
  --namespace kube-system --name aws-load-balancer-controller \
  --attach-policy-arn arn:aws:iam::$ACCOUNT:policy/AWSLoadBalancerControllerIAMPolicy-$CLUSTER \
  --approve --override-existing-serviceaccounts

# 3) 설치
helm repo add eks https://aws.github.io/eks-charts && helm repo update
helm upgrade --install aws-load-balancer-controller eks/aws-load-balancer-controller \
  -n kube-system --set clusterName=$CLUSTER \
  --set serviceAccount.create=false \
  --set serviceAccount.name=aws-load-balancer-controller --wait

kubectl -n kube-system rollout status deploy/aws-load-balancer-controller
```

**서브넷 태그가 없으면 컨트롤러가 서브넷을 못 고른다.** ALB 가 안 생기고 Ingress 이벤트에 에러가 남는다.

```bash
aws ec2 create-tags --region $R --resources $PUBLIC_SUBNETS  --tags Key=kubernetes.io/role/elb,Value=1
aws ec2 create-tags --region $R --resources $PRIVATE_SUBNETS --tags Key=kubernetes.io/role/internal-elb,Value=1
```

## Gateway API

**LBC 를 깔아도 Gateway API 의 core CRD 는 안 따라온다.** 별도로 넣어야 `Gateway`/`HTTPRoute` 가 인식된다. 모르고 들어가면 `resource mapping not found` 로 막힌다.

```bash
kubectl apply -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.5.0/standard-install.yaml
kubectl get crd | grep gateway.networking.k8s.io
```

LBC v2.14+ 가 필요하고, v3.0.0 부터 GA 다.

## 진단 원라이너

```bash
kubectl get pods -A --field-selector 'status.phase!=Running'
kubectl get events -A --sort-by=.lastTimestamp | tail -30
kubectl describe pod <pod> -n <ns> | sed -n '/Events:/,$p'     # 왜 Pending 인지
kubectl logs <pod> -n <ns> --previous                          # CrashLoop 직전 로그
kubectl top nodes; kubectl top pods -n <ns>                    # metrics-server 필요
kubectl get nodes -o custom-columns='NAME:.metadata.name,LABELS:.metadata.labels' | tr ',' '\n' | grep skills
kubectl auth can-i --list --as=system:serviceaccount:app:app-sa -n app
kubectl -n kube-system logs deploy/aws-load-balancer-controller --tail=50 | grep -i error
```

파드가 Pending 이면 순서대로: 노드 라벨/`nodeSelector` 불일치 → 리소스 부족 → taint/toleration → PVC 바인딩 대기.
