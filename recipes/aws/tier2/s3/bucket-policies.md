# S3 버킷 정책 패턴 모음

본 문서는 과제에서 자주 요구되는 S3 버킷 정책(bucket policy) 예시 모음이다.
`$B` 는 버킷 이름, `$ACCT` 는 계정 ID. 적용:

```bash
export B=lab-web-$ACCT
aws s3api put-bucket-policy --bucket $B --policy file://policy.json
aws s3api get-bucket-policy --bucket $B --query Policy --output text | python3 -m json.tool  # 확인
```

각 예시는 `Statement` 하나(또는 배열). 실제로는 `{"Version":"2012-10-17","Statement":[ … ]}` 로 감싼다.

## 예시 정책

- HTTPS(TLS) 강제 — 평문 HTTP 요청 전부 거부
```json
{"Sid":"DenyInsecure","Effect":"Deny","Principal":"*","Action":"s3:*",
 "Resource":["arn:aws:s3:::BUCKET","arn:aws:s3:::BUCKET/*"],
 "Condition":{"Bool":{"aws:SecureTransport":"false"}}}
```

- CloudFront OAC 만 GetObject 허용 (그 외 전부 차단, 1과제 핵심)
```json
{"Sid":"AllowOAC","Effect":"Allow","Principal":{"Service":"cloudfront.amazonaws.com"},
 "Action":"s3:GetObject","Resource":"arn:aws:s3:::BUCKET/*",
 "Condition":{"StringEquals":{"AWS:SourceArn":"arn:aws:cloudfront::ACCT:distribution/DISTID"}}}
```

- 퍼블릭 읽기 (정적 웹호스팅 — PAB 해제 필요)
```json
{"Sid":"PublicRead","Effect":"Allow","Principal":"*","Action":"s3:GetObject",
 "Resource":"arn:aws:s3:::BUCKET/*"}
```

- 특정 VPC 엔드포인트에서만 접근 (그 외 거부)
```json
{"Sid":"VpceOnly","Effect":"Deny","Principal":"*",
 "Action":["s3:GetObject","s3:PutObject","s3:DeleteObject","s3:ListBucket"],
 "Resource":["arn:aws:s3:::BUCKET","arn:aws:s3:::BUCKET/*"],
 "Condition":{"StringNotEquals":{"aws:sourceVpce":"vpce-xxxxxxxx"}}}
```
> ⚠️ **자기잠금 함정(실측)**: `Action` 을 `s3:*` 로 하면 `s3:PutBucketPolicy`/`s3:DeleteBucketPolicy` 까지 Deny 되어, VPCe 밖에 있는 **본인(IAM user)이 정책을 못 지운다** → 버킷이 영구 잠김(root 만 해제 가능, 현장엔 root 없음). 반드시 **데이터 액션만** 나열하고 버킷 관리 액션(`s3:*BucketPolicy`, `s3:DeleteBucket`)은 조건 Deny 대상에서 뺀다. IP 화이트리스트도 동일.

- 특정 IP 대역에서만 접근 (사무실 IP 화이트리스트)
```json
{"Sid":"IpAllowlist","Effect":"Deny","Principal":"*",
 "Action":["s3:GetObject","s3:PutObject","s3:DeleteObject","s3:ListBucket"],
 "Resource":["arn:aws:s3:::BUCKET","arn:aws:s3:::BUCKET/*"],
 "Condition":{"NotIpAddress":{"aws:SourceIp":["203.0.113.0/24"]}}}
```

- 다른 계정에 읽기 위임 (크로스 어카운트)
```json
{"Sid":"CrossAcct","Effect":"Allow","Principal":{"AWS":"arn:aws:iam::OTHER_ACCT:root"},
 "Action":["s3:GetObject","s3:ListBucket"],
 "Resource":["arn:aws:s3:::BUCKET","arn:aws:s3:::BUCKET/*"]}
```

- 특정 prefix(폴더)만 접근 허용 — 사용자별 홈 디렉터리
```json
{"Sid":"PrefixScoped","Effect":"Allow","Principal":{"AWS":"arn:aws:iam::ACCT:role/app"},
 "Action":"s3:GetObject","Resource":"arn:aws:s3:::BUCKET/uploads/*"}
```

- SSE-KMS 없는 업로드 거부 (암호화 강제)
```json
{"Sid":"DenyUnencrypted","Effect":"Deny","Principal":"*","Action":"s3:PutObject",
 "Resource":"arn:aws:s3:::BUCKET/*",
 "Condition":{"StringNotEquals":{"s3:x-amz-server-side-encryption":"aws:kms"}}}
```

- 특정 KMS 키가 아니면 업로드 거부
```json
{"Sid":"DenyWrongKey","Effect":"Deny","Principal":"*","Action":"s3:PutObject",
 "Resource":"arn:aws:s3:::BUCKET/*",
 "Condition":{"StringNotEquals":{"s3:x-amz-server-side-encryption-aws-kms-key-id":"arn:aws:kms:REGION:ACCT:key/KEYID"}}}
```

- 버킷 소유자 전체 제어(bucket-owner-full-control) 아니면 업로드 거부
```json
{"Sid":"RequireOwnerFull","Effect":"Deny","Principal":"*","Action":"s3:PutObject",
 "Resource":"arn:aws:s3:::BUCKET/*",
 "Condition":{"StringNotEquals":{"s3:x-amz-acl":"bucket-owner-full-control"}}}
```

- 삭제·정책변경 차단 (읽기전용 잠금, 관리자 role 만 예외)
```json
{"Sid":"DenyDelete","Effect":"Deny","NotPrincipal":{"AWS":"arn:aws:iam::ACCT:role/admin"},
 "Action":["s3:DeleteObject","s3:DeleteBucket","s3:PutBucketPolicy"],
 "Resource":["arn:aws:s3:::BUCKET","arn:aws:s3:::BUCKET/*"]}
```

- 특정 org(조직) 소속 계정만 (Organizations, aws:PrincipalOrgID)
```json
{"Sid":"OrgOnly","Effect":"Allow","Principal":"*","Action":"s3:GetObject",
 "Resource":"arn:aws:s3:::BUCKET/*",
 "Condition":{"StringEquals":{"aws:PrincipalOrgID":"o-xxxxxxxxxx"}}}
```

- ALB 액세스 로그 전송 허용 (ELB 서비스 계정에 PutObject)
```json
{"Sid":"AlbLog","Effect":"Allow","Principal":{"Service":"logdelivery.elasticloadbalancing.amazonaws.com"},
 "Action":"s3:PutObject","Resource":"arn:aws:s3:::BUCKET/alb-logs/AWSLogs/ACCT/*"}
```
