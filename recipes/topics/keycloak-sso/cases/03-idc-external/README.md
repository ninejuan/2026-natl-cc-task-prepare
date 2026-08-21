# IAM Identity Center + 외부 IdP(Keycloak) — ★ 실검증: 대회형 계정에선 대개 **불가**

IdC 를 SSO 허브로 두고 Keycloak 을 외부 IdP 로 붙이는 구성. 개념은 깔끔한데
**멤버 계정에서는 손댈 수 없다**는 걸 실계정에서 확인했다.

## 실측 (2026-08-21, 계정 156041424727)

이 계정은 조직 `o-afgy8n9da2`(관리계정 `6066…`)의 **멤버 계정**이다.

```bash
$ aws sso-admin list-instances
# → 조직 인스턴스가 보이긴 한다 (OwnerAccountId = 관리계정)
#   { "InstanceArn": "arn:aws:sso:::instance/ssoins-…", "IdentityStoreId": "d-…",
#     "OwnerAccountId": "<관리계정>", "Status": "ACTIVE" }

$ aws sso-admin create-instance --name lab-idc
ServiceQuotaExceededException: You have exceeded IAM Identity Center quotas.
Cannot create more than 1 instance for 156041424727

$ aws sso-admin list-permission-sets --instance-arn arn:aws:sso:::instance/ssoins-…
AccessDeniedException: User … is not authorized to perform: sso:ListPermissionSets
on resource: … because the resource does not exist in this Region,
no resource-based policies allow access, …
```

정리:
1. **자기 IdC 인스턴스를 못 만든다** — 계정당 인스턴스 1개인데, 조직 인스턴스가 이미 그 한 자리를 차지한다.
2. **조직 인스턴스는 읽지도 쓰지도 못한다** — permission set 조회부터 `AccessDenied`.
   IdC 를 구성하려면 **관리계정**이거나 **위임 관리자(delegated administrator)** 로 지정돼야 한다.
3. **식별 소스(identity source)를 외부 IdP 로 바꾸는 것은 콘솔 전용** — 공개 API 가 없다.
   설령 인스턴스가 있어도 Keycloak 연결은 CLI/TF 로 자동화할 수 없다.

## 대회에서의 결론

> 지급 계정이 조직 멤버(대부분 그렇다)이고 IAM 사용자만 준다면
> **IdC 경로는 시도하지 마라. `../01-saml-2role/`(IAM SAML 페더레이션)이 유일하게 되는 길이다.**

SAML 경로는 같은 계정에서 **전부 동작**한다(실검증):
IAM SAML provider 생성 → role 여러 개 → Keycloak 이 `Role` attribute 로 role/provider ARN 쌍을 넘김.
IdP 접근성 검사도 없어서 **VPC 내부 사설 Keycloak 으로도 된다**.

## 그래도 IdC 를 써야 한다면 (관리계정 권한이 있을 때)

```bash
aws sso-admin create-instance --name lab-idc                      # 조직 인스턴스 없을 때만
aws sso-admin create-permission-set --instance-arn $INS --name PowerUser --session-duration PT1H
aws sso-admin attach-managed-policy-to-permission-set --instance-arn $INS \
  --permission-set-arn $PS --managed-policy-arn arn:aws:iam::aws:policy/PowerUserAccess
aws identitystore create-group --identity-store-id $IDS --display-name developers
aws sso-admin create-account-assignment --instance-arn $INS --permission-set-arn $PS \
  --principal-type GROUP --principal-id $GID --target-id <account-id> --target-type AWS_ACCOUNT
# 외부 IdP(Keycloak) 연결: 콘솔 → Settings → Identity source → Change to External identity provider
#   AWS 쪽 SAML metadata 를 받아 Keycloak SAML 클라이언트로 등록하고, Keycloak metadata 를 업로드한다.
```
- 위임 관리자 지정은 **관리계정에서** `aws organizations register-delegated-administrator --service-principal sso.amazonaws.com`.
- 외부 IdP 를 쓰면 사용자/그룹은 **SCIM 프로비저닝**으로 동기화한다(Keycloak 쪽 SCIM 지원 필요).

## 함정

- **인스턴스 quota 는 계정당 1개** — 조직 인스턴스가 있으면 계정 인스턴스를 못 만든다(실측).
- 멤버 계정에서 `list-instances` 는 **되지만** 그 인스턴스에 대한 `sso-admin` 작업은 전부 거부된다. "보이니까 되겠지"가 함정.
- `identitystore` 읽기는 열려 있을 수 있다 — **남의 디렉토리 데이터다. 조회·수정하지 마라.**
- IdC 는 **홈 리전 고정**. 다른 리전에서 부르면 "resource does not exist in this Region".
