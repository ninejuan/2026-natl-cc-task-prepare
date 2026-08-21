# GitHub Actions OIDC (장기 키 없이) — ✅ live 검증 + ★ 함정 규명

`trust-policy.json`. GHA 가 이 role 을 web-identity 로 assume 한다.
실제 GitHub repo(`ninejuan/lab-gha`)에서 워크플로를 돌려 **끝까지 검증**했다(`../01-gha-ecs/`).

```bash
aws iam create-open-id-connect-provider --url https://token.actions.githubusercontent.com \
  --client-id-list sts.amazonaws.com \
  --thumbprint-list 6938fd4d98bab03faadb97b34396831e3780aea1
sed 's|ACCT|<계정>|; s|OWNER|myorg|g; s|REPO|myrepo|g' trust-policy.json \
  | jq 'with_entries(select(.key|startswith("_")|not))' > /tmp/t.json
aws iam create-role --role-name gha-deploy --assume-role-policy-document file:///tmp/t.json
```
워크플로에는 `permissions: {id-token: write, contents: read}` 가 **반드시** 있어야 한다.

## ★★ 최대 함정 — `sub` 클레임에 불변 ID 가 들어간다 (실측)

인터넷의 모든 예제(그리고 이 카드의 예전 버전)는 이렇게 쓴다:
```json
"StringEquals": {"token.actions.githubusercontent.com:sub": "repo:OWNER/REPO:ref:refs/heads/main"}
```
그런데 **실제 GitHub 이 보내는 토큰의 sub 는 이랬다**(워크플로 안에서 JWT 를 디코드해 확인):
```
sub        = repo:ninejuan@79080468/lab-gha@1341682700:ref:refs/heads/main
aud        = sts.amazonaws.com
iss        = https://token.actions.githubusercontent.com
repository = ninejuan/lab-gha
```
`OWNER@<owner_id>` / `REPO@<repo_id>` 형태로 **숫자 불변 ID 가 끼어든다**(GitHub 의 immutable identifier 기능).
`StringEquals` 로 옛 형식을 고정해 두면 **절대 매칭되지 않는다**.

증상이 특히 고약하다:
```
##[error]Could not assume role with OIDC: Not authorized to perform sts:AssumeRoleWithWebIdentity
```
`configure-aws-credentials` 가 **약 2분간 12번 재시도**한 뒤에야 이 한 줄만 뱉는다. 왜 안 맞는지는 안 알려준다.

**고친 형태**(양쪽 형식 모두 매칭 + `repository` 로 조임):
```json
"StringEquals": {
  "token.actions.githubusercontent.com:aud": "sts.amazonaws.com",
  "token.actions.githubusercontent.com:repository": "OWNER/REPO"
},
"StringLike": {
  "token.actions.githubusercontent.com:sub": "repo:OWNER*/REPO*:ref:refs/heads/main"
}
```
→ 이 정책으로 바꾸자 **바로 assume 성공**(실측).

## 진단법 (막혔을 때 이걸 먼저 해라)

워크플로에 이 스텝을 넣으면 실제 클레임을 볼 수 있다. 원인 파악이 30초로 끝난다.
```yaml
- name: debug OIDC claims
  run: |
    T=$(curl -sS -H "Authorization: bearer $ACTIONS_ID_TOKEN_REQUEST_TOKEN" \
         "$ACTIONS_ID_TOKEN_REQUEST_URL&audience=sts.amazonaws.com" \
         | python3 -c 'import sys,json;print(json.load(sys.stdin)["value"])')
    python3 - "$T" <<'PY'
    import sys,base64,json
    p=sys.argv[1].split('.')[1]; p+='='*(-len(p)%4)
    c=json.loads(base64.urlsafe_b64decode(p))
    for k in ("sub","aud","iss","repository"): print(k,"=",c.get(k))
    PY
```

## 그 외 함정 (실측)

- **`sub`/`job_workflow_ref` 조건이 없으면 AWS 가 정책 자체를 거부한다**:
  `MalformedPolicyDocument: Trust policy with trusted principal … must evaluate, using StringEquals, StringLike or StringEqualsIgnoreCase, token.actions.githubusercontent.com:sub or …:job_workflow_ref which is not scoped to all.`
  → `aud` 만 걸고 넘어갈 수 없다. 조건 없이 넓게 열 수 없게 AWS 가 막아준다.
- **`token.actions.githubusercontent.com:repository` 도 조건 키로 쓸 수 있다**(실측 수락). `sub` 와 같이 걸면 와일드카드를 써도 안전하다.
- `aud=sts.amazonaws.com` 은 `configure-aws-credentials` 기본값.
- 브랜치를 안 가리려면 `…:*`, PR 도 허용하려면 `repo:OWNER*/REPO*:pull_request`.
- 지문(thumbprint)은 넣되, AWS 는 잘 알려진 IdP 에 대해 자체 신뢰 저장소를 쓴다 — 지문 불일치가 원인인 경우는 드물다.
- Keycloak OIDC 도 **완전히 같은 메커니즘**이다 — `../../keycloak-sso/cases/02-oidc/` 참고(단, 사설 issuer 는 provider 생성 자체가 안 된다).
