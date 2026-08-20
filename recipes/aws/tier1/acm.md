# ACM (Certificate Manager)

**트리거 문구** — "HTTPS 프로토콜", "아마존 인증서 발급", "ACM 을 통해 인증서", "암호화된 연결", "openssl s_client 로 발급자 확인".

**전제**
```bash
export R=ap-northeast-2
```

> ★ **CloudFront 에 붙일 인증서는 반드시 `us-east-1`.** ALB/API Gateway 는 해당 리전. 이거 틀리면 CloudFront 에서 인증서가 목록에 안 뜬다.

---

## 케이스 A — DNS 검증 (Route53 자동)

DNS 검증이 가장 빠르고 자동 갱신된다. Route53 을 쓰면 검증 레코드를 자동 생성.

```bash
# CloudFront 용은 us-east-1
CERT=$(aws acm request-certificate --region us-east-1 \
  --domain-name "cf.example.com" \
  --validation-method DNS \
  --query CertificateArn --output text)

# 검증용 CNAME 레코드 확인
aws acm describe-certificate --region us-east-1 --certificate-arn "$CERT" \
  --query 'Certificate.DomainValidationOptions[0].ResourceRecord' --output json
# {"Name":"_xxx.cf.example.com.","Type":"CNAME","Value":"_yyy.acm-validations.aws."}

# Route53 에 그 CNAME 을 넣으면 자동 검증 → ISSUED
aws route53 change-resource-record-sets --hosted-zone-id $ZONE --change-batch '{
  "Changes":[{"Action":"UPSERT","ResourceRecordSet":{
    "Name":"<검증 Name>","Type":"CNAME","TTL":300,
    "ResourceRecords":[{"Value":"<검증 Value>"}]}}]}'

aws acm wait certificate-validated --region us-east-1 --certificate-arn "$CERT"
```

## 케이스 B — 와일드카드 / SAN (다중 도메인)

```bash
aws acm request-certificate --region us-east-1 \
  --domain-name "example.com" \
  --subject-alternative-names "*.example.com" "app.example.com" \
  --validation-method DNS
```
`*.example.com` 은 1레벨만(`a.example.com` O, `a.b.example.com` X). apex 도 필요하면 SAN 에 추가.

## CloudFront / ALB 에 연결

```bash
# CloudFront: ViewerCertificate 에 ACMCertificateArn(us-east-1) + SSLSupportMethod:sni-only
#   + Aliases 에 도메인 등록 (CNAME)
# ALB: HTTPS 리스너에 --certificates CertificateArn=<해당 리전 cert>
aws elbv2 create-listener --region $R --load-balancer-arn $ALB \
  --protocol HTTPS --port 443 \
  --certificates CertificateArn=$CERT_SAME_REGION \
  --ssl-policy ELBSecurityPolicy-TLS13-1-2-2021-06 \
  --default-actions Type=forward,TargetGroupArn=$TG
```

## 검증

```bash
aws acm list-certificates --region us-east-1 --query 'CertificateSummaryList[].[DomainName,Status]' --output text
aws acm describe-certificate --region us-east-1 --certificate-arn "$CERT" \
  --query 'Certificate.[Status,DomainName]' --output text     # ISSUED

# 채점 방식: openssl 로 발급자(Amazon) 확인
echo -n "Q" | openssl s_client -connect cf.example.com:443 2>/dev/null | grep -i 'issuer\|i:'
# issuer 에 Amazon 포함되면 ACM 인증서
curl -sI "https://cf.example.com/" | head -1
```

## 함정

- **CloudFront = us-east-1** 인증서. 다른 리전이면 CF 콘솔·API 에서 안 보인다. 가장 흔한 실수.
- **DNS 검증 레코드 오타** → 영구 `PENDING_VALIDATION`. Route53 이면 콘솔의 "Create records in Route53" 버튼(CLI 는 위 change-batch)으로 자동 생성이 안전.
- **`certificate-validated` wait** 로 ISSUED 확인 후 연결. PENDING 인 채로 CF/ALB 에 붙이면 실패.
- **Aliases(CNAME) 등록 없이** 인증서만 붙이면 커스텀 도메인 접근이 안 된다 — CF Aliases + Route53 alias 둘 다.
- **가져온 인증서(import)** 는 자동 갱신 안 됨. 대회에선 ACM 발급(DNS 검증)만.
- ALB 인증서는 **ALB 와 같은 리전**. CF 용(us-east-1)과 별도로 발급해야 할 수 있다.

## 정리
```bash
# CF/ALB 에서 연결 해제 후 삭제 (사용 중이면 삭제 불가)
aws acm delete-certificate --region us-east-1 --certificate-arn "$CERT"
```
