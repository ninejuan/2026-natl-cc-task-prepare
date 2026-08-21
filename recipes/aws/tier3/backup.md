# AWS Backup

**트리거 문구** — "백업", "복원", "데이터 유실 대비", "백업 정책/보존".

**전제**
```bash
export R=ap-northeast-2
```
DynamoDB PITR·RDS 스냅샷처럼 서비스 자체 백업으로 충분한 경우가 많다. AWS Backup 은 **여러 서비스를 한 정책으로** 관리하거나 중앙 백업 요구 시.

---

## 케이스 A — vault + plan + selection [검증됨: vault·plan]

```bash
# vault (백업 저장소)
aws backup create-backup-vault --region $R --backup-vault-name lab-vault

# plan (스케줄 + 보존)
PLAN=$(aws backup create-backup-plan --region $R --backup-plan '{
  "BackupPlanName":"lab-plan",
  "Rules":[{
    "RuleName":"daily","TargetBackupVaultName":"lab-vault",
    "ScheduleExpression":"cron(0 5 * * ? *)",
    "StartWindowMinutes":60,"CompletionWindowMinutes":120,
    "Lifecycle":{"DeleteAfterDays":7}
  }]}' --query BackupPlanId --output text)

# selection (백업 대상 — 태그 또는 ARN). role 필요
aws backup create-backup-selection --region $R --backup-plan-id $PLAN --backup-selection '{
  "SelectionName":"tagged","IamRoleArn":"arn:aws:iam::ACCT:role/service-role/AWSBackupDefaultServiceRole",
  "ListOfTags":[{"ConditionType":"STRINGEQUALS","ConditionKey":"Backup","ConditionValue":"yes"}]}'
```
- **selection role**: `AWSBackupDefaultServiceRole`(관리형). 없으면 콘솔 첫 진입 시 생성되거나 수동 생성.
- **대상 선택**: 태그(`Backup=yes`) 또는 리소스 ARN 목록.

## 케이스 B — 온디맨드 백업 + 복원 [검증됨: DDB 백업 COMPLETED→복원, 복원본에 백업시점 데이터만]

```bash
# 즉시 백업
aws backup start-backup-job --region $R \
  --backup-vault-name lab-vault \
  --resource-arn arn:aws:dynamodb:$R:ACCT:table/mytable \
  --iam-role-arn <backup-role>

# 복구 지점 목록
aws backup list-recovery-points-by-backup-vault --region $R --backup-vault-name lab-vault \
  --query 'RecoveryPoints[].[RecoveryPointArn,Status]' --output text

# 복원 (새 리소스로)
aws backup start-restore-job --region $R --recovery-point-arn <rp-arn> \
  --iam-role-arn <backup-role> --metadata '{...서비스별 메타...}'
```

## 검증

```bash
aws backup list-backup-vaults --region $R --query 'BackupVaultList[].BackupVaultName' --output text
aws backup get-backup-plan --region $R --backup-plan-id $PLAN --query 'BackupPlan.Rules[].[RuleName,ScheduleExpression]' --output text
aws backup list-recovery-points-by-backup-vault --region $R --backup-vault-name lab-vault --query 'length(RecoveryPoints)' --output text
```

## Terraform

```hcl
resource "aws_backup_vault" "v" { name = "lab-vault" }
resource "aws_backup_plan" "p" {
  name = "lab-plan"
  rule {
    rule_name         = "daily"
    target_vault_name = aws_backup_vault.v.name
    schedule          = "cron(0 5 * * ? *)"
    lifecycle { delete_after = 7 }
  }
}
resource "aws_backup_selection" "s" {
  name         = "tagged"
  plan_id      = aws_backup_plan.p.id
  iam_role_arn = aws_iam_role.backup.arn
  selection_tag {
    type  = "STRINGEQUALS"
    key   = "Backup"
    value = "yes"
  }
}
```

## Console 팁

- **백업 플랜 마법사**: 스케줄·보존·전환(cold storage)을 폼으로 + 리소스 할당(태그/ARN).
- **온디맨드 백업**: 리소스 콘솔(DynamoDB/RDS/EFS 등)에서 "Create backup" 바로.
- **복원**: Vault → recovery point → Restore. 서비스별 복원 옵션을 폼으로(CLI 메타데이터 조립보다 쉬움).

## 참고 문서

- AWS Backup 개발자 가이드: https://docs.aws.amazon.com/aws-backup/latest/devguide/
- Terraform `aws_backup_plan`: https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/backup_plan

## 함정

- **selection role 필요** — `AWSBackupDefaultServiceRole` 또는 백업/복원 권한 role. 없으면 job 실패.
- **cron 6필드** — `cron(0 5 * * ? *)` (AWS 형식, `?` 필수).
- **백업/복원은 시간이 걸린다** — 채점 대기 고려. 온디맨드 백업도 즉시 안 끝남.
- **vault 삭제는 복구 지점 있으면 불가** — 먼저 recovery point 삭제.
- DynamoDB 는 PITR(`dynamodb.md`)이 더 빠른 복원. Backup 은 크로스 서비스·장기 보존용.

## 정리
```bash
aws backup delete-backup-plan --region $R --backup-plan-id $PLAN
aws backup delete-backup-vault --region $R --backup-vault-name lab-vault
```
