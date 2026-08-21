# IAM 정책 문서 모음 — ✅ live 검증

> **실검증**: trust policy 4종(EC2 / External ID / MFA 조건 / ECS task)을 실제 `create-role` 로 통과시켰고,
> permission policy 는 **Access Analyzer `validate-policy`** 로 린트했다(S3 최소권한·permission boundary 는 findings 0,
> 조건부 정책은 `SECURITY_WARNING: PASS_ROLE_WITH_STAR_IN_RESOURCE` — 의도된 경고).
> permission boundary 는 `put-role-permissions-boundary` 로 붙여 `PermissionsBoundaryType: Policy` 까지 확인.


본 문서는 과제에서 반복 사용하는 IAM **trust policy**(누가 role 을 assume 하나)와
**permission policy**(무엇을 할 수 있나) 예시 모음이다. 각 예시는 `Statement` 원소.
실제로는 `{"Version":"2012-10-17","Statement":[ … ]}` 로 감싼다.

```bash
export ACCT=$(aws sts get-caller-identity --query Account --output text) R=ap-northeast-2
# trust policy → create-role, permission policy → put-role-policy
aws iam create-role --role-name lab-role --assume-role-policy-document file://trust.json
aws iam put-role-policy --role-name lab-role --policy-name p --policy-document file://perm.json
```

> ⚠️ zsh 에서 `${ACCT}` 중괄호 필수 — `$ACCT:root` 는 `:root` modifier 로 잘린다.

## Trust policy (AssumeRole 대상)

- EC2 인스턴스 (인스턴스 프로파일)
```json
{"Effect":"Allow","Principal":{"Service":"ec2.amazonaws.com"},"Action":"sts:AssumeRole"}
```

- Lambda 실행 역할
```json
{"Effect":"Allow","Principal":{"Service":"lambda.amazonaws.com"},"Action":"sts:AssumeRole"}
```

- ECS 태스크 역할
```json
{"Effect":"Allow","Principal":{"Service":"ecs-tasks.amazonaws.com"},"Action":"sts:AssumeRole"}
```

- 여러 서비스 동시 (배열)
```json
{"Effect":"Allow","Principal":{"Service":["ecs-tasks.amazonaws.com","lambda.amazonaws.com"]},"Action":"sts:AssumeRole"}
```

- 같은 계정 principal + External ID 강제 (감사 role)
```json
{"Effect":"Allow","Principal":{"AWS":"arn:aws:iam::ACCT:root"},"Action":"sts:AssumeRole",
 "Condition":{"StringEquals":{"sts:ExternalId":"skills-2026"}}}
```

- 특정 role/user 만 (교차 계정)
```json
{"Effect":"Allow","Principal":{"AWS":"arn:aws:iam::OTHER:role/deployer"},"Action":"sts:AssumeRole"}
```

- MFA 필수
```json
{"Effect":"Allow","Principal":{"AWS":"arn:aws:iam::ACCT:root"},"Action":"sts:AssumeRole",
 "Condition":{"Bool":{"aws:MultiFactorAuthPresent":"true"}}}
```

- SAML (Keycloak 등 IdP)
```json
{"Effect":"Allow","Principal":{"Federated":"arn:aws:iam::ACCT:saml-provider/keycloak"},
 "Action":"sts:AssumeRoleWithSAML",
 "Condition":{"StringEquals":{"SAML:aud":"https://signin.aws.amazon.com/saml"}}}
```

- OIDC — GitHub Actions (특정 repo/브랜치만)
```json
{"Effect":"Allow","Principal":{"Federated":"arn:aws:iam::ACCT:oidc-provider/token.actions.githubusercontent.com"},
 "Action":"sts:AssumeRoleWithWebIdentity",
 "Condition":{"StringEquals":{"token.actions.githubusercontent.com:sub":"repo:OWNER/REPO:ref:refs/heads/main"}}}
```

