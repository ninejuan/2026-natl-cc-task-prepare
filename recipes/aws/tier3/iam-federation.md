# IAM Federation (Assume · SAML · OIDC · Identity Center)

**트리거 문구** — "Assume role", "External ID", "최소 권한", "SAML SSO", "Keycloak 으로 AWS 로그인", "특정 IAM Role 로 로그인", "IAM Identity Center", "OIDC".

**전제**
```bash
export R=ap-northeast-2 ACCT=$(aws sts get-caller-identity --query Account --output text)
```
> ⚠️ trust policy 의 ARN 은 `${ACCT}:root` 처럼 **중괄호**. zsh `:r`/`:role` modifier 로 `727oot`/`727ole` 로 깨진다(실검증 중 반복 발생).

---

> 📎 **정책 문서 모음**: `iam/policy-documents.md` — trust policy(EC2/Lambda/ECS/External ID/MFA/SAML/OIDC-GitHub/OIDC-IRSA) + permission policy(S3/DDB/KMS/Secrets/ECR/태그·리전 조건/명시적 Deny/PassRole) + permission boundary. identity 정책은 Access Analyzer, trust 정책은 실제 create-role 로 검증.

## ★ 케이스 A — Assume Role + External ID [검증됨]

2026 후보 audit-role("동일 계정 principal 이 External ID 와 함께 assume, 없거나 틀리면 거부, 최대 세션 1시간, 최소권한, 와일드카드 금지").

```bash
cat > trust.json <<JSON
{"Version":"2012-10-17","Statement":[{
  "Effect":"Allow",
  "Principal":{"AWS":"arn:aws:iam::${ACCT}:root"},
  "Action":"sts:AssumeRole",
  "Condition":{"StringEquals":{"sts:ExternalId":"skills-audit-2026<비번호>"}}
}]}
JSON
aws iam create-role --role-name skills-audit-role \
  --assume-role-policy-document file://trust.json \
  --max-session-duration 3600   # 1시간

# 최소권한 (와일드카드 금지 — 특정 액션·리소스만)
aws iam put-role-policy --role-name skills-audit-role --policy-name ro --policy-document '{
  "Version":"2012-10-17","Statement":[{"Effect":"Allow",
    "Action":["dynamodb:DescribeTable","ec2:DescribeVpcs","eks:DescribeCluster"],
    "Resource":["arn:aws:dynamodb:'$R':'$ACCT':table/특정테이블","..."]}]}'
```
검증(실동작 확인):
```bash
RARN="arn:aws:iam::${ACCT}:role/skills-audit-role"
aws sts assume-role --role-arn "$RARN" --role-session-name audit --external-id "skills-audit-2026<비번호>" --query 'AssumedRoleUser.Arn' --output text  # 성공
aws sts assume-role --role-arn "$RARN" --role-session-name audit --query x 2>&1 | grep AccessDenied  # External ID 없으면 거부
```
- **`sts:ExternalId` 조건**이 핵심. 없거나 틀리면 AccessDenied(검증됨).
- **최소권한 = Resource 를 특정 ARN 으로**, `*` 금지. `mark-self.sh --foul` 이 `Action:"*"` 검사.
- 세션 시간: `--max-session-duration 3600`.

## ★ 케이스 B — SAML (Keycloak → AWS 콘솔) [검증됨: SAML provider + role×2 + SAML:aud trust]

Keycloak 상세는 `../../../cncf/keycloak/`(realm import + setup-aws-saml.sh 로 검증됨). AWS 쪽만:

```bash
# 1) Keycloak IdP metadata 로 SAML Provider 등록
aws iam create-saml-provider --name keycloak \
  --saml-metadata-document file://keycloak-metadata.xml

# 2) SAML trust role (2개: admin-access, poweruser-access)
cat > saml-trust.json <<JSON
{"Version":"2012-10-17","Statement":[{
  "Effect":"Allow",
  "Principal":{"Federated":"arn:aws:iam::${ACCT}:saml-provider/keycloak"},
  "Action":"sts:AssumeRoleWithSAML",
  "Condition":{"StringEquals":{"SAML:aud":"https://signin.aws.amazon.com/saml"}}}]}
JSON
aws iam create-role --role-name admin-access --assume-role-policy-document file://saml-trust.json --max-session-duration 3600
aws iam attach-role-policy --role-name admin-access --policy-arn arn:aws:iam::aws:policy/AdministratorAccess
```
Keycloak 유저 attribute `Role` = `<role-arn>,<saml-provider-arn>`. 로그인 → SAML assertion → Role 선택 → 콘솔.

## ★ 케이스 C — IAM Identity Center (IdC) + 외부 IdP [⛔ 실측: org 멤버 계정은 인스턴스 생성 불가 + 조직 인스턴스 접근 거부]

"IdC + Keycloak 연동으로 특정 permission set 으로 로그인" 요구. **IdC 는 조직/계정 레벨 활성화**(콘솔에서 enable)라 CLI 로만은 제한적.

