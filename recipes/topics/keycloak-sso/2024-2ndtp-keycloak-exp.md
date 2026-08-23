# 2024 2과제 Keycloak 해설

좋은 과제네요. 이건 **Keycloak을 SAML IdP(Identity Provider)로, AWS를 SP(Service Provider)로** 두고 페더레이션을 거는 전형적인 구성입니다. 기존 IAM 유저 로그인은 그대로 두고, SAML 로그인 경로만 추가하는 거라 서로 충돌하지 않습니다.

전체 흐름부터 잡고 단계별로 갈게요.

## 전체 아키텍처

```
[Local PC 브라우저]
      │  ① Keycloak IdP-initiated SSO URL 접속 → 로그인
      ▼
[Keycloak (EC2 t3.medium)]  ── SAML IdP
      │  ② SAML Assertion (Role 속성 포함) 을 브라우저 통해 POST
      ▼
https://signin.aws.amazon.com/saml
      │  ③ Assertion 검증 → Role 선택/즉시 로그인
      ▼
[AWS Console]  (admin-access / poweruser-access Role로 진입)
```

핵심은 Keycloak이 SAML 응답에 AWS가 요구하는 **특수 속성 3개**를 담아 보내고, AWS IAM이 그걸 신뢰하도록 SAML Provider와 Role을 만들어 두는 것입니다.

AWS가 요구하는 속성:
- `https://aws.amazon.com/SAML/Attributes/Role` → `역할ARN,SAML프로바이더ARN`
- `https://aws.amazon.com/SAML/Attributes/RoleSessionName` → 콘솔에 표시될 세션 이름(보통 username)
- (선택) `https://aws.amazon.com/SAML/Attributes/SessionDuration`

---

## 1단계. EC2에 Keycloak 배포

t3.medium 이하 EC2 하나 띄우고 Docker로 올리는 게 제일 빠릅니다. 보안그룹은 8080/8443만 열면 됩니다.

```bash
docker run -d --name keycloak \
  -p 8080:8080 -p 8443:8443 \
  -e KEYCLOAK_ADMIN=admin \
  -e KEYCLOAK_ADMIN_PASSWORD='관리자비번' \
  -e KC_HOSTNAME=<EC2퍼블릭DNS또는도메인> \
  quay.io/keycloak/keycloak:latest start-dev
```

