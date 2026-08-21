# EFS 특정 role 만 쓰기 (자격증명 접근제어)

`fs-policy-role-scoped.json` — 지정 role(APP_ROLE)만 mount+write 허용, 나머지 전부 Deny.
"자격 증명 및 액세스 관리"(2025 #12) 요구의 핵심. ★ Linux 파일권한이 아니라 EFS 파일시스템 정책 + IAM 으로.

```bash
sed "s|ACCT|<계정>|g; s|REGION|ap-northeast-2|g; s|FS_ID|<fs-id>|g; s|APP_ROLE|<role명>|g" \
  fs-policy-role-scoped.json > /tmp/p.json
aws efs put-file-system-policy --region ap-northeast-2 --file-system-id <fs-id> --policy file:///tmp/p.json
```

- `AccessedViaMountTarget=true` — mount target 경유만(직접 API 차단).
- `aws:PrincipalArn` 로 특정 role 외 Deny. `ClientRootAccess` 도 Deny 목록에.
- 마운트 시 IAM: `mount -t efs -o tls,iam ...` + 그 role 이 EC2/task role 이어야.
- 기반: `../../../../aws/tier3/efs.md`(파일시스템 정책·access point 실검증).
