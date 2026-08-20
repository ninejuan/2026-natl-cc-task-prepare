# SSE-KMS 암호화 강제 버킷 정책

`policy.json` — 암호화 없는 업로드 / 다른 KMS 키 업로드 / 평문(HTTP) 접근을 전부 Deny.

```bash
export B=lab-protect-<계정id> KEY=arn:aws:kms:ap-northeast-2:<계정>:key/<키id>
sed "s|BUCKET|$B|g; s|KMS_KEY_ARN|$KEY|g" policy.json > /tmp/p.json
aws s3api put-bucket-policy --bucket $B --policy file:///tmp/p.json
```

`policy.json` 은 `Version`/`Statement` 만 있는 순수 정책 문서라 그대로 `put-bucket-policy` 에 넣어도 된다(주석키 없음). `BUCKET`/`KMS_KEY_ARN` 만 치환.

## 검증

```bash
# 암호화 없는 업로드 → 거부되어야
echo x > /tmp/x; aws s3 cp /tmp/x s3://$B/x                      # AccessDenied (SSE 없음)
aws s3 cp /tmp/x s3://$B/x --sse aws:kms --sse-kms-key-id $KEY   # 성공
# 평문 접근 차단은 aws:SecureTransport=false 조건이 처리
```

기반: 버킷 정책 13종 `../../../../aws/tier2/s3/bucket-policies.md`(자기잠금 함정 포함 — 데이터 액션만 Deny).
