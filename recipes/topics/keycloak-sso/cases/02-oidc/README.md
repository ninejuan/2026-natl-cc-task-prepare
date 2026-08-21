# OIDC → IAM Role (Keycloak) — ★ 실검증 중 발견한 결정적 제약

Keycloak 을 **OIDC** provider 로 등록해 `sts:AssumeRoleWithWebIdentity` 로 임시자격을 받는 방식.
기반: `../../../../aws/tier3/iam-federation.md`. 실행 스크립트: `../../verify-aws-side.sh`.

```bash
aws iam create-open-id-connect-provider \
  --url https://<keycloak>/realms/<realm> \
  --client-id-list sts.amazonaws.com \
  --thumbprint-list <IdP TLS 인증서 SHA1 지문>
```
trust policy (조건 키는 **issuer URL 에서 `https://` 를 뗀 문자열**로 시작한다):
```json
{"Effect":"Allow","Principal":{"Federated":"<oidc-provider-arn>"},
 "Action":"sts:AssumeRoleWithWebIdentity",
 "Condition":{
   "StringEquals":{"<keycloak>/realms/<realm>:aud":"sts.amazonaws.com"},
   "StringLike":{"<keycloak>/realms/<realm>:sub":"service-account-*"}}}
```

## ★ 실측: 접근 불가능한 issuer 로는 provider 를 만들 수 없다

`--url https://keycloak.lab.local/realms/aws` 로 시도했더니:
```
An error occurred (InvalidInput) when calling the CreateOpenIDConnectProvider operation: Unknown
```
AWS 가 **issuer 의 `/.well-known/openid-configuration` 을 실제로 가져가 검증**하기 때문이다.
→ **Keycloak 이 인터넷에서 HTTPS 로 접근 가능하고 유효한 인증서를 가져야** OIDC 경로를 쓸 수 있다.

**대회 함의**: Keycloak 을 VPC 안 EC2/EKS 에 사설로 띄운 상태라면 **OIDC 는 못 쓴다**.
- 사설 Keycloak → **SAML 경로**(`../01-saml-2role/`)를 써라. SAML provider 는 **메타데이터 XML 만 있으면 되고 IdP 접근성을 검사하지 않는다**(실측 — 존재하지 않는 `keycloak.lab.local` 로도 생성 성공).
- OIDC 를 꼭 써야 하면 Keycloak 에 퍼블릭 도메인 + ACM/Let's Encrypt 인증서를 붙여 ALB 로 노출한 뒤 등록.

## 그 외 함정

- 조건 키에 `https://` 를 넣으면 **절대 매칭되지 않는다**(에러도 안 난다). `keycloak.example.com/realms/aws:aud` 형태.
- `client-id-list` = OIDC `aud`. Keycloak 클라이언트 ID 와 정확히 같아야 한다.
- 지문(thumbprint)은 IdP TLS 체인의 **최상위 중간 CA** SHA1. 인증서 갱신으로 CA 가 바뀌면 갱신 필요(`update-open-id-connect-provider-thumbprint`).
- GitHub Actions OIDC 와 완전히 같은 메커니즘이다 — `../../../cicd/cases/03-oidc/`(live 검증) 참고.
