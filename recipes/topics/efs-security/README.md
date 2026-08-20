# File System Security 플레이북 (2025 #12)

**가이드 원문(2025 #12)** — "EFS 데이터 보안 솔루션. **자격 증명 및 액세스 관리**. ★ EFS 데이터 보안과 무관한 **Linux 시스템 보안 구성은 넣으면 안 됨**(감점)."
- 필수: VPC, EC2, EFS / 선택: IAM

**트리거 문구** — "EFS 접근 제어", "파일시스템 보안", "access point 격리", "IAM 으로 마운트 제어".

**리전 격리** — 전용. 예시 `ap-northeast-2`.

**기반 카드**: EFS(파일시스템·mount target·access point·FS policy) `../../aws/tier3/efs.md`(실검증). 이 플레이북은 그걸 **보안 관점으로 재구성** + 반칙(Linux 보안 넣지 말 것) 강조.

---

## 핵심: "자격 증명 및 액세스 관리" = AWS 레이어만

| 레이어 | 수단 | ✅/❌ |
|---|---|---|
| **파일시스템 정책** | `elasticfilesystem:ClientMount/ClientWrite/ClientRootAccess` IAM | ✅ 이게 핵심 |
| **Access Point** | POSIX uid/gid 강제 + root 디렉토리 격리 | ✅ |
| **전송 암호화** | TLS 마운트(`-o tls`), `transitEncryption` | ✅ |
| **저장 암호화** | KMS (`--encrypted`) | ✅ |
| ~~Linux 파일권한/chmod/SELinux~~ | OS 레벨 | ❌ **감점**(가이드 명시) |

## 케이스 인덱스

| # | 케이스 | 핵심 | 기반 |
|---|---|---|---|
| 01 | FS policy — IAM 마운트 강제 | AccessedViaMountTarget + 특정 role | `cases/01-iam-accesspoint/` ✅ live |
| 02 | Access Point POSIX 격리 | uid/gid + root dir per 앱 | `cases/01-iam-accesspoint/` ✅ live |
| 03 | 특정 role 만 쓰기 | FS policy Principal 제한 + 나머지 Deny | `cases/03-role-scoped/` |

## 검증 (채점자 문체)

```bash
aws efs describe-file-systems --region $R --query 'FileSystems[?Name==`lab-efs`].[Encrypted,LifeCycleState]' --output text
aws efs describe-access-points --region $R --file-system-id $FS \
  --query 'AccessPoints[].[RootDirectory.Path,PosixUser.Uid]' --output text
aws efs describe-file-system-policy --region $R --file-system-id $FS --query Policy --output text | python3 -m json.tool
# 기능: 허용 role 로 마운트 성공, 그 외 role 마운트 거부(AccessDenied)
```

## 함정

- **Linux 보안 넣으면 감점**(가이드 명시) — chmod/iptables/SELinux 로 풀지 말고 EFS 정책+AP+IAM 으로만.
- **FS policy 는 `AccessedViaMountTarget` 조건** + IAM action. `ClientRootAccess` 는 root 마운트 허용(신중히).
- **mount target SG 2049(NFS)** — 노드/EC2 SG 로부터 허용 안 하면 마운트 타임아웃.
- **Access Point 는 POSIX 강제** — 마운트 시 uid/gid 를 AP 가 덮어씀 → 테넌트 격리.
- **TLS 마운트**: `mount -t efs -o tls,accesspoint=$AP $FS:/ /mnt`.
- IAM 마운트: `-o tls,iam` + task/instance role 에 EFS 권한.

## context7 참고

- EFS IAM: https://docs.aws.amazon.com/efs/latest/ug/iam-access-control-nfs-efs.html
- Access Points: https://docs.aws.amazon.com/efs/latest/ug/efs-access-points.html
- `aws_efs_file_system_policy`·`aws_efs_access_point` (TF AWS v6)
