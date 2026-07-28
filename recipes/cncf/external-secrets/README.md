# External Secrets Operator (ESO)

Secrets Manager / Parameter Store 값을 **k8s Secret 객체로 동기화**한다. 파드가 표준 `env`·`volume` 으로 쓸 수 있다.

Secrets Store CSI Driver 와 비교: CSI는 파드에 파일로만 마운트한다. **Secret 객체 자체가 필요하면**(다른 컨트롤러가 참조, `envFrom`, imagePullSecret) ESO를 쓴다.

## 설치

```bash
helm repo add external-secrets https://charts.external-secrets.io && helm repo update
helm upgrade --install external-secrets external-secrets/external-secrets \
  -n external-secrets --create-namespace --version 0.20.4 \
  --set installCRDs=true \
  --set 'serviceAccount.annotations.eks\.amazonaws\.com/role-arn=arn:aws:iam::000000000000:role/skills-eso-role' \
  --wait
kubectl get pods -n external-secrets
```

IAM Role 최소 권한:

```json
{"Version":"2012-10-17","Statement":[
 {"Effect":"Allow","Action":["secretsmanager:GetSecretValue","secretsmanager:DescribeSecret"],
  "Resource":"arn:aws:secretsmanager:ap-northeast-2:000000000000:secret:skills/*"},
 {"Effect":"Allow","Action":["ssm:GetParameter","ssm:GetParameters"],
  "Resource":"arn:aws:ssm:ap-northeast-2:000000000000:parameter/skills/*"},
 {"Effect":"Allow","Action":"kms:Decrypt","Resource":"arn:aws:kms:ap-northeast-2:000000000000:key/*"}]}
```

CMK로 암호화된 시크릿이면 `kms:Decrypt` 가 반드시 필요하다. 빠뜨리면 `AccessDeniedException` 이 난다.

## 파일

| 파일 | 케이스 |
|---|---|
| [`clustersecretstore-secretsmanager.yaml`](clustersecretstore-secretsmanager.yaml) | Secrets Manager 연결 (클러스터 전역) |
| [`clustersecretstore-parameterstore.yaml`](clustersecretstore-parameterstore.yaml) | SSM Parameter Store 연결 |
| [`secretstore-namespaced.yaml`](secretstore-namespaced.yaml) | 네임스페이스 한정 + 파드 SA 로 assume (테넌트 분리) |
| [`externalsecret-key-property.yaml`](externalsecret-key-property.yaml) | JSON 시크릿에서 **특정 키만** 뽑기 |
| [`externalsecret-datafrom-extract.yaml`](externalsecret-datafrom-extract.yaml) | JSON 시크릿 **전체**를 Secret 키로 펼치기 |
| [`externalsecret-template.yaml`](externalsecret-template.yaml) | 값을 조합해 연결문자열·설정파일 형태로 만들기 |
| [`externalsecret-find-by-name.yaml`](externalsecret-find-by-name.yaml) | 이름 패턴으로 여러 시크릿을 한 번에 |
| [`pushsecret.yaml`](pushsecret.yaml) | 역방향 — k8s Secret 을 Secrets Manager 로 밀어넣기 |
| [`deployment-consumer.yaml`](deployment-consumer.yaml) | 만들어진 Secret 을 `envFrom` 으로 소비 |

## 확인

```bash
kubectl get clustersecretstore
kubectl get externalsecret -n app
kubectl get secret app-secret -n app -o jsonpath='{.data}' | jq 'keys'
kubectl get secret app-secret -n app -o jsonpath='{.data.password}' | base64 -d; echo
```

`ExternalSecret` 의 `STATUS` 가 `SecretSynced` 여야 한다. 실패하면:

```bash
kubectl describe externalsecret app-secret -n app | tail -20
kubectl logs -n external-secrets -l app.kubernetes.io/name=external-secrets --tail=50
```

## 함정

- **`refreshInterval: 0` 은 한 번만 동기화**한다. 회전(rotation)을 보여줘야 하면 `1m` 같이 짧게 둔다.
- **`ClusterSecretStore` 는 클러스터 스코프**다. `metadata.namespace` 를 넣으면 안 된다. 네임스페이스 한정이 필요하면 `SecretStore`.
- **`SecretStore` 를 참조할 때 `secretStoreRef.kind` 를 명시**한다. 생략하면 `SecretStore` 로 간주되어 `ClusterSecretStore` 를 못 찾는다.
- **키 이름에 `/` 가 있으면** `remoteRef.key` 에 전체 경로를 쓴다 (`skills/db/credentials`).
- Parameter Store의 `SecureString` 은 `service: ParameterStore` + `kms:Decrypt` 필요.
- ESO가 만든 Secret을 손으로 수정하면 다음 동기화에 덮어써진다.
