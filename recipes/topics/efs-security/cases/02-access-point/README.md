# EFS Access Point POSIX 격리
access point 로 마운트 시 POSIX uid/gid 강제 + 루트 디렉토리 격리(테넌트별). 실검증은 01-iam-accesspoint/setup.sh 가 access point 까지 함께 생성(uid/gid 1000, root /app 확인됨).
```bash
aws efs create-access-point --file-system-id <fs> \
  --posix-user Uid=1000,Gid=1000 \
  --root-directory 'Path=/app,CreationInfo={OwnerUid=1000,OwnerGid=1000,Permissions=755}'
```
마운트: mount -t efs -o tls,accesspoint=<ap-id> <fs>:/ /mnt  → 앱이 어떤 uid 든 AP 가 1000 으로 덮어씀(격리). 기반: ../../../../aws/tier3/efs.md, 01-iam-accesspoint.