주의할 점:
- **`KC_HOSTNAME`을 반드시 실제 접속 주소로 지정**하세요. 이걸 안 맞추면 Keycloak이 생성하는 SAML 메타데이터의 엔드포인트 URL이 틀어져서 AWS 페더레이션이 깨집니다. 채점자가 Local PC에서 접근할 그 주소여야 합니다.
- 데모/채점용이면 `start-dev`로 HTTP(8080) 사용도 가능하지만, 가능하면 HTTPS를 권장합니다(도메인 위임 받으면 Let's Encrypt, 아니면 self-signed). SAML 자체는 브라우저 POST라 HTTP로도 동작하지만, Keycloak 프로덕션 모드는 HTTPS를 요구합니다.

---

## 2단계. Keycloak Realm + SAML Client 생성

관리자 콘솔 접속 후:

1. **Realm 생성**: 예 `aws`
2. **SAML Client 생성** (Clients → Create client → Type: SAML)
   - Client ID: `urn:amazon:webservices` ← AWS 표준 Entity ID, 그대로 써야 함
   - Valid redirect URIs: `https://signin.aws.amazon.com/saml`
   - Name ID format: `transient` (또는 persistent)
   - **IDP-Initiated SSO URL name**: 예 `aws` ← 이게 채점자가 접속할 URL 경로가 됩니다
   - Force POST Binding: ON

이렇게 하면 채점자가 접속할 **로그인 시작 주소**가 이렇게 나옵니다:
```
https://<KEYCLOAK주소>/realms/aws/protocol/saml/clients/aws
```
(과제지 맨 아래 "Local PC에서 접근 가능한 Keycloak 주소"에 이걸 적으면 됩니다.)

---

## 3단계. AWS IAM 설정

먼저 Keycloak IdP 메타데이터 URL을 확보합니다:
```
https://<KEYCLOAK주소>/realms/aws/protocol/saml/descriptor
```

그다음 AWS 콘솔에서:

1. **IAM → Identity providers → Add provider → SAML**
   - Provider name: 예 `keycloak`
   - 위 메타데이터 XML 업로드
   - → `arn:aws:iam::계정ID:saml-provider/keycloak` 생성됨

2. **IAM Role 2개 생성** (Trusted entity type: SAML 2.0 federation → 위 provider 선택)
   - `admin-access` → 정책 `AdministratorAccess` 부착
   - `poweruser-access` → 정책 `PowerUserAccess` 부착

각 Role의 신뢰 정책은 이 형태여야 합니다:
```json
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": { "Federated": "arn:aws:iam::계정ID:saml-provider/keycloak" },
    "Action": "sts:AssumeRoleWithSAML",
    "Condition": { "StringEquals": { "SAML:aud": "https://signin.aws.amazon.com/saml" } }
  }]
}
```

기존 IAM 유저는 건드리지 않으므로, 기존 유저는 여전히 IAM 로그인으로 접속 가능합니다. 요구사항 충족.

---

## 4단계. Keycloak — 속성 매퍼 + 유저 + Role 매핑 (핵심)

여기가 제일 헷갈리는 부분입니다. AWS의 Role 속성 값은 반드시 `역할ARN,프로바이더ARN` 문자열이어야 하는데, Keycloak의 "Role list" 매퍼는 **Keycloak Role의 이름을 그대로 속성 값으로 내보냅니다.** 그래서 **Keycloak Role의 이름 자체를 ARN 쌍으로 짓는** 방식을 씁니다.

### 4-1. 클라이언트 매퍼 2개 추가

`urn:amazon:webservices` 클라이언트 → Client scopes(또는 Mappers 탭)에서:

- **매퍼 A — RoleSessionName**
  - Mapper type: `User Property`
  - Property: `username`
  - SAML Attribute Name: `https://aws.amazon.com/SAML/Attributes/RoleSessionName`
  - Name format: `Basic`

- **매퍼 B — Role**
  - Mapper type: `Role list`
  - Role attribute name: `https://aws.amazon.com/SAML/Attributes/Role`
  - SAML Attribute NameFormat: `Basic`
  - **Single Role Attribute: ON**

### 4-2. 클라이언트 Role 2개를 ARN 이름으로 생성

`urn:amazon:webservices` 클라이언트 → Roles → 아래 이름 그대로 Role 생성:

```
arn:aws:iam::계정ID:role/admin-access,arn:aws:iam::계정ID:saml-provider/keycloak
arn:aws:iam::계정ID:role/poweruser-access,arn:aws:iam::계정ID:saml-provider/keycloak
```
(역할ARN이 앞, 프로바이더ARN이 뒤, 콤마로 연결 — 순서 중요)

### 4-3. 유저 생성 + Role 할당

Users → Create user 로 2명 생성 (과제지 표기대로 `admin<비번호>`, `dev<비번호>`), Credentials 탭에서 비밀번호 설정:

- `admin<비번호>` → Role mapping에서 위 **admin-access ARN Role** 할당
- `dev<비번호>` → **poweruser-access ARN Role** 할당

이 유저들은 Keycloak 내부 유저이지 IAM 유저가 아닙니다. 요구사항대로 Keycloak 페이지에서 생성됩니다.

---

## 5단계. 테스트

브라우저(시크릿 창)에서:
```
https://<KEYCLOAK주소>/realms/aws/protocol/saml/clients/aws
```
접속 → Keycloak 로그인 페이지 → `admin<비번호>`로 로그인 → AWS 콘솔로 리다이렉트 → admin-access Role로 진입. `dev<비번호>`는 poweruser-access로 진입.

---

## 꼭 짚고 넘어갈 주의사항 2가지

**① "Role 선택 화면"이 안 뜰 수 있음.** AWS는 SAML 응답에 Role이 **2개 이상**일 때만 선택 화면을 보여줍니다. 지금 설계는 유저당 Role 1개라서 선택 화면 없이 바로 로그인됩니다. 채점 기준에 "Role 선택 화면이 나오는지"가 명시돼 있으니, 안전하게 하려면 **각 유저에게 두 Role을 모두 할당**(admin은 admin+poweruser, dev도 둘 다, 혹은 최소 admin에게 둘 다)해서 선택 화면이 뜨도록 만드는 걸 권장합니다. 다만 과제지의 "admin→admin-access, dev→poweruser-access" 문구와 상충할 수 있으니, 심사 기준을 심사장에게 한 번 확인하는 게 안전합니다.

**② hostname 불일치가 제일 흔한 실패 원인**입니다. Keycloak 메타데이터의 엔드포인트 URL과 실제 접속 주소가 다르면 서명 검증/리다이렉트가 깨집니다. `KC_HOSTNAME`을 채점 접속 주소로 고정하고, 그 상태에서 메타데이터를 뽑아 AWS에 등록하세요. 도중에 주소(IP)가 바뀌면 메타데이터를 다시 등록해야 합니다.

---

원하시면 위 구성을 실제 클릭 순서(최신 Keycloak 관리 콘솔 화면 기준) 스크린샷 흐름으로 더 세분화하거나, HTTPS/도메인까지 포함한 배포 스크립트를 짜드릴 수 있어요. 지금 EC2로 갈지 컨테이너(ECS)로 갈지는 정하셨나요?
