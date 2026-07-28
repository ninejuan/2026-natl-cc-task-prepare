# Crossplane

k8s 매니페스트로 AWS 리소스를 만든다. `kubectl apply` 로 S3 버킷·DynamoDB 테이블·RDS 를 띄우는 것.

**대회에서 이걸 쓸 이유는 하나다: 과제지가 명시적으로 Crossplane 을 요구할 때.** 그 외에는 terraform 이나 CLI 가 훨씬 빠르다. Provider 설치와 CRD 등록에만 수 분이 걸린다.

## 설치

3단계다. 각 단계가 끝나야 다음이 된다.

```bash
# 1. Crossplane 코어
helm repo add crossplane-stable https://charts.crossplane.io/stable && helm repo update
helm upgrade --install crossplane crossplane-stable/crossplane \
  -n crossplane-system --create-namespace --wait

# 2. AWS Provider (필요한 서비스별로 하나씩)
kubectl apply -f provider-aws-s3.yaml
kubectl apply -f provider-aws-dynamodb.yaml
kubectl wait provider.pkg.crossplane.io --all --for=condition=Healthy --timeout=5m

# 3. 자격증명 연결
kubectl apply -f providerconfig-irsa.yaml
```

**Provider 가 Healthy 가 되기까지 2~5분** 걸린다. 그 사이 CRD 가 등록되므로 관리 리소스를 미리 apply 하면 실패한다. `kubectl wait` 로 기다려라.

## 파일

| 파일 | 케이스 |
|---|---|
| [`provider-aws-s3.yaml`](provider-aws-s3.yaml) | S3 Provider |
| [`provider-aws-dynamodb.yaml`](provider-aws-dynamodb.yaml) | DynamoDB Provider |
| [`providerconfig-irsa.yaml`](providerconfig-irsa.yaml) | IRSA 로 인증 (Secret 없이) |
| [`providerconfig-secret.yaml`](providerconfig-secret.yaml) | 액세스 키 Secret 으로 인증 |
| [`bucket.yaml`](bucket.yaml) | S3 버킷 관리 리소스 |
| [`dynamodb-table.yaml`](dynamodb-table.yaml) | DynamoDB 테이블 |
| [`xrd.yaml`](xrd.yaml) | 커스텀 API 정의 (CompositeResourceDefinition) |
| [`composition.yaml`](composition.yaml) | XRD 를 실제 AWS 리소스로 조립 |
| [`claim.yaml`](claim.yaml) | 개발자가 쓰는 최종 인터페이스 |

## 두 가지 사용 수준

**① 관리 리소스 직접 사용** — `Bucket`, `Table` 같은 CRD 를 그대로 apply 한다. 간단하다.

**② XRD + Composition + Claim** — "버킷 + 테이블 + IAM Role 을 한 세트로" 같은 추상화를 만든다. 과제지가 "개발자가 한 줄로 요청하면 인프라 세트가 생성되도록" 류를 요구하면 이쪽이다. 파일 3개가 한 묶음이다.

```
Claim (개발자가 쓴다)  →  XRD (API 스키마)  →  Composition (실제 리소스 조립)
```

## 확인

```bash
kubectl get providers
kubectl get providerconfig
kubectl get buckets,tables                      # 관리 리소스
kubectl get managed                             # 전부 한 번에

# READY / SYNCED 가 True 여야 실제로 AWS 에 만들어졌다
kubectl get bucket skills-crossplane-bucket -o jsonpath='{.status.conditions}' | jq
kubectl describe bucket skills-crossplane-bucket | tail -20

# AWS 쪽에서 실제 확인
aws s3api head-bucket --bucket skills-crossplane-000
```

`SYNCED=True, READY=True` 가 정상. `SYNCED=False` 면 자격증명 문제, `READY=False` 면 AWS API 가 거부한 것이다. `describe` 의 Events 에 이유가 나온다.

## 함정

- **API 그룹이 버전마다 바뀐다.** `s3.aws.upbound.io/v1beta1` 과 `s3.aws.m.upbound.io/v1beta1`(네임스페이스 스코프) 이 공존한다. 설치한 Provider 가 무엇을 등록했는지 확인하라: `kubectl api-resources | grep -i bucket`
- **Provider 를 서비스별로 따로 깐다.** `provider-aws-s3`, `provider-aws-dynamodb` 처럼. 전체 `provider-aws` 는 거대해서 설치가 오래 걸린다.
- **Provider 가 Healthy 전에 리소스를 apply 하면** `no matches for kind` 가 난다. `kubectl wait` 필수.
- **IRSA 를 쓰려면 Provider 파드의 ServiceAccount 에 annotation 이 붙어야 한다.** Provider 는 자체 SA 를 만들므로 `ControllerConfig`(구버전) 또는 `DeploymentRuntimeConfig`(신버전) 로 주입한다.
- **삭제 시 실제 AWS 리소스가 지워진다.** `kubectl delete bucket` 이 S3 버킷을 삭제한다. `deletionPolicy: Orphan` 을 주면 k8s 객체만 지운다.
- 버킷 이름은 전역 유니크다. `metadata.name` 이 아니라 `forProvider` 나 annotation 으로 실제 이름을 지정해야 한다.
