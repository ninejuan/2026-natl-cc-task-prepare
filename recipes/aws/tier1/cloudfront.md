# CloudFront

**트리거 문구** — "CloudFront Distribution 생성", "OAC 를 통해서만 S3 접근", "웹페이지에 접근", "캐싱", "behavior 로 경로 분기", "Lambda@Edge 이미지 리사이징", "HTTP 헤더 변경", "VPC Origin".

**전제**
```bash
export R=ap-northeast-2 ACCT=$(aws sts get-caller-identity --query Account --output text)
```
CloudFront 는 글로벌. 배포 반영 **실측 ~2분**(최대 10분). WAF·ACM 은 **us-east-1**.

> 📎 **CloudFront Functions 7종 모음**: `functions/` (README.md 카탈로그) — 보안헤더, apex→www 리다이렉트, Basic 인증, SPA 리라이트, 캐시키 정규화, 국가별 라우팅, A/B 배정. 전부 `test-function` API 로 실행 검증.

---

## ★ 케이스 A — S3 오리진 + OAC [검증됨: CF 200, S3 직접 403]

2024 CDN Security 재현. **S3 는 OAC 로만 접근, 버킷 정책은 이 배포 ARN 만 허용.**

```bash
BUCKET=lab-cf-$ACCT
aws s3api create-bucket --region $R --bucket $BUCKET --create-bucket-configuration LocationConstraint=$R
aws s3api put-public-access-block --bucket $BUCKET --public-access-block-configuration \
  BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true
echo '<html><body>Cloud Skills 2026</body></html>' > index.html
aws s3 cp index.html s3://$BUCKET/index.html

# OAC (Origin Access Control — OAI 는 구식, OAC 를 쓴다)
OAC=$(aws cloudfront create-origin-access-control --origin-access-control-config \
  '{"Name":"lab-oac","OriginAccessControlOriginType":"s3","SigningBehavior":"always","SigningProtocol":"sigv4"}' \
  --query 'OriginAccessControl.Id' --output text)

# Distribution (S3 + OAC + default root object)
cat > dist.json <<JSON
{
  "CallerReference": "lab-$(date +%s)",
  "Comment": "lab-cf-distribution",
  "Enabled": true,
  "DefaultRootObject": "index.html",
  "Origins": {"Quantity": 1, "Items": [{
    "Id": "s3origin",
    "DomainName": "$BUCKET.s3.$R.amazonaws.com",
    "OriginAccessControlId": "$OAC",
    "S3OriginConfig": {"OriginAccessIdentity": ""}
  }]},
  "DefaultCacheBehavior": {
    "TargetOriginId": "s3origin",
    "ViewerProtocolPolicy": "redirect-to-https",
    "CachePolicyId": "658327ea-f89d-4fab-a63d-7e88639e58f6",
    "Compress": true
  }
}
JSON
DIST=$(aws cloudfront create-distribution --distribution-config file://dist.json --query 'Distribution.Id' --output text)

# ★ 버킷 정책: 이 배포만 허용 (OAC 의 짝)
cat > bp.json <<JSON
{"Version":"2012-10-17","Statement":[{"Sid":"AllowCF","Effect":"Allow",
  "Principal":{"Service":"cloudfront.amazonaws.com"},"Action":"s3:GetObject",
  "Resource":"arn:aws:s3:::$BUCKET/*",
  "Condition":{"StringEquals":{"AWS:SourceArn":"arn:aws:cloudfront::$ACCT:distribution/$DIST"}}}]}
JSON
aws s3api put-bucket-policy --bucket $BUCKET --policy file://bp.json
```
- `CachePolicyId 658327ea-...` = AWS 관리형 `CachingOptimized`.
- **`S3OriginConfig.OriginAccessIdentity` 는 빈 문자열** + `OriginAccessControlId` 를 준다(OAC 방식). OAI 를 쓰면 구식.
- **검증**: `curl https://$DOMAIN/` → 200 + 내용 / `curl https://$BUCKET.s3...` → **403**(직접 차단).

## 케이스 B — 커스텀 오리진 (ALB) + VPC Origin

