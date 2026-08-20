# Cloud Governance / Event Handling 플레이북 (2025 #3 / 2026 #7)

**가이드 원문** — "EC2/Security Group 에 정책 위반 수정이 이뤄지거나 특정 상태로 변하면 **감지 → 알림 또는 원래 상태로 복구** 자동화."
- 필수: VPC, EC2 / 선택: Config, EventBridge, SNS, Lambda, CloudWatch, SSM, CloudTrail, IAM

**★ 3년 연속 출제 영역.** 2026 후보 채점: SG 에 22/0.0.0.0/0 추가 → Lambda → 180초 내 인바운드 0 확인.

**트리거 문구** — "정책 위반 감지", "자동 복구", "SG 변경 감지", "EC2 상태 복구", "규정 준수".

**리전 격리** — 전용. 예시 `ap-northeast-2`.

**기반 카드**: Config·SSM·자동복구 `../../aws/tier3/config-ssm.md`(실검증), EventBridge `../../aws/serverless/eventbridge.md`, Lambda `../../aws/serverless/lambda/`.

---

## 두 경로 (속도 vs 완결성)

| 경로 | 지연 | 언제 |
|---|---|---|
| **EventBridge + Lambda**(권장) | 즉시(초) | CloudTrail API 이벤트 → Lambda 즉시 복구. **채점 3분 안에 확실** |
| **Config rule + remediation** | 수 분 | 평가 지연. recorder 셋업 무거움. 3분 제약에 불리 |

## 케이스 인덱스

| # | 케이스 | 트리거 | 복구 | 상태 |
|---|---|---|---|---|
| 01 | SG 0.0.0.0/0 인바운드 → 즉시 제거 | EventBridge(AuthorizeSecurityGroupIngress) | Lambda revoke | ✅ 실검증 `cases/01-sg-autofix/verify.sh` |
| 02 | EC2 stop → 자동 재시작 | EventBridge(EC2 state-change) | Lambda start | ✅ live(stop→Lambda Invocations=1→running) |
| 03 | Config rule + SSM remediation | restricted-ssh 등 | AWS-DisablePublicAccessForSecurityGroup | ✅ live(recorder recording + rule ACTIVE, 원상복구) |
| 04 | 태그 위반 탐지 → 알림 | EventBridge/Config | SNS | ✅ live(tag-change rule→SNS target) |

### 01 실검증 결과 (ap-northeast-1, 2026-08-20)

`verify.sh {deploy|test|test-trail|teardown}` — VPC+SG, SNS, IAM role, Lambda(handler.py), CloudTrail, EventBridge rule 를 `lab-apne1-*` 로 생성/검증/정리.

- **direct invoke**: SG 에 `tcp/22 0.0.0.0/0` 추가 → Lambda 동기 호출 → 반환 `{"reverted":[{22/tcp 0.0.0.0/0}],"group":sg-...}` → describe 인바운드 `[]` (제거 확인).
- **trail-driven(end-to-end)**: authorize → CloudTrail → EventBridge rule `Invocations=1`, `FailedInvocations=0` → Lambda 실행 → ~10초 내 `0.0.0.0/0:22` 제거.
- **함정(실측)**: (1) 새 CloudTrail 는 첫 delivery 까지 수 분 warm-up — 그 사이 EventBridge 안 뜸. (2) JMESPath 중첩필터 `IpPermissions[?ToPort==\`22\`].IpRanges[?...]` 는 projection 때문에 **비어서 오탐**; `.IpRanges[] | [?CidrIp==\`0.0.0.0/0\`]` 처럼 `[]` 로 flatten 후 필터. (3) 이 계정엔 외부 자동복구 없음(Lambda 경로 끊으면 22 유지됨 확인).

## 케이스 01 복구 Lambda (핵심 패턴)

```python
# cases/01-sg-autofix/handler.py
import boto3
def handler(event, context):
    detail = event["detail"]
    gid = detail["requestParameters"]["groupId"]
    ec2 = boto3.client("ec2")
    # 위반 규칙(0.0.0.0/0) 되돌림
    for item in detail["requestParameters"]["ipPermissions"]["items"]:
        for rng in item.get("ipRanges", {}).get("items", []):
            if rng["cidrIp"] == "0.0.0.0/0":
                ec2.revoke_security_group_ingress(GroupId=gid, IpPermissions=[{
                    "IpProtocol": item["ipProtocol"],
                    "FromPort": item["fromPort"], "ToPort": item["toPort"],
                    "IpRanges": [{"CidrIp": "0.0.0.0/0"}]}])
    boto3.client("sns").publish(TopicArn=os.environ["TOPIC"], Message=f"reverted 0.0.0.0/0 on {gid}")
```

## 검증 (채점자 문체 — 채점이 위반을 만든다)

```bash
# 채점이 SG 에 위반 추가 → N초 후 사라지는지
aws ec2 authorize-security-group-ingress --region $R --group-id $SG --protocol tcp --port 22 --cidr 0.0.0.0/0
sleep 30
aws ec2 describe-security-groups --region $R --group-ids $SG \
  --query "SecurityGroups[0].IpPermissions[?ToPort==\`22\`].IpRanges[?CidrIp=='0.0.0.0/0']" --output text  # 비어야
```

## 함정

- **EventBridge+Lambda 가 빠르다** — Config 는 평가 지연(수 분)으로 3분 채점 불리.
- **CloudTrail 필수** — API Call 기반 감지는 CloudTrail 켜져 있어야(전제).
- **Lambda role 에 ec2:Revoke/Authorize/Describe + sns:Publish**.
- **멱등** — 채점이 여러 번 위반 넣어도 매번 복구돼야.
- Config recorder 는 계정당 1개(이미 있으면 재사용).

## context7 참고

- `aws_cloudwatch_event_rule`(event_pattern) / `aws_config_config_rule` / `aws_config_remediation_configuration` (TF AWS v6)
- Config remediation: https://docs.aws.amazon.com/config/latest/developerguide/remediation.html
