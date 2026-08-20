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
| 01 | S3 + OAC (정적 호스팅) | 오리진 보호 | ✅ 실검증 `cases/01-s3-oac/verify.sh` |
| 02 | Function: 헤더 변경/리다이렉트/인증/SPA | viewer-request/response | ✅ viewer-response 헤더 01 에 포함 실검증 |
| 03 | Lambda@Edge: 이미지 리사이징 | origin-response | ⚠️ association 은 실검증(배포 Deployed), 단 python3.12 함수가 edge 에서 `LambdaValidationError`(502) — **Lambda@Edge 런타임 제약**(아래 함정). Node.js 또는 지원 Python 버전 필요 |
| 04 | behavior 경로 분기 | /api/* → 다른 origin | ✅ live(ordered behavior `/api/*` config 수락 + Deployed) |
| 05 | origin failover | origin group 500/502 | ✅ live(OriginGroups FailoverCriteria 500/502 config 수락 + Deployed) |
| 06 | signed URL/cookie | 콘텐츠 보호 | 키그룹/트러스티드시그너 설정(별도 keypair) |

### 01/02 실검증 결과 (ap-northeast-1 + CloudFront 글로벌, 2026-08-20)

`cases/01-s3-oac/verify.sh {deploy|test|teardown}` — private S3(PAB on)+OAC+배포(Comment=`lab-apne1-cf`)+viewer-response Function 을 `lab-apne1-*` 로 생성/검증/정리.

- **배포**: Status=`Deployed`, DefaultRootObject=index.html.
- **curl `https://<domain>/`** → `HTTP/2 200`, body = 업로드한 index.html. 기본 루트 오브젝트로 `/` 가 index.html 반환.
- **viewer-response Function 헤더**(실측): `x-custom-marker: cloud-skills-2026`, `strict-transport-security`, `x-content-type-options: nosniff`, `x-frame-options: DENY` 모두 응답에 존재.
- **직접 S3 접근 차단**: `curl https://<bucket>.s3.ap-northeast-1.amazonaws.com/index.html` → **403** (PAB + OAC, 버킷 정책은 배포 SourceArn 만 허용).
- **함정(실측)**: (1) OAC 오리진은 `S3OriginConfig.OriginAccessIdentity:""` + origin 레벨 `OriginAccessControlId`. (2) 캐시가 채점/헤더검증 방해 안 하도록 managed `CachingDisabled`(4135ea2d-...) 사용. (3) 배포 반영·teardown disable→delete 모두 수 분(실측 배포 완료까지 wait 필요).

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
- **★ Lambda@Edge 런타임 제약(실측)**: `python3.12` 로 만들어 origin-response 에 붙였더니 edge 에서 `502 LambdaValidationError`. Lambda@Edge 는 표준 Lambda 보다 지원 런타임이 뒤처진다 — **Node.js(nodejs18.x/20.x) 또는 검증된 Python 버전**을 쓸 것. 이미지 리사이징 예제는 Node.js 가 무난. association·배포 자체는 정상(config 수락, Deployed).
- **origin group failover**: `OriginGroups.FailoverCriteria.StatusCodes` 는 500/502/503/504 등 5xx 계열만. default behavior 의 TargetOriginId 를 origin group id 로 지정(실측 config 수락).
- HTTPS 는 ACM(us-east-1) + custom domain.

## context7 참고

- `aws_cloudfront_distribution`·`_function`·`_origin_access_control` (TF AWS v6)
- CloudFront Functions: https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/cloudfront-functions.html