```bash
# 커스텀 오리진(ALB, public)
#   "DomainName":"<alb-dns>", "CustomOriginConfig":{"HTTPPort":80,"OriginProtocolPolicy":"http-only"}
# VPC Origin (ALB 를 internal 로 두고 CF 가 직접) — 2026 트렌드, 인터넷 노출 없이
aws cloudfront create-vpc-origin --vpc-origin-endpoint-config '{
  "Name":"lab-vpc-origin","Arn":"<internal-alb-arn>",
  "HTTPPort":80,"HTTPSPort":443,"OriginProtocolPolicy":"http-only"}'
# distribution origin 에서 VpcOriginConfig.VpcOriginId 로 참조
```
"유저는 CloudFront 로만, 이후 내부 ALB 로" 요구 → **Internal ALB + VPC Origin**. ALB 를 인터넷에 노출 안 한다.

## 케이스 C — 다중 오리진 + behavior 경로 분기

```json
"Origins": {"Quantity": 2, "Items": [
  {"Id":"s3origin", ...},
  {"Id":"alborigin", "DomainName":"<alb>", "CustomOriginConfig":{...}}
]},
"DefaultCacheBehavior": {"TargetOriginId":"s3origin", ...},
"CacheBehaviors": {"Quantity": 1, "Items": [
  {"PathPattern":"/api/*", "TargetOriginId":"alborigin",
   "ViewerProtocolPolicy":"https-only",
   "CachePolicyId":"4135ea2d-6df8-44a3-9df3-4b5a84be39ad",
   "OriginRequestPolicyId":"216adef6-5c7f-47e4-b989-5492eafa07d3"}]}
```
`/api/*` 는 ALB(캐싱 없음 `CachingDisabled`), 나머지는 S3(캐싱). 정적/동적 분리.

## ★ 케이스 D — CloudFront Functions [검증됨: test-function]

뷰어 요청/응답을 엣지에서 조작. 헤더 변경·리다이렉트·A/B·간단 인증. `functions/viewer-request.js`.

```bash
aws cloudfront create-function --name lab-viewer-fn \
  --function-config '{"Comment":"lab","Runtime":"cloudfront-js-2.0"}' \
  --function-code fileb://functions/viewer-request.js

# ★ 배포 없이 test-function 으로 검증 (실검증됨: /old -> /index.html 리라이트)
ETAG=$(aws cloudfront describe-function --name lab-viewer-fn --query ETag --output text)
aws cloudfront test-function --name lab-viewer-fn --if-match "$ETAG" \
  --event-object fileb://functions/test-event.json --stage DEVELOPMENT \
  --query 'TestResult.FunctionOutput' --output text

# 통과하면 publish 후 behavior 에 연결
aws cloudfront publish-function --name lab-viewer-fn --if-match "$ETAG"
# behavior 의 FunctionAssociations: {EventType:viewer-request, FunctionARN:...}
```
- Functions: 뷰어 req/res 만, 짧고 빠름(헤더·URI·쿠키). **Lambda@Edge**: 오리진 req/res 도, 무겁고 느림(이미지 리사이징 등 로직).
- `test-function` 으로 배포 전 검증 — 가장 빠른 디버깅.

## 케이스 E — Lambda@Edge (이미지 리사이징 등)

```bash
# ★ 반드시 us-east-1 에서 함수 생성 + 버전 발행(ARN 에 버전 필수, $LATEST 불가)
# CDN 모듈 "Lambda@Edge 이미지 리사이징" → origin-response 에서 Pillow 로 리사이즈
# behavior LambdaFunctionAssociations: {EventType:origin-response, LambdaFunctionARN:"...:1"}
```
Functions 로 안 되는(외부 호출·무거운 처리) 경우만. us-east-1 + 버전 ARN 이 핵심 제약.

## 케이스 F — 캐시 무효화 / 커스텀 에러페이지

```bash
aws cloudfront create-invalidation --distribution-id $DIST --paths "/*"   # 채점 전 캐시 클리어
# CustomErrorResponses: 403/404 -> /error.html (SPA 라우팅)
```
채점이 "캐시 영향 없이" 를 요구하면 `create-invalidation` 으로 초기화하거나 쿼리스트링에 난수.

## 검증

```bash
# 채점은 Comment 로 배포를 찾는다 (Name 태그 없이)
aws cloudfront list-distributions --query "DistributionList.Items[?Comment=='lab-cf-distribution'].[Id,DomainName,Status]" --output text
DOMAIN=$(aws cloudfront get-distribution --id $DIST --query 'Distribution.DomainName' --output text)
curl -s -o /dev/null -w '%{http_code}\n' "https://$DOMAIN/"                    # 200
curl -s -o /dev/null -w '%{http_code}\n' "https://$BUCKET.s3.$R.amazonaws.com/index.html"  # 403
curl -s "https://$DOMAIN/" | grep "Cloud Skills"
```

