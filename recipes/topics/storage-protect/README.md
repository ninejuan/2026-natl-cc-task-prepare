# Storage Data Protect 플레이북 (2025 #8)

**가이드 원문(2025 #8)** — "S3 에 저장되는 데이터 보호. PII 등 민감 데이터 **검색 및 조치**, **Access Point, IAM, Bucket Policy** 접근 제어. 데이터셋은 배포파일로 제공."
- 필수: S3 / 선택: Lambda, Macie, IAM

**트리거 문구** — "민감 데이터 탐지", "PII 검색", "Macie", "Access Point 로 접근 분리", "버킷 정책으로 보호".

**리전 격리** — 전용. 예시 `ap-northeast-2`.

**기반 카드**: 버킷 정책 13종 `../../aws/tier2/s3/bucket-policies.md`, S3 케이스 `../../aws/tier2/s3.md`. 이 플레이북은 **Macie(민감데이터 탐지) + Access Point** 를 얹는다.

---

## 케이스 인덱스

| # | 케이스 | 핵심 | 검증 |
|---|---|---|---|
| 01 | `cases/01-macie/` | Macie 로 PII 자동 탐지 job | 스크립트(미실행: 계정단위 과금) |
| 02 | `cases/02-access-point/` | Access Point(VPC 전용/prefix 격리) | ✅ live(AP+prefix 정책) |
| 03 | `cases/03-encryption-enforce/` | SSE-KMS 강제 + 정책 | 기반 카드 |

## 검증 (채점자 문체)

```bash
# Macie 활성 + job
aws macie2 get-macie-session --region $R --query status --output text   # ENABLED
aws macie2 list-classification-jobs --region $R --query 'items[?name==`lab-pii-scan`].jobStatus' --output text
# Access Point (VPC 전용이면 NetworkOrigin=VPC)
aws s3control list-access-points --account-id $ACCT --bucket lab-protect --query 'AccessPointList[].[Name,NetworkOrigin]' --output text
# 버킷 보호 정책
aws s3api get-bucket-policy --bucket lab-protect --query Policy --output text | python3 -m json.tool
```

## 함정

- **Macie 는 계정 단위 활성화** — `enable-macie` 선행. 이미 켜져 있으면 재사용(끄지 말 것). ⚠️ 활성화하면 계정 단위 과금(최소요금+GB) → 준비 계정에선 실행 안 함(현재 미활성 확인). 현장에선 활성화 후 job 실행.
- **Macie job 은 시간이 걸린다** — 소량이라도 수 분. 채점 3분 제약이면 **미리 실행해 결과 보유** 상태로.
- **Access Point 이름은 계정+리전 유니크**, ARN 을 버킷처럼 사용(`--bucket <ap-arn>`).
- **VPC 전용 AP**: `--vpc-configuration VpcId=...` → NetworkOrigin=VPC. 그 VPC 밖에선 접근 불가.
- **Macie 로 찾은 뒤 "조치"** — 발견(finding)을 EventBridge→Lambda 로 격리/태깅하는 흐름이 "조치". 탐지만이 아니라 대응까지 요구될 수 있음.
- 민감데이터셋은 출제자 제공 — 샘플에 실제 PII 패턴(주민번호/카드번호 형식)이 있어야 Macie 가 탐지.

## context7 참고

- `aws_macie2_account`·`aws_macie2_classification_job`·`aws_s3_access_point` (TF AWS v6)
- Macie 사용 설명서: https://docs.aws.amazon.com/macie/latest/user/
- S3 Access Points: https://docs.aws.amazon.com/AmazonS3/latest/userguide/access-points.html
