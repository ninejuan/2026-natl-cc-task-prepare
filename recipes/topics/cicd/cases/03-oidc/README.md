# GitHub Actions OIDC (장기 키 없이) — 실검증됨
`trust-policy.json` — GHA 가 이 role 을 web-identity 로 assume. 실검증: OIDC provider 생성 + role trust sub=repo:.../main 확인.
```bash
THUMB=6938fd4d98bab03faadb97b34396831e3780aea1
aws iam create-open-id-connect-provider --url https://token.actions.githubusercontent.com \
  --client-id-list sts.amazonaws.com --thumbprint-list $THUMB
sed "s|ACCT|<계정>|;s|OWNER/REPO|myorg/myrepo|" trust-policy.json > /tmp/t.json
aws iam create-role --role-name gha-deploy --assume-role-policy-document file:///tmp/t.json
```
★ sub 조건으로 특정 repo/브랜치만(없으면 아무 repo 나 assume). aud=sts.amazonaws.com. GHA 워크플로는 ../01-gha-ecs/deploy.yml.
