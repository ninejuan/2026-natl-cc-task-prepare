# Keycloak SSO 플레이북 (2026 #10, 2024 추가과제 원형)

**가이드 원문(2026 #10)** — "Keycloak 으로 SSO AWS 로그인. EC2 에 직접 배포해 Keycloak 구동."
- 필수: VPC, EC2, IAM, Keycloak / 선택: ELB

**★ 2024 추가과제 실제 출제**: Keycloak SAML SSO — admin\<번호\>·dev\<번호\> 2 유저 → AWS `admin-access`·`poweruser-access` IAM Role 로 각각 로그인. **Keycloak 서버가 선수 계정에 있어야**(반칙검사), 기존 IAM 유저 로그인도 유지.

**트리거 문구** — "Keycloak SSO", "SAML 로 AWS 로그인", "특정 IAM Role 로 로그인", "IdP 페더레이션".

**리전 격리** — 전용. 예시 `ap-northeast-2`.

**기반 카드**: Keycloak(realm import + setup-aws-saml) `../../cncf/keycloak/`(검증됨), IAM federation(SAML/OIDC/IdC) `../../aws/tier3/iam-federation.md`, 정책 문서 `../../aws/tier3/iam/policy-documents.md`(trust 실검증).

---

## 케이스 인덱스

| # | 케이스 | 방식 | 기반 |
|---|---|---|---|
| 01 | SAML → IAM 2 Role (2024 원형) | IAM SAML provider + role×2 | ✅ **AWS 쪽 live**(`verify-aws-side.sh` — provider+role×2+trust 조건 실측) / Keycloak 은 사용자 k8s 패스 |
| 02 | OIDC → IAM Role | OIDC provider | ⚠️ **live 로 제약 발견** — AWS 가 issuer 를 실제 조회해서 **사설 Keycloak 이면 생성 불가**(`cases/02-oidc/`) |
| 03 | IdC + 외부 IdP(Keycloak) | Identity Center | ⛔ **live 로 불가 확인** — org 멤버 계정은 IdC 인스턴스 생성 불가(quota) + 조직 인스턴스 접근 거부. `cases/03-idc-external/` |
| 04 | 그룹별 Role 매핑 | Keycloak group → SAML attr | `cases/04-group-mapping/` (AWS 쪽 role 분리는 01 에서 live) |

## 2024 원형 흐름 (SAML)

```
Keycloak(EC2, 선수계정) ──SAML metadata──> IAM SAML Provider
   유저 admin<번호> (attr Role = admin-access-arn,provider-arn)
   유저 dev<번호>   (attr Role = poweruser-access-arn,provider-arn)
        │ 로그인 → SAML assertion → Role 선택 → AWS Console
```
- IAM: `create-saml-provider` + trust `AssumeRoleWithSAML` + `SAML:aud=https://signin.aws.amazon.com/saml`.
- Keycloak 유저 attribute `Role` = `<role-arn>,<saml-provider-arn>`.
- Role 2개: admin-access(Admin), poweruser-access(PowerUser 이상).

## 검증 (채점자 문체 — 브라우저 중심)

```bash
# AWS 쪽 (CLI 로 확인 가능한 부분)
aws iam list-saml-providers --query 'SAMLProviderList[].Arn' --output text
aws iam get-role --role-name admin-access --query 'Role.AssumeRolePolicyDocument.Statement[0].Principal.Federated' --output text
# ★ 실제 채점은 브라우저: Keycloak 페이지 로그인 → AWS Role 선택 화면 → 각 유저가 해당 Role 로 콘솔 진입
```

## 반칙 자가검사 (2024 명시)

```bash
# Keycloak 서버가 선수 계정에 있어야 (제출 URL 이 선수 계정 리소스인지)
aws ec2 describe-instances --region $R --filters Name=tag:Name,Values='*keycloak*' \
  --query 'Reservations[].Instances[].InstanceId' --output text   # 존재
# 기존 IAM 유저 로그인 유지 — SAML 붙였다고 기존 유저 지우지 말 것
```

## 함정

- **Keycloak 은 선수 계정 EC2 에**(2024 반칙검사) — 외부 호스팅 금지. t3.medium 이하(2024 비용 제한).
- **SAML:aud 조건 필수** — 없으면 assertion 거부.
- **기존 IAM 유저 로그인 유지**(2024 명시) — SAML 추가지 교체 아님.
- **Role attribute 형식**: `role-arn,provider-arn`(쉼표, 순서). 틀리면 Role 선택 안 됨.
- **ARN 조립 zsh 함정** — `${ACCT}:saml-provider/...` 중괄호(iam-federation 카드).
- DNS 는 채점요소 아님(2024) — 필요 시 cloudhrdk 위임 또는 IP 접근.

## context7 참고

- Keycloak: `../../cncf/keycloak/` (realm import·client 설정)
- IAM SAML: https://docs.aws.amazon.com/IAM/latest/UserGuide/id_roles_providers_saml.html
- `aws_iam_saml_provider`·`aws_iam_role`(assume_role_with_saml) (TF AWS v6)
