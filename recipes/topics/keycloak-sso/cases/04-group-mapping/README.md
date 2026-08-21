# Keycloak 그룹 → AWS IAM Role 매핑 (SAML)

Keycloak 그룹 소속에 따라 다른 IAM Role 로 로그인. 2024 원형(admin→admin-access, dev→poweruser-access)의 그룹 기반 버전.
★ Keycloak 서버 검증은 사용자 cncf/k8s 패스에서(`../../../../cncf/keycloak/`). 여기선 AWS↔Keycloak 매핑 규칙.

## SAML assertion 의 Role attribute

AWS SAML 페더레이션은 assertion 의 두 attribute 를 본다:
- `https://aws.amazon.com/SAML/Attributes/Role` = `<role-arn>,<saml-provider-arn>` (여러 값이면 로그인 시 선택)
- `https://aws.amazon.com/SAML/Attributes/RoleSessionName` = 유저 식별자

## Keycloak 쪽 (그룹 → Role attribute)

1. 그룹 생성: `aws-admins`, `aws-developers`.
2. **Group SAML Role mapper**: 각 그룹에 `Role` attribute 값으로 해당 role ARN 쌍을 매핑
   (Client Scopes → mapper, 또는 Group attribute → Script/Hardcoded role mapper).
3. 유저를 그룹에 넣으면 그 그룹의 Role attribute 가 assertion 에 포함.

## AWS 쪽 (그룹별 role×2)

```bash
# SAML provider (Keycloak metadata)
aws iam create-saml-provider --name keycloak --saml-metadata-document file://metadata.xml
# 그룹별 role — trust 는 동일(AssumeRoleWithSAML), 권한만 다르게
#   aws-admins   → admin-access (AdministratorAccess)
#   aws-developers → poweruser-access (PowerUserAccess)
```
trust policy 는 `../../../../aws/tier3/iam/policy-documents.md` 의 SAML 예시(실검증). SAML:aud 조건 필수.

## 검증 (브라우저)

Keycloak 로그인 → AWS Role 선택 화면에 그룹 소속 role 만 표시 → 해당 role 로 콘솔 진입.
(CLI 로는 SAML provider/role 존재까지, 실제 SSO 플로우는 브라우저.)
