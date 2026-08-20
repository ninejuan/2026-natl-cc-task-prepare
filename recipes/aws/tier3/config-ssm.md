# Config · SSM (governance / 자동 복구)

**트리거 문구** — "정책 위반 감지", "원래 상태로 복구", "자동화", "Parameter Store", "Session Manager", "Run Command", Cloud governance / event handling 모듈.

**전제**
```bash
export R=ap-northeast-2
```

**governance/event handling 은 3년 연속 출제.** "SG/EC2 에 위반 변경 → 감지 → 알림/복구". 두 경로:
- **EventBridge + Lambda**(빠름, 권장) → `../../serverless/eventbridge.md` 케이스 A + `lambda`. CloudTrail 이벤트로 즉시 반응.
- **Config rule + remediation**(느림, recorder 셋업 필요) → 아래 케이스 C.

---

## ★ 케이스 A — SSM Parameter Store [검증됨]

앱 설정·시크릿을 코드 밖에. Secrets Manager 보다 가볍다(회전 없으면).

```bash
aws ssm put-parameter --region $R --name /lab/app/table --value lab-table --type String --overwrite
aws ssm put-parameter --region $R --name /lab/app/password --value 'S3cr3t!' --type SecureString --overwrite  # KMS 암호화
aws ssm put-parameter --region $R --name /lab/app/hosts --value 'a.com,b.com' --type StringList --overwrite

# 조회
aws ssm get-parameter --region $R --name /lab/app/password --with-decryption --query Parameter.Value --output text
aws ssm get-parameters-by-path --region $R --path /lab/app --recursive --with-decryption \
  --query 'Parameters[].[Name,Type]' --output text
```
- **SecureString** 은 KMS 로 암호화. 읽는 주체에 `kms:Decrypt` + `ssm:GetParameter`.
- Lambda/ECS 에서 참조: 환경변수 대신 런타임에 `get-parameter`, 또는 ECS `secrets` 로 주입.

## ★ 케이스 B — 자동 복구 (EventBridge + Lambda, 권장 경로)

"SG 에 0.0.0.0/0 인바운드가 추가되면 즉시 제거" 형. **가장 빠르고 3분 채점 안에 확실.**

```
CloudTrail(SG 변경 API) → EventBridge rule → Lambda(위반 규칙 되돌림) → SNS 알림
```
- EventBridge rule: `../../serverless/eventbridge.md` 케이스 A (eventName: AuthorizeSecurityGroupIngress).
- Lambda: 이벤트에서 groupId 추출 → `revoke-security-group-ingress` → SNS publish.
- **CloudTrail 이 켜져 있어야** API Call 이벤트가 온다(전제).

2026 후보 3모듈 채점이 정확히 이 방식이었다(mark.sh: SG 에 22/0.0.0.0/0 추가 → Lambda invoke → 180초 내 인바운드 0 확인).

## 케이스 C — Config rule + remediation (recorder 필요)

```bash
# 1) Config recorder + delivery channel 먼저 (계정에 없으면 셋업 필요, 느림)
aws configservice put-configuration-recorder --configuration-recorder name=default,roleARN=<config-role> \
  --recording-group allSupported=true
aws configservice put-delivery-channel --delivery-channel name=default,s3BucketName=<bucket>
aws configservice start-configuration-recorder --configuration-recorder-name default

# 2) managed rule (예: restricted-ssh — SG 22 개방 감지)
aws configservice put-config-rule --config-rule '{
  "ConfigRuleName":"restricted-ssh",
  "Source":{"Owner":"AWS","SourceIdentifier":"INCOMING_SSH_DISABLED"}}'

# 3) remediation (SSM Automation 문서로 자동 조치)
aws configservice put-remediation-configurations --remediation-configurations '[{
  "ConfigRuleName":"restricted-ssh","TargetType":"SSM_DOCUMENT",
  "TargetId":"AWS-DisablePublicAccessForSecurityGroup","Automatic":true,
  "Parameters":{...}}]'
```
Config 는 평가에 수 분 걸려 **채점 3분 제약과 안 맞을 수 있다**. governance 를 빠르게 보여줘야 하면 케이스 B(EventBridge).

## 케이스 D — SSM Run Command / Session Manager / Automation

```bash
# Run Command (EC2 에 명령, SSH 없이) — 채점이 EC2 내부 상태 확인에 씀
CMD=$(aws ssm send-command --region $R --instance-ids $EC2 \
  --document-name AWS-RunShellScript \
  --parameters 'commands=["systemctl is-active app && systemctl is-enabled app"]' \
  --query 'Command.CommandId' --output text)
aws ssm get-command-invocation --region $R --command-id $CMD --instance-id $EC2 \
  --query StandardOutputContent --output text

# Session Manager (SSH 키 없이 셸)
aws ssm start-session --region $R --target $EC2

# Automation (다단계 자동화 문서)
aws ssm start-automation-execution --region $R --document-name AWS-RestartEC2Instance \
  --parameters "InstanceId=$EC2"
```
EC2 에 **SSM Agent(AL2023 기본 탑재) + instance profile(AmazonSSMManagedInstanceCore)** 필요. 채점이 `send-command` 로 앱 상태를 확인하는 항목이 있다(`systemctl is-active`).

## 검증

```bash
aws ssm get-parameters-by-path --region $R --path /lab --recursive --query 'Parameters[].Name' --output text
aws configservice describe-config-rules --region $R --query 'ConfigRules[].[ConfigRuleName,ConfigRuleState]' --output text
# 자동복구: SG 에 위반 규칙 넣고 → N초 후 사라지는지
aws ec2 authorize-security-group-ingress --region $R --group-id $SG --protocol tcp --port 22 --cidr 0.0.0.0/0
sleep 30; aws ec2 describe-security-groups --region $R --group-ids $SG --query 'SecurityGroups[0].IpPermissions|length(@)' --output text
```

## 함정

- **governance 는 EventBridge+Lambda 가 빠르다** — Config 는 평가 지연(수 분)으로 3분 채점에 불리.
- **CloudTrail 전제** — API Call 기반 감지는 CloudTrail 이 켜져 있어야.
- **SecureString 읽기 = kms:Decrypt** 필요.
- **Config recorder 는 계정당 1개** — 이미 있으면 재사용, 없으면 role+버킷 셋업(무겁다).
- **Run Command = SSM Agent + instance profile** — 없으면 `send-command` 가 InvalidInstanceId.
- Parameter Store advanced tier(8KB↑, 정책)는 유료. standard 로 충분.

## 정리
```bash
aws ssm delete-parameter --region $R --name /lab/app/table   # 파라미터 각각
aws configservice delete-config-rule --region $R --config-rule-name restricted-ssh
```
