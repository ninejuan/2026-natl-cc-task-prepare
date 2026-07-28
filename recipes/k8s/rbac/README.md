# RBAC

클러스터 내부 권한. **IAM 권한과는 별개다** — IAM 은 "클러스터 API 에 접근할 수 있는가", RBAC 는 "접근한 뒤 무엇을 할 수 있는가".

## 적용

```bash
kubectl apply -f role.yaml
kubectl apply -f rolebinding.yaml
```

## 파일

| 파일 | 리소스 |
|---|---|
| `role.yaml` | Role (네임스페이스 스코프) |
| `rolebinding.yaml` | RoleBinding — ServiceAccount + Group 을 묶는다 |

클러스터 전역이 필요하면 `ClusterRole` + `ClusterRoleBinding` 으로 바꾼다. 노드·PV·네임스페이스 같은 클러스터 스코프 리소스는 Role 로 줄 수 없다.

## IAM 사용자를 RBAC 에 연결 — Access Entry

2026 후보 과제지가 **`aws-auth` ConfigMap 방식을 금지하고 Access Entry 를 요구**했다. 신규 클러스터는 Access Entry 를 쓴다.

```bash
export CLUSTER=skills-eks R=ap-northeast-2
ACCOUNT=$(aws sts get-caller-identity --query Account --output text)

# 인증 모드 확인. API 또는 API_AND_CONFIG_MAP 이어야 Access Entry 가 동작한다
aws eks describe-cluster --name $CLUSTER --region $R \
  --query 'cluster.accessConfig.authenticationMode' --output text

# 필요하면 전환 (CONFIG_MAP → API_AND_CONFIG_MAP → API 순서로만 가능, 되돌릴 수 없다)
aws eks update-cluster-config --name $CLUSTER --region $R \
  --access-config authenticationMode=API_AND_CONFIG_MAP

# ① IAM Principal 을 RBAC 그룹에 매핑 → 우리가 만든 Role/RoleBinding 이 적용된다
aws eks create-access-entry --cluster-name $CLUSTER --region $R \
  --principal-arn arn:aws:iam::$ACCOUNT:role/skills-viewer-role \
  --kubernetes-groups skills-readers

# ② AWS 관리형 정책으로 한 번에 (그룹·Role 없이)
aws eks create-access-entry --cluster-name $CLUSTER --region $R \
  --principal-arn arn:aws:iam::$ACCOUNT:role/skills-admin-role
aws eks associate-access-policy --cluster-name $CLUSTER --region $R \
  --principal-arn arn:aws:iam::$ACCOUNT:role/skills-admin-role \
  --policy-arn arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy \
  --access-scope type=cluster
```

`rolebinding.yaml` 의 `Group: skills-readers` 가 ①의 `--kubernetes-groups` 와 연결되는 지점이다.

관리형 액세스 정책: `AmazonEKSClusterAdminPolicy`, `AmazonEKSAdminPolicy`, `AmazonEKSEditPolicy`, `AmazonEKSViewPolicy`.

## 확인

```bash
kubectl get role,rolebinding -n app
kubectl get clusterrole,clusterrolebinding | grep skills

# ★ 가장 유용한 명령 — 실제 권한을 시뮬레이션한다
kubectl auth can-i --list --as=system:serviceaccount:app:app-sa -n app
kubectl auth can-i get pods --as=system:serviceaccount:app:app-sa -n app
kubectl auth can-i delete pods --as=system:serviceaccount:app:app-sa -n app     # no 여야 한다
kubectl auth can-i list secrets --as=system:serviceaccount:app:app-sa -n app

# IAM Principal 로
kubectl auth can-i --list --as=arn:aws:iam::$ACCOUNT:role/skills-viewer-role

# Access Entry
aws eks list-access-entries --cluster-name $CLUSTER --region $R --output text
aws eks list-associated-access-policies --cluster-name $CLUSTER --region $R \
  --principal-arn arn:aws:iam::$ACCOUNT:role/skills-admin-role
```

`kubectl auth can-i` 로 **허용돼야 하는 것과 거부돼야 하는 것을 둘 다** 확인하라. 최소권한 요구가 있으면 후자가 채점 대상이다.

## 최소권한 작성 순서

1. 앱이 실제로 호출하는 API 를 파악한다 (로그의 Forbidden 메시지가 알려준다).
2. 필요한 `resources` 와 `verbs` 만 나열한다.
3. `kubectl auth can-i` 로 되는 것/안 되는 것을 확인한다.

```bash
# 권한 부족으로 실패한 요청을 찾는다
kubectl logs -n app deploy/app-deploy | grep -i 'forbidden\|cannot'
```

## 함정

- **`ClusterRole` 을 `RoleBinding` 으로 묶으면** 그 네임스페이스에서만 유효하다. 이 조합은 합법이고 유용하다 — 헷갈리지 마라.
- **`ClusterRole` + `ClusterRoleBinding` 은 전 네임스페이스**다. 최소권한 요구가 있으면 감점 요인.
- **`pods/log` 는 별도 리소스**다. `pods` 만 주면 `kubectl logs` 가 안 된다. `pods/exec`, `pods/portforward` 도 마찬가지.
- **와일드카드 금지 조항**이 흔하다. `verbs: ["*"]` / `resources: ["*"]` 를 쓰지 마라.
- **`authenticationMode` 는 되돌릴 수 없다.** `CONFIG_MAP` → `API_AND_CONFIG_MAP` → `API` 한 방향이다.
- **`API` 모드로 바꾸면 `aws-auth` ConfigMap 이 무시**된다. 기존 매핑으로 접속하던 주체가 잠길 수 있다. Access Entry 를 먼저 만들고 전환하라.
- 클러스터를 만든 IAM Principal 은 자동으로 admin 이다. 다른 사람이 만든 클러스터에 접근하려면 Access Entry 가 필요하다.