- OIDC — EKS IRSA (특정 서비스어카운트만)
```json
{"Effect":"Allow","Principal":{"Federated":"arn:aws:iam::ACCT:oidc-provider/oidc.eks.REGION.amazonaws.com/id/XXXX"},
 "Action":"sts:AssumeRoleWithWebIdentity",
 "Condition":{"StringEquals":{"oidc.eks.REGION.amazonaws.com/id/XXXX:sub":"system:serviceaccount:default:my-sa"}}}
```

## Permission policy (권한)

- S3 특정 버킷 읽기전용
```json
{"Effect":"Allow","Action":["s3:GetObject","s3:ListBucket"],
 "Resource":["arn:aws:s3:::BUCKET","arn:aws:s3:::BUCKET/*"]}
```

- DynamoDB 특정 테이블 CRUD (최소권한, 와일드카드 없음)
```json
{"Effect":"Allow",
 "Action":["dynamodb:GetItem","dynamodb:PutItem","dynamodb:Query","dynamodb:UpdateItem","dynamodb:DeleteItem"],
 "Resource":"arn:aws:dynamodb:REGION:ACCT:table/lab-ddb"}
```

- DynamoDB 테이블 + 그 인덱스까지
```json
{"Effect":"Allow","Action":["dynamodb:Query"],
 "Resource":["arn:aws:dynamodb:REGION:ACCT:table/lab-ddb","arn:aws:dynamodb:REGION:ACCT:table/lab-ddb/index/*"]}
```

- Lambda 기본 실행 로그 (CloudWatch Logs)
```json
{"Effect":"Allow","Action":["logs:CreateLogGroup","logs:CreateLogStream","logs:PutLogEvents"],"Resource":"*"}
```

- SQS 큐 소비 (Lambda ESM)
```json
{"Effect":"Allow","Action":["sqs:ReceiveMessage","sqs:DeleteMessage","sqs:GetQueueAttributes"],
 "Resource":"arn:aws:sqs:REGION:ACCT:lab-queue"}
```

- KMS 키로 복호화만
```json
{"Effect":"Allow","Action":["kms:Decrypt","kms:DescribeKey"],"Resource":"arn:aws:kms:REGION:ACCT:key/KEYID"}
```

- Secrets Manager 특정 시크릿 읽기
```json
{"Effect":"Allow","Action":"secretsmanager:GetSecretValue",
 "Resource":"arn:aws:secretsmanager:REGION:ACCT:secret:lab/db-*"}
```

- ECR pull (태스크 이미지 가져오기)
```json
{"Effect":"Allow","Action":["ecr:GetAuthorizationToken","ecr:BatchCheckLayerAvailability","ecr:GetDownloadUrlForLayer","ecr:BatchGetImage"],"Resource":"*"}
```

- 태그 조건부 — 특정 태그 리소스만 제어
```json
{"Effect":"Allow","Action":"ec2:StopInstances","Resource":"*",
 "Condition":{"StringEquals":{"aws:ResourceTag/env":"dev"}}}
```

- 리전 제한 (특정 리전에서만)
```json
{"Effect":"Allow","Action":"*","Resource":"*",
 "Condition":{"StringEquals":{"aws:RequestedRegion":"ap-northeast-2"}}}
```

- 명시적 거부 (Deny 가 Allow 를 이긴다 — 삭제 금지)
```json
{"Effect":"Deny","Action":["dynamodb:DeleteTable","s3:DeleteBucket"],"Resource":"*"}
```

- PassRole 제한 (특정 role 만 서비스에 넘기기 — 권한 상승 방지)
```json
{"Effect":"Allow","Action":"iam:PassRole","Resource":"arn:aws:iam::ACCT:role/lab-task-role",
 "Condition":{"StringEquals":{"iam:PassedToService":"ecs-tasks.amazonaws.com"}}}
```

## Permission boundary (권한 상한선)

- 부여 가능한 최대 권한을 S3/DynamoDB 로 한정 (관리자가 하위 역할에 씌움)
```json
{"Effect":"Allow","Action":["s3:*","dynamodb:*"],"Resource":"*"}
```
> boundary 는 **부여될 수 있는 최대치**만 정의. 실제 권한 = boundary ∩ 연결된 정책. `create-role --permissions-boundary <arn>`.
