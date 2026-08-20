# CDN 플레이북 (2025 #6 / 2026 #2)

**가이드 원문** — "CloudFront 로 캐싱·엣지 서비스. **Static asset 캐싱, Lambda@Edge 이미지 리사이징, Function 으로 HTTP Header 변경** 등. ★ 채점 시 Cache 등 환경 영향 안 받게 구성."
- 필수: CloudFront / 선택: S3, Lambda, ELB, EC2

**트리거 문구** — "CloudFront 배포", "OAC 로 S3", "엣지에서 헤더 변경", "이미지 리사이징", "캐싱 정책", "behavior 경로 분기".

**리전 격리** — CloudFront 글로벌(WAF·ACM 은 us-east-1). 예시 리소스 `ap-northeast-2`.

**기반 카드**: CloudFront 전 기능 `../../aws/tier1/cloudfront.md`, **CloudFront Functions 7종** `../../aws/tier1/cloudfront/functions/`(test-function 실검증), 이미지리사이즈 핸들러 `../../aws/serverless/lambda/image-resize/handler.py`.

---

## 케이스 인덱스

| # | 케이스 | 엣지 기능 | 검증 |
|---|---|---|---|
| 01 | S3 + OAC (정적 호스팅) | 오리진 보호 | cloudfront.md ✓ |
| 02 | Function: 헤더 변경/리다이렉트/인증/SPA | viewer-request/response | functions 7종 ✓ |
| 03 | Lambda@Edge: 이미지 리사이징 | origin-response | image-resize handler ✓ |
| 04 | behavior 경로 분기 | /api→ALB, /static→S3 | `cases/04-behaviors/` |
| 05 | origin failover | primary/secondary origin group | `cases/05-failover/` |
| 06 | signed URL/cookie | 콘텐츠 보호 | `cases/06-signed/` |

## Function vs Lambda@Edge

| | CloudFront Function | Lambda@Edge |
|---|---|---|
| 실행 | viewer-request/response | + origin-request/response |
| 언어 | JS(cloudfront-js-2.0) | Node/Python |
| 용도 | 헤더·리다이렉트·리라이트(경량) | 이미지 처리·네트워크 호출(무거움) |
| 이미지 리사이징 | ❌ | ✅ (origin-response) |

## 검증 (채점자 문체 — Comment 로 식별!)

```bash
# ★ CloudFront 는 Comment 필드로 식별(태그 아님). Comment 꼭 넣어라.
DIST=$(aws cloudfront list-distributions --query "DistributionList.Items[?Comment=='lab-cf'].Id" --output text)
aws cloudfront get-distribution --id $DIST --query 'Distribution.Status' --output text  # Deployed
# 캐시 히트/헤더 (채점이 x-cache, 커스텀 헤더 확인)
curl -s -o /dev/null -w '%{http_code} x-cache=%header{x-cache}\n' "https://$DOMAIN/index.html"
curl -sI "https://$DOMAIN/" | grep -i 'strict-transport\|x-custom'   # Function 헤더
# 캐시 무효화(채점 전 환경 영향 제거)
aws cloudfront create-invalidation --distribution-id $DIST --paths '/*'
```

## 함정

- **★ Comment 없으면 채점이 배포를 못 찾는다**(MARK-PATTERNS). Comment + Name 태그 필수.
- **캐시 영향 제거**(가이드) — 채점 전 `create-invalidation` 또는 캐시 우회 헤더. TTL 짧게.
- **OAC(신형) 사용** — OAI 는 구식. 버킷 정책은 배포 ARN(SourceArn)만.
- **배포 반영 ~2분**(실측, 최대 10분) — 변경 후 Deployed 대기.
- **Function querystring 재할당은 키순서 못바꿈**(실측) — 정렬 no-op, 삭제로.
- **Lambda@Edge 는 us-east-1 에 배포** + 버전 published(별칭 아님).
- HTTPS 는 ACM(us-east-1) + custom domain.

## context7 참고

- `aws_cloudfront_distribution`·`_function`·`_origin_access_control` (TF AWS v6)
- CloudFront Functions: https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/cloudfront-functions.html
