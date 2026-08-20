# Secrets Manager

**트리거 문구** — "시크릿 관리", "비밀번호 회전", "RDS 자격증명", "DB 접속 정보".

**전제**
```bash
export R=ap-northeast-2
```
회전이 필요없는 단순 설정은 **Parameter Store SecureString**(`config-ssm.md`)이 더 싸다. Secrets Manager 는 **자동 회전·RDS 통합**이 필요할 때.

---

## 케이스 A — 시크릿 + 조회 + resource policy [검증됨]

```bash
SEC=$(aws secretsmanager create-secret --region $R --name lab/db \
  --secret-string '{"username":"admin","password":"S3cr3t!"}' --query ARN --output text)
# CMK 암호화: --kms-key-id <key>

aws secretsmanager get-secret-value --region $R --secret-id lab/db --query SecretString --output text
# {"username":"admin","password":"S3cr3t!"}

# resource policy (교차 계정/특정 principal 만)
aws secretsmanager put-resource-policy --region $R --secret-id lab/db --resource-policy '{
  "Version":"2012-10-17","Statement":[{"Effect":"Allow",
    "Principal":{"AWS":"arn:aws:iam::OTHER:root"},
    "Action":"secretsmanager:GetSecretValue","Resource":"*"}]}'
```

## 케이스 B — 자동 회전 (Lambda)

```bash
# RDS 관리형 회전: RDS 와 연결하면 AWS 제공 회전 Lambda 자동 구성
aws secretsmanager rotate-secret --region $R --secret-id lab/db \
  --rotation-lambda-arn <rotation-fn-arn> \
  --rotation-rules "AutomaticallyAfterDays=30"
# RDS credential 은 create-secret 시 관리형 회전 옵션 사용 권장
```
회전 Lambda 4단계(createSecret/setSecret/testSecret/finishSecret). RDS/Aurora 는 AWS 제공 템플릿.

## 케이스 C — RDS/애플리케이션 참조

```bash
# ECS: task definition secrets
#   "secrets":[{"name":"DB_PASSWORD","valueFrom":"arn:...:secret:lab/db:password::"}]
# Lambda/EC2: 런타임에 get-secret-value (SDK). role 에 secretsmanager:GetSecretValue + kms:Decrypt
# 캐싱: 매 호출마다 API 대신 lambda extension / 캐시 라이브러리
```

## 검증

```bash
aws secretsmanager describe-secret --region $R --secret-id lab/db --query '[Name,RotationEnabled]' --output text
aws secretsmanager get-secret-value --region $R --secret-id lab/db --query SecretString --output text
aws secretsmanager get-resource-policy --region $R --secret-id lab/db --query ResourcePolicy --output text
```

## Terraform

```hcl
resource "aws_secretsmanager_secret" "s" { name = "lab/db" }
resource "aws_secretsmanager_secret_version" "v" {
  secret_id     = aws_secretsmanager_secret.s.id
  secret_string = jsonencode({ username = "admin", password = "S3cr3t!" })
}
# 회전: aws_secretsmanager_secret_rotation { rotation_lambda_arn, rotation_rules { automatically_after_days = 30 } }
```
> 랜덤 비밀번호는 `random_password` + `secret_version` 조합. state 에 평문이 남으니 주의(대회용은 무방).

## Console 팁

- **시크릿 생성 마법사**: 타입(RDS 자격증명/기타)·KMS 키·회전을 폼으로. RDS 선택 시 **관리형 회전 Lambda 를 자동 구성**(직접 안 짬).
- **Retrieve secret value**: 콘솔에서 값을 바로 확인(권한 있으면).
- **회전 설정**: Rotation 탭에서 주기·Lambda 를 클릭으로.

## 참고 문서

- Secrets Manager 사용 설명서: https://docs.aws.amazon.com/secretsmanager/latest/userguide/
- 자동 회전: https://docs.aws.amazon.com/secretsmanager/latest/userguide/rotating-secrets.html
- Terraform `aws_secretsmanager_secret`: https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/secretsmanager_secret

## 함정

- **읽는 주체에 GetSecretValue + kms:Decrypt**(CMK 면).
- **삭제는 복구 기간** — `delete-secret` 은 기본 7~30일 후 삭제. 즉시는 `--force-delete-without-recovery`.
- **ECS secrets valueFrom** 형식: `<arn>:<json-key>::` (버전 스테이지/ID 생략 시 `::`).
- **회전 Lambda 는 VPC/네트워크** — RDS 접근 가능해야. 관리형 회전이 편하다.
- 이름에 `/` 는 계층(경로) — 조회 시 전체 이름.

## 정리
```bash
aws secretsmanager delete-secret --region $R --secret-id lab/db --force-delete-without-recovery
```
