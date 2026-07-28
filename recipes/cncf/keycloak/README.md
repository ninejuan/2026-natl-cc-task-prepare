# Keycloak

SAML/OIDC IdP. 2026 가이드 "Keycloak" 모듈은 **EC2 에 직접 배포**를 요구한다 (`- 필수 : VPC, EC2, IAM, Keycloak`). k8s 배포는 과제지가 허용할 때만.

목표는 보통 이것이다: **Keycloak 로그인 → AWS 콘솔에 IAM Role 로 진입.**

## 어디에 띄우나

| | EC2 (가이드 요구) | k8s |
|---|---|---|
| 언제 | 2026 가이드 Keycloak 모듈 | 과제지가 컨테이너를 허용할 때 |
| 파일 | [`ec2-userdata.sh`](ec2-userdata.sh) | [`deployment.yaml`](deployment.yaml) 외 |

EC2 쪽이 요구사항이면 k8s 매니페스트를 쓰지 마라. 채점이 EC2 인스턴스를 찾는다.

## 파일

| 파일 | 케이스 |
|---|---|
| [`ec2-userdata.sh`](ec2-userdata.sh) | EC2 에 Docker 로 Keycloak + Postgres. systemd 서비스로 등록 |
| [`namespace.yaml`](namespace.yaml) · [`secret.yaml`](secret.yaml) · [`statefulset-postgres.yaml`](statefulset-postgres.yaml) · [`service-postgres.yaml`](service-postgres.yaml) | k8s 배포용 DB |
| [`deployment.yaml`](deployment.yaml) · [`service.yaml`](service.yaml) · [`ingress-alb.yaml`](ingress-alb.yaml) | k8s 배포용 Keycloak |
| [`realm-import-aws-saml.json`](realm-import-aws-saml.json) | **realm 통째 import** — client·mapper·user·role 을 한 번에 |
| [`setup-aws-saml.sh`](setup-aws-saml.sh) | AWS 쪽 설정 (SAML Provider + IAM Role 2개) |

## AWS SAML SSO 흐름

```
브라우저 → Keycloak 로그인 → SAML Assertion → AWS signin/saml → Role 선택 화면 → 콘솔
```

필요한 것이 정확히 네 개다.

1. **Keycloak client** — `saml`, clientId = `urn:amazon:webservices`
2. **Protocol mapper 3개** — `Role`(AWS Role ARN 목록), `RoleSessionName`, `SessionDuration`
3. **AWS SAML Identity Provider** — Keycloak 의 IdP metadata XML 을 업로드
4. **IAM Role 2개** — trust policy 의 Principal 이 그 SAML Provider

`setup-aws-saml.sh` 가 3·4 를 자동화한다. 1·2 는 `realm-import-aws-saml.json` 에 들어 있다.

## 순서

**두 쪽이 서로를 참조하므로 순서가 있다.** Role ARN 을 Keycloak mapper 에 넣어야 하는데, Role trust policy 는 SAML Provider ARN 을 필요로 한다.

```bash
export P=<비번호> R=ap-northeast-2
export KC_URL=http://<keycloak-주소>            # EC2 퍼블릭 IP 또는 ALB DNS

# 1) Keycloak 을 먼저 띄운다 (EC2 user data 또는 k8s)
# 2) realm import — client + mapper + 유저 2명이 들어간다
#    관리 콘솔 → Realm settings → Action → Partial import → realm-import-aws-saml.json
# 3) IdP metadata 를 받아 AWS 쪽 설정
curl -s "$KC_URL/realms/aws/protocol/saml/descriptor" -o /tmp/keycloak-metadata.xml
./setup-aws-saml.sh                              # SAML Provider + admin-access/poweruser-access Role
# 4) 출력된 Role ARN 을 Keycloak 유저의 Role attribute 에 넣는다 (README 아래 참조)
```

## Role attribute 채우기

`Role` mapper 는 유저 attribute 를 읽는다. 각 유저에 아래 형식으로 넣는다.

```
<Role ARN>,<SAML Provider ARN>
```

예:
```
arn:aws:iam::000000000000:role/admin-access,arn:aws:iam::000000000000:saml-provider/keycloak
```

관리 콘솔 → Users → `admin<비번호>` → Attributes → key `Role`, value 위 문자열.
`dev<비번호>` 에는 `poweruser-access` ARN 을 넣는다.

## 확인

```bash
# Keycloak 이 살아 있나
curl -s -o /dev/null -w '%{http_code}\n' "$KC_URL/realms/aws/.well-known/openid-configuration"
curl -s "$KC_URL/realms/aws/protocol/saml/descriptor" | head -3

# AWS 쪽
aws iam list-saml-providers --query 'SAMLProviderList[].Arn' --output text
aws iam get-role --role-name admin-access --query 'Role.AssumeRolePolicyDocument' --output json
aws iam list-attached-role-policies --role-name poweruser-access --query 'AttachedPolicies[].PolicyName' --output text
```

**최종 검증은 브라우저다.** 채점도 브라우저로 한다.

1. 새 창(시크릿)으로 `$KC_URL/realms/aws/protocol/saml/clients/urn:amazon:webservices` 접속
2. `admin<비번호>` 로 로그인
3. AWS Role 선택 화면이 나오는지 — 계정번호와 `admin-access` 가 보여야 한다
4. 로그인 후 우측 상단에 `admin-access/...` 표시 확인
5. `dev<비번호>` 로 같은 절차 → `poweruser-access`

## 함정

- **clientId 는 정확히 `urn:amazon:webservices`** 여야 한다. AWS 가 이 값을 SP Entity ID 로 기대한다.
- **Role mapper 이름은 `Role`, attribute name 은** `https://aws.amazon.com/SAML/Attributes/Role`. 오타 하나면 Role 선택 화면이 안 나온다.
- **`RoleSessionName` mapper 가 없으면** AWS 가 assertion 을 거부한다. 세 mapper 가 다 필요하다.
- **기존 IAM 유저 로그인을 유지하라.** 2024 과제지가 명시했다. SAML 을 붙였다고 IAM 유저를 지우면 감점이다.
- **HTTP 로 운영하면** Keycloak 이 프록시 뒤에서 리다이렉트를 https 로 만들려 해 루프가 난다. `KC_HOSTNAME_STRICT=false` + `KC_PROXY_HEADERS=xforwarded` 를 준다.
- **`start-dev` 는 개발 모드**다. 대회에선 이게 편하지만, 과제지가 운영 구성을 요구하면 `start --optimized` + DB 를 쓴다.
- **인스턴스 크기 상한**(t3.medium 등)을 과제지가 지정하면 넘기지 마라. Keycloak + Postgres 를 한 EC2 에 올리면 t3.small 은 빡빡하다.
- 제출 양식에 **Keycloak 접속 URL 을 적는 칸**이 있다. 적는 것을 잊지 마라 — 2024 과제지에 있었다.