```bash
# IdC 인스턴스 확인 (활성화돼 있어야)
aws sso-admin list-instances --query 'Instances[0].[InstanceArn,IdentityStoreId]' --output text

# permission set 생성 (역할 템플릿)
PS=$(aws sso-admin create-permission-set --region $R \
  --instance-arn <idc-instance-arn> --name skills-admin \
  --session-duration PT1H --query 'PermissionSet.PermissionSetArn' --output text)
aws sso-admin attach-managed-policy-to-permission-set --instance-arn <idc> \
  --permission-set-arn $PS --managed-policy-arn arn:aws:iam::aws:policy/AdministratorAccess

# 계정에 할당 (principal = IdC 유저/그룹)
aws sso-admin create-account-assignment --instance-arn <idc> \
  --permission-set-arn $PS --principal-type GROUP --principal-id <group-id> \
  --target-type AWS_ACCOUNT --target-id $ACCT
```
**외부 IdP(Keycloak) 연동**: IdC 콘솔 → Identity source → External identity provider → Keycloak 의 SAML metadata 업로드 + SCIM(선택). 그 후 IdC 그룹 ↔ permission set ↔ 계정 매핑. Keycloak 유저가 IdC 로그인 → 그 permission set 역할로 계정 진입.

| 방식 | 언제 | 구성 |
|---|---|---|
| SAML(케이스 B) | 단일 계정, Keycloak 직접 | IAM SAML Provider + Role |
| IdC(케이스 C) | 다계정·중앙 관리, permission set | IdC + external IdP + assignment |

과제가 "특정 IAM Role 로 로그인" 단일 계정이면 **B(SAML)가 간단**. "IdC 로" 를 명시하면 C.

## 케이스 D — OIDC (IRSA / GitHub Actions) [검증됨: 실제 GHA 에서 assume 성공 — sub 불변ID 함정 주의]

```bash
# EKS IRSA: ../../../k8s/identity/ (OIDC provider + sub 조건 trust)
# GitHub Actions OIDC:
aws iam create-open-id-connect-provider --url https://token.actions.githubusercontent.com \
  --client-id-list sts.amazonaws.com --thumbprint-list <thumbprint>
# trust: token.actions.githubusercontent.com:sub = repo:OWNER/REPO:ref:refs/heads/main
```
CI 가 장기 키 없이 AWS 접근. GitHub Actions CI/CD 모듈에서.

## 검증

```bash
aws iam get-role --role-name skills-audit-role --query 'Role.[MaxSessionDuration,AssumeRolePolicyDocument]' --output json
aws iam list-saml-providers --query 'SAMLProviderList[].Arn' --output text
aws sso-admin list-permission-sets --instance-arn <idc> --output text
```

## Terraform [role apply 검증됨]

`terraform-iam/main.tf` — External ID assume role + 최소권한 + 세션 1시간. (assume 동작은 CLI 케이스 A 에서 검증)

```hcl
data "aws_iam_policy_document" "assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${data.aws_caller_identity.cur.account_id}:root"]
    }
    condition {
      test     = "StringEquals"
      variable = "sts:ExternalId"
      values   = [var.external_id]   # 비번호 포함이면 var 로
    }
  }
}
resource "aws_iam_role" "audit" {
  assume_role_policy   = data.aws_iam_policy_document.assume.json
  max_session_duration = 3600
}
# SAML: aws_iam_saml_provider + Federated principal
# OIDC: aws_iam_openid_connect_provider + sub 조건
```
- **`aws_iam_policy_document` 데이터 소스**가 JSON 이스케이프·중괄호 함정을 없앤다(zsh ARN 문제 회피).
- IdC 는 `aws_ssoadmin_permission_set`·`aws_ssoadmin_account_assignment`. 단 외부 IdP 연동은 콘솔.

## Console 팁

- **역할 생성 마법사**: trusted entity(AWS account/SAML/OIDC/service)를 라디오로. External ID·세션 시간을 폼으로.
- **IAM Identity Center**: 외부 IdP(Keycloak) 연동은 **콘솔 필수** — Settings → Identity source → External IdP → SAML metadata 업로드. permission set·account assignment 도 콘솔이 직관적.
- **Policy simulator**: 만든 정책이 특정 액션을 허용/거부하는지 시뮬레이션. 최소권한 검증.
- **Access Analyzer**: 외부 접근 가능 리소스를 자동 탐지.

## 참고 문서

- IAM 사용 설명서: https://docs.aws.amazon.com/IAM/latest/UserGuide/
- External ID: https://docs.aws.amazon.com/IAM/latest/UserGuide/id_roles_create_for-user_externalid.html
- SAML federation: https://docs.aws.amazon.com/IAM/latest/UserGuide/id_roles_providers_saml.html
- IAM Identity Center: https://docs.aws.amazon.com/singlesignon/latest/userguide/
- Terraform `aws_iam_role`: https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role

## 함정

- **ARN 조립 zsh 함정** — `${ACCT}:root` 중괄호. (TF `aws_iam_policy_document` 는 이 문제 없음)
- **External ID 는 StringEquals 조건** — 대소문자 정확히. 비번호 포함되면 `$P`.
- **최소권한 = Resource 특정** — `*` 쓰면 감점(`mark-self.sh --foul`).
- **IdC 는 콘솔 활성화 선행** — CLI list-instances 가 비면 미활성. 외부 IdP 연동도 콘솔 SAML metadata 업로드가 핵심(CLI 불가 영역).
- **SAML:aud 조건** 없으면 assertion 거부. `https://signin.aws.amazon.com/saml`.
- **기존 IAM 유저 로그인 유지**(2024 명시) — SAML 붙였다고 기존 유저 지우지 말 것.

## 정리
```bash
aws iam delete-role-policy --role-name skills-audit-role --policy-name ro
aws iam delete-role --role-name skills-audit-role
aws iam delete-saml-provider --saml-provider-arn arn:aws:iam::${ACCT}:saml-provider/keycloak
```
