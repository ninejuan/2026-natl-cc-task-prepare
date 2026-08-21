# SAML → IAM Role ×2 (2024 원형) — ✅ AWS 쪽 live 검증

admin → 강한 role, dev → 약한 role. Keycloak 유저의 `Role` attribute 가 `<role-arn>,<provider-arn>`.
실행 스크립트: `../../verify-aws-side.sh`(SAML provider + role×2 생성→조회→삭제).
Keycloak 서버 자체는 사용자 k8s/cncf 패스(`../../../cncf/keycloak/`).

## AWS 쪽 (live 실측)

```bash
# 1) Keycloak realm 의 SAML descriptor 를 그대로 등록
#    (Keycloak: https://<host>/realms/<realm>/protocol/saml/descriptor)
SAML=$(aws iam create-saml-provider --name lab-kc-idp \
  --saml-metadata-document file://kc-metadata.xml --query SAMLProviderArn --output text)

# 2) 같은 provider 를 신뢰하는 role 2개 — 권한만 다르게
aws iam create-role --role-name lab-kc-Admin    --assume-role-policy-document file://t-admin.json --max-session-duration 3600
aws iam create-role --role-name lab-kc-ReadOnly --assume-role-policy-document file://t-ro.json    --max-session-duration 3600
aws iam attach-role-policy --role-name lab-kc-Admin    --policy-arn arn:aws:iam::aws:policy/PowerUserAccess
aws iam attach-role-policy --role-name lab-kc-ReadOnly --policy-arn arn:aws:iam::aws:policy/ReadOnlyAccess
```
trust policy:
```json
{"Effect":"Allow","Principal":{"Federated":"<saml-provider-arn>"},
 "Action":"sts:AssumeRoleWithSAML",
 "Condition":{"StringEquals":{"SAML:aud":"https://signin.aws.amazon.com/saml"}}}
```

## 실측 결과

```
arn:aws:iam::…:saml-provider/lab-kc-idp    ValidUntil=2126-08-21T10:03:44+00:00
get-saml-provider → entityID="https://keycloak.lab.local/realms/aws"

lab-kc-Admin     sts:AssumeRoleWithSAML  Federated=…lab-kc-idp
                 Condition {"StringEquals":{"SAML:aud":"https://signin.aws.amazon.com/saml"}}   PowerUserAccess
lab-kc-ReadOnly  sts:AssumeRoleWithSAML  Federated=…lab-kc-idp
                 Condition {"StringEquals":{"SAML:aud":"…","SAML:sub_type":"persistent"}}       ReadOnlyAccess
```
`assume-role-with-saml` 에 가짜 assertion 을 넣으면 `InvalidIdentityToken: Invalid base64 SAMLResponse` —
API 경로 자체는 열려 있고 **실제 서명된 assertion 만 있으면 되는 상태**임을 확인.

## 함정 (실측)

- **★ SAML provider 는 IdP 접근성을 검사하지 않는다** — 존재하지 않는 `keycloak.lab.local` 메타데이터로도 생성된다.
  그래서 **사설 Keycloak(VPC 내부)이라도 SAML 은 된다.** 반대로 **OIDC 는 issuer 를 실제로 조회**해서 사설 Keycloak 이면 실패한다(`../02-oidc/`).
- `ValidUntil` 이 자동으로 100년 뒤로 잡힌다 — 만료 걱정 없음.
- `SAML:aud` 는 **`https://signin.aws.amazon.com/saml`** 고정(콘솔 SSO). 빼면 아무 SAML 이나 이 role 을 먹을 수 있다.
- **메타데이터 XML 구조를 검증한다** — `EntityDescriptor`/`IDPSSODescriptor`/`KeyDescriptor(X509Certificate)`/`SingleSignOnService` 가 있어야 한다.
- Keycloak 쪽 `Role` attribute 는 `<role-arn>,<saml-provider-arn>` **쉼표 한 개, 공백 없음**. 순서 바뀌면 로그인 실패.
- role 2개 이상이 assertion 에 들어오면 AWS 로그인 화면에서 **role 선택 UI** 가 뜬다(2024 원형이 이 형태).