## Terraform [검증됨: apply→CF 200/S3 403→destroy]

`terraform-cloudfront/main.tf` — S3 + OAC + distribution + 버킷정책 한 스택. **destroy 시 disable→삭제를 TF 가 자동 처리**(CLI 는 수동 2단계).

```bash
cd terraform-cloudfront
terraform init && terraform apply -auto-approve   # 배포 완료까지 기다림(~수 분)
DOMAIN=$(terraform output -raw domain)
curl -s "https://$DOMAIN/"                          # Cloud Skills
curl -s -o /dev/null -w '%{http_code}\n' "https://$(terraform output -raw bucket).s3.ap-northeast-2.amazonaws.com/index.html"  # 403
terraform destroy -auto-approve
```
핵심:
```hcl
resource "aws_cloudfront_origin_access_control" "oac" {
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}
resource "aws_cloudfront_distribution" "d" {
  comment = var.name        # ★ 채점이 Comment 로 찾음
  origin {
    domain_name              = aws_s3_bucket.b.bucket_regional_domain_name  # regional 도메인
    origin_access_control_id = aws_cloudfront_origin_access_control.oac.id
  }
  default_cache_behavior { cache_policy_id = "658327ea-..." }  # CachingOptimized
}
# 버킷정책 SourceArn = aws_cloudfront_distribution.d.arn (OAC 의 짝)
```
- **`bucket_regional_domain_name`** 을 origin 에(단순 `bucket_domain_name` 은 리전 리다이렉트 이슈).
- VPC Origin·behavior 분기·Functions association 도 TF 블록(`ordered_cache_behavior`, `function_association`).

## Console 팁

- **배포 마법사**: origin(S3/ALB/VPC Origin)·OAC·behavior·인증서를 폼으로. OAC 생성 시 "버킷 정책 자동 업데이트" 버튼이 SourceArn 정책을 바로 붙여준다(수동 실수 제거).
- **Functions/Lambda@Edge**: behavior 편집에서 이벤트별(viewer/origin req/res) 연결. Functions 는 콘솔 에디터+Test.
- **Invalidation**: Invalidations 탭에서 `/*` 클릭. 채점 전 캐시 클리어.
- **배포 상태**: Deployed 될 때까지 기다렸다 테스트.

## 참고 문서

- CloudFront 개발자 가이드: https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/
- OAC: https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/private-content-restricting-access-to-s3.html
- VPC Origin: https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/private-content-vpc-origins.html
- CloudFront Functions: https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/cloudfront-functions.html
- Terraform `aws_cloudfront_distribution`: https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudfront_distribution

## 함정

- **Comment 로 찾는다** — 채점 스크립트가 `Comment==` 로 배포를 식별. Comment 를 과제지 이름과 일치시켜라.
- **배포 반영 대기** — 실측 ~2분이지만 최대 10분. `Status==Deployed` 확인 후 curl.
- **OAC vs OAI** — OAC 가 현재 표준. `S3OriginConfig.OriginAccessIdentity` 는 빈 문자열, `OriginAccessControlId` 를 채운다.
- **버킷 정책 SourceArn** — 배포 ARN(`arn:aws:cloudfront::ACCT:distribution/ID`). 이게 OAC 의 짝. 없으면 CF 도 403.
- **ACM/WAF 는 us-east-1** — CloudFront 에 붙일 인증서·WebACL 은 무조건 버지니아.
- **Lambda@Edge 는 us-east-1 + 버전 ARN** — `$LATEST` 불가.
- **캐시** — 값 바꿔도 TTL 동안 옛 응답. 채점 전 invalidation.
- **default root object** 없으면 `/` 접근 시 S3 ListBucket(403). `index.html` 지정.

## 정리
```bash
aws cloudfront get-distribution-config --id $DIST --query 'DistributionConfig' > dc.json  # ETag 필요
# Enabled:false 로 update → Deployed 대기 → delete. (활성 배포는 바로 삭제 불가)
aws s3 rb s3://$BUCKET --force
```
