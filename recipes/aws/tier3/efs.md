# EFS

**트리거 문구** — "EFS 파일시스템", "여러 인스턴스가 공유", "자격 증명 및 액세스 관리"(File System security 모듈), "Access Point", "Lambda 에서 마운트".

**전제**
```bash
export R=ap-northeast-2
```

---

## 케이스 A — 파일시스템 + mount target + access point [검증됨]

```bash
VPC=<vpc>; SUBS="<priv-a> <priv-b>"; SG=<sg>
# 파일시스템 (암호화)
FS=$(aws efs create-file-system --region $R --encrypted \
  --performance-mode generalPurpose --throughput-mode bursting \
  --tags Key=Name,Value=lab-efs --query FileSystemId --output text)
aws efs wait file-system-available --region $R --file-system-id $FS 2>/dev/null || \
  until [ "$(aws efs describe-file-systems --region $R --file-system-id $FS --query 'FileSystems[0].LifeCycleState' --output text)" = available ]; do sleep 6; done

# mount target — 각 AZ 서브넷마다. NFS(2049) SG 필요
for s in $SUBS; do
  aws efs create-mount-target --region $R --file-system-id $FS --subnet-id $s --security-groups $SG
done

# access point (POSIX 사용자 강제 + 루트 디렉토리 격리)
AP=$(aws efs create-access-point --region $R --file-system-id $FS \
  --posix-user "Uid=1000,Gid=1000" \
  --root-directory "Path=/app,CreationInfo={OwnerUid=1000,OwnerGid=1000,Permissions=755}" \
  --query AccessPointId --output text)
```
- **access point**: 마운트할 때마다 POSIX 사용자·루트 디렉토리를 강제. 테넌트/앱별 격리. File System security 모듈의 핵심.
- **mount target SG 는 노드/EC2 SG 로부터 2049(NFS)** 를 허용해야 마운트된다.

## ★ 케이스 B — IAM 접근 제어 (File System security 모듈) [검증됨: topics/efs-security 01·03 — FS policy Allow/Deny]

```bash
# 파일시스템 정책: mount target 경유 + IAM 인증 강제
aws efs put-file-system-policy --region $R --file-system-id $FS --policy '{
  "Version":"2012-10-17","Statement":[{
    "Effect":"Allow","Principal":{"AWS":"*"},
    "Action":["elasticfilesystem:ClientMount","elasticfilesystem:ClientWrite"],
    "Condition":{"Bool":{"elasticfilesystem:AccessedViaMountTarget":"true"}}}]}'
# 특정 role 만 쓰기 허용하려면 Principal 을 그 role ARN 으로, 나머지는 Deny.
```
"자격 증명 및 액세스 관리" 요구 → 파일시스템 정책 + IAM(`elasticfilesystem:ClientMount/ClientWrite/ClientRootAccess`) + access point 조합. **EFS 데이터 보안과 무관한 Linux 보안은 넣지 말 것**(가이드 명시).

## 케이스 C — EC2 / Lambda / ECS 마운트 [검증됨: topics/efs-security 02 — Access Point POSIX 격리]

```bash
# EC2 (amazon-efs-utils)
sudo dnf install -y amazon-efs-utils
sudo mount -t efs -o tls,accesspoint=$AP $FS:/ /mnt/efs

# Lambda (VPC + EFS access point)
aws lambda update-function-configuration --region $R --function-name $FN \
  --file-system-configs "Arn=arn:aws:elasticfilesystem:$R:$ACCT:access-point/$AP,LocalMountPath=/mnt/efs"
#   Lambda 는 VPC 연결 + 서브넷이 mount target 과 같아야. role 에 EFS 권한.

# ECS (task definition volumes)
#   "volumes":[{"name":"efs","efsVolumeConfiguration":{"fileSystemId":"$FS","transitEncryption":"ENABLED","authorizationConfig":{"accessPointId":"$AP","iam":"ENABLED"}}}]
```

## 검증

```bash
aws efs describe-file-systems --region $R --file-system-id $FS \
  --query 'FileSystems[0].[LifeCycleState,Encrypted,NumberOfMountTargets]' --output text
aws efs describe-access-points --region $R --file-system-id $FS \
  --query 'AccessPoints[].[AccessPointId,RootDirectory.Path,PosixUser.Uid]' --output text
aws efs describe-mount-targets --region $R --file-system-id $FS --query 'MountTargets[].LifeCycleState' --output text
# EC2 에서: mount 후 echo test > /mnt/efs/f && cat /mnt/efs/f
```

## Terraform

```hcl
resource "aws_efs_file_system" "fs" {
  encrypted = true
  tags      = { Name = "lab-efs" }
}
resource "aws_efs_mount_target" "mt" {
  for_each        = toset([var.subnet_a, var.subnet_b])
  file_system_id  = aws_efs_file_system.fs.id
  subnet_id       = each.value
  security_groups = [var.sg]   # SG 가 노드/EC2 로부터 2049 허용해야
}
resource "aws_efs_access_point" "ap" {
  file_system_id = aws_efs_file_system.fs.id
  posix_user {
    uid = 1000
    gid = 1000
  }
  root_directory {
    path = "/app"
    creation_info {
      owner_uid   = 1000
      owner_gid   = 1000
      permissions = "755"
    }
  }
}
resource "aws_efs_file_system_policy" "p" { ... }   # IAM 접근제어
```

## Console 팁

- **파일시스템 생성 마법사**: VPC·mount target(AZ별)·성능/처리량 모드·암호화를 폼으로. mount target SG 를 여기서 지정.
- **Access Point**: 콘솔에서 POSIX 사용자·루트 디렉토리를 폼으로. 테넌트 격리를 클릭으로.
- **마운트 도우미**: 파일시스템 콘솔의 "Attach" 가 EC2 mount 명령(TLS·access point 옵션 포함)을 생성.

## 참고 문서

- EFS 사용 설명서: https://docs.aws.amazon.com/efs/latest/ug/
- Access Point: https://docs.aws.amazon.com/efs/latest/ug/efs-access-points.html
- IAM 정책: https://docs.aws.amazon.com/efs/latest/ug/iam-access-control-nfs-efs.html
- Terraform `aws_efs_file_system`: https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/efs_file_system

## 함정

- **mount target SG 2049(NFS)** — 노드/EC2 SG 로부터 허용 안 하면 마운트 타임아웃. 가장 흔한 EFS 실패.
- **AZ 마다 mount target** — 없는 AZ 의 파드/EC2 는 마운트 불가.
- **파일시스템 생성 직후 access point 실패** — "not available". available 대기.
- **Lambda 마운트는 VPC 연결 필수** + 서브넷이 mount target 과 같은 AZ.
- **transit encryption(tls)** — access point 마운트 시 권장. ECS 는 `transitEncryption:ENABLED`.
- File System security 모듈: **EFS 보안만** — OS 방화벽 등 Linux 보안 넣으면 감점.

## 정리
```bash
for mt in $(aws efs describe-mount-targets --region $R --file-system-id $FS --query 'MountTargets[].MountTargetId' --output text); do
  aws efs delete-mount-target --region $R --mount-target-id $mt; done
sleep 30   # mount target 삭제 대기
aws efs delete-access-point --region $R --access-point-id $AP
aws efs delete-file-system --region $R --file-system-id $FS
```
