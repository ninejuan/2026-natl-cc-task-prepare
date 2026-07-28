# 스토리지 (EBS / EFS CSI)

## 애드온 먼저

드라이버가 없으면 PVC 가 영구 `Pending` 이다.

```bash
export CLUSTER=skills-eks R=ap-northeast-2
ACCOUNT=$(aws sts get-caller-identity --query Account --output text)

# EBS
eksctl create iamserviceaccount --cluster $CLUSTER --region $R \
  --namespace kube-system --name ebs-csi-controller-sa \
  --attach-policy-arn arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy \
  --approve --role-only --role-name AmazonEKS_EBS_CSI_DriverRole-$CLUSTER
aws eks create-addon --cluster-name $CLUSTER --addon-name aws-ebs-csi-driver --region $R \
  --service-account-role-arn arn:aws:iam::$ACCOUNT:role/AmazonEKS_EBS_CSI_DriverRole-$CLUSTER \
  --resolve-conflicts OVERWRITE
aws eks wait addon-active --cluster-name $CLUSTER --addon-name aws-ebs-csi-driver --region $R

# EFS
eksctl create iamserviceaccount --cluster $CLUSTER --region $R \
  --namespace kube-system --name efs-csi-controller-sa \
  --attach-policy-arn arn:aws:iam::aws:policy/service-role/AmazonEFSCSIDriverPolicy \
  --approve --role-only --role-name AmazonEKS_EFS_CSI_DriverRole-$CLUSTER
aws eks create-addon --cluster-name $CLUSTER --addon-name aws-efs-csi-driver --region $R \
  --service-account-role-arn arn:aws:iam::$ACCOUNT:role/AmazonEKS_EFS_CSI_DriverRole-$CLUSTER \
  --resolve-conflicts OVERWRITE
```

## EFS 파일시스템 준비

EFS 는 AWS 쪽 리소스를 먼저 만들어야 한다. **마운트 타깃의 SG 가 노드 SG 로부터 2049/TCP 를 허용**해야 마운트된다 — 이걸 빠뜨리면 파드가 마운트 타임아웃으로 멈춘다.

```bash
FS=$(aws efs create-file-system --region $R --encrypted \
  --tags Key=Name,Value=skills-efs --query FileSystemId --output text)
SG=$(aws ec2 create-security-group --region $R --group-name skills-efs-sg \
  --description efs --vpc-id $VPC --query GroupId --output text)
aws ec2 authorize-security-group-ingress --region $R --group-id $SG \
  --protocol tcp --port 2049 --source-group $NODE_SG
for s in $PRIV_A $PRIV_B; do
  aws efs create-mount-target --region $R --file-system-id $FS --subnet-id $s --security-groups $SG
done
aws efs describe-mount-targets --region $R --file-system-id $FS \
  --query 'MountTargets[].LifeCycleState' --output text     # available 대기
echo "fileSystemId=$FS  → storageclass-efs.yaml 에 넣는다"
```

## 적용

```bash
kubectl apply -f storageclass-ebs.yaml
kubectl apply -f pvc-ebs.yaml
kubectl apply -f statefulset.yaml

kubectl apply -f storageclass-efs.yaml    # fileSystemId 를 먼저 바꿔라
kubectl apply -f pvc-efs.yaml
```

## 파일

| 파일 | 리소스 |
|---|---|
| `storageclass-ebs.yaml` | StorageClass gp3, 암호화, WaitForFirstConsumer |
| `pvc-ebs.yaml` | PVC (ReadWriteOnce) |
| `statefulset.yaml` | StatefulSet + volumeClaimTemplates |
| `storageclass-efs.yaml` | StorageClass EFS (동적 프로비저닝, access point) |
| `pvc-efs.yaml` | PVC (ReadWriteMany) |

## EBS vs EFS

| | EBS | EFS |
|---|---|---|
| accessMode | ReadWriteOnce (한 노드) | ReadWriteMany (여러 노드 동시) |
| AZ | AZ 에 묶인다 | AZ 무관 |
| 언제 | DB, 단일 쓰기 | 여러 파드가 같은 파일을 공유 |
| 사전 준비 | 없음 | 파일시스템 + 마운트 타깃 + SG |

"여러 파드가 같은 볼륨을" 이라는 문구가 있으면 EBS 로는 불가능하다. EFS 다.

## 확인

```bash
kubectl get sc
kubectl get pvc -n app
kubectl get pv
kubectl get pvc app-data -n app -o jsonpath='{.status.phase} {.spec.volumeName}{"\n"}'   # Bound
kubectl describe pvc app-data -n app | sed -n '/Events:/,$p'

# 실제로 쓰기가 되는지
kubectl exec -n app app-sts-0 -- sh -c 'echo ok > /data/t && cat /data/t'
aws ec2 describe-volumes --region $R --filters Name=tag:kubernetes.io/created-for/pvc/name,Values=app-data \
  --query 'Volumes[].[VolumeId,Size,VolumeType,Encrypted]' --output text
```

## PVC 가 Pending 일 때

```bash
kubectl describe pvc <pvc> -n <ns> | sed -n '/Events:/,$p'
kubectl -n kube-system logs deploy/ebs-csi-controller -c csi-provisioner --tail=30
```

1. **드라이버 애드온이 없다** — 가장 흔하다.
2. **`WaitForFirstConsumer`** 라서 파드가 스케줄될 때까지 정상적으로 Pending 이다. 파드를 만들어라.
3. **IRSA 권한 없음** — 컨트롤러가 볼륨을 만들 수 없다.
4. EFS: **마운트 타깃 SG 에 2049 미허용** — PVC 는 Bound 되는데 파드가 마운트에서 멈춘다.

## 함정

- **`WaitForFirstConsumer` 를 `Immediate` 로 바꾸면** 볼륨이 임의 AZ 에 생겨 파드와 어긋나고 영구 Pending 이 된다. 기본값을 유지하라.
- **EBS PVC 는 확장만 되고 축소는 안 된다.** `allowVolumeExpansion: true` 를 미리 넣어라.
- **StatefulSet 의 `volumeClaimTemplates` 로 만든 PVC 는 StatefulSet 을 지워도 남는다.** 미사용 리소스 감점 대상이다. 정리하라.
- **`reclaimPolicy: Delete`** 면 PVC 삭제 시 EBS 볼륨도 지워진다. `Retain` 이면 볼륨이 남는다 — 잔재 확인 필요.
- KMS CMK 로 암호화하려면 StorageClass 에 `kmsKeyId` 를 주고, **CSI 드라이버 Role 에 해당 키의 `kms:CreateGrant` 권한**이 있어야 한다.
- EFS StorageClass 의 `provisioningMode: efs-ap` 는 access point 를 자동 생성한다. 파일시스템 하나에 여러 PVC 를 격리해 쓸 수 있다.
