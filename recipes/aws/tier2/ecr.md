# ECR

**트리거 문구** — "이미지를 저장", "ECR 활용", "취약점 스캔", "latest 제외 태그 중복 불허"(→ 태그 불변), "라이프사이클", "CMK 암호화".

**전제**
```bash
export R=ap-northeast-2 ACCT=$(aws sts get-caller-identity --query Account --output text)
```

---

## 케이스 A — 스캔 + 태그 불변 + 암호화 [검증됨]

2026 task1 ECR 요구("취약점 없어야, latest 제외 태그 중복 불허, CMK 암호화") 대응.

```bash
aws ecr create-repository --region $R --repository-name lab-ecr \
  --image-scanning-configuration scanOnPush=true \
  --image-tag-mutability IMMUTABLE \
  --encryption-configuration encryptionType=KMS,kmsKey=<key-arn>   # CMK. 생략 시 AES256
```
- **IMMUTABLE**: 같은 태그 재푸시 불가 → "태그 중복 불허". 단 과제가 "latest 는 예외" 면 `IMMUTABLE_WITH_EXCLUSION` + `--image-tag-mutability-exclusion-filter` 로 latest 제외.
- **scanOnPush**: 푸시 시 자동 취약점 스캔(basic). enhanced 는 Inspector 연동.

## 케이스 B — 라이프사이클 [검증됨]

```bash
aws ecr put-lifecycle-policy --region $R --repository-name lab-ecr --lifecycle-policy-text '{
  "rules":[
    {"rulePriority":1,"description":"untagged 1d","selection":{"tagStatus":"untagged","countType":"sinceImagePushed","countUnit":"days","countNumber":1},"action":{"type":"expire"}},
    {"rulePriority":2,"description":"keep last 10","selection":{"tagStatus":"any","countType":"imageCountMoreThan","countNumber":10},"action":{"type":"expire"}}
  ]}'
```
미태그 1일 후 삭제, 최근 10개만 유지. `tagPrefixList` 로 특정 태그군 대상 가능.

## 케이스 C — 이미지 빌드·푸시

```bash
aws ecr get-login-password --region $R | docker login --username AWS --password-stdin $ACCT.dkr.ecr.$R.amazonaws.com
docker build -t lab-ecr .
docker tag lab-ecr:latest $ACCT.dkr.ecr.$R.amazonaws.com/lab-ecr:v1.0.0
docker push $ACCT.dkr.ecr.$R.amazonaws.com/lab-ecr:v1.0.0
```
> ⚠️ **CloudShell 은 홈 1GB** 라 큰 이미지 빌드가 실패. 지급 PC(Docker Desktop) 또는 CodeBuild(`../tier3/code-series/`)로. 현장은 지급 PC 에서 빌드.

## 케이스 D — 스캔 결과 / pull-through cache

```bash
# 스캔 결과 (채점: 취약점 0 확인)
aws ecr describe-image-scan-findings --region $R --repository-name lab-ecr --image-id imageTag=v1.0.0 \
  --query 'imageScanFindings.findingSeverityCounts' --output json

# pull-through cache (public 이미지를 ECR 로 캐싱, VPC 내부에서 당길 때)
aws ecr create-pull-through-cache-rule --region $R \
  --ecr-repository-prefix ecr-public --upstream-registry-url public.ecr.aws
```

## 검증

```bash
aws ecr describe-repositories --region $R --repository-names lab-ecr \
  --query 'repositories[0].{Mutability:imageTagMutability,Scan:imageScanningConfiguration.scanOnPush,Enc:encryptionConfiguration.encryptionType}' --output json
aws ecr describe-images --region $R --repository-name lab-ecr --query 'sort(imageDetails[].imageTags[])' --output json
aws ecr get-lifecycle-policy --region $R --repository-name lab-ecr --query lifecyclePolicyText --output text
```
채점 방식(2026 task1 mark.sh): `describe-repositories` 로 scanOnPush·mutability·encryptionType, `describe-images` 로 태그 목록, `describe-image-scan-findings` 로 취약점 수.

## 함정

- **IMMUTABLE 이면 같은 태그 재푸시 실패** — CI 에서 `latest` 를 계속 밀면 막힌다. latest 예외가 필요하면 `IMMUTABLE_WITH_EXCLUSION`.
- **CMK 암호화는 생성 시에만** — 나중에 변경 불가. 재생성 필요.
- **CloudShell 이미지 빌드 실패**(1GB). 지급 PC 나 CodeBuild.
- **EKS/ECS 에서 pull 하려면** 노드 role 에 `ecr:GetAuthorizationToken`·`BatchGetImage`·`GetDownloadUrlForLayer`. private 서브넷이면 ECR VPC endpoint(ecr.api+ecr.dkr+**S3 gateway**).
- 스캔은 basic(무료)·enhanced(Inspector, 유료). 과제 "취약점 없어야" 는 basic 으로 충분.

## 정리
```bash
aws ecr delete-repository --region $R --repository-name lab-ecr --force
```
