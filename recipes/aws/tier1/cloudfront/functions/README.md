# CloudFront Functions 모음

경량 엣지 JS(viewer-request/viewer-response). Lambda@Edge 보다 빠르고 싸다 —
헤더 조작·리다이렉트·URL 리라이트·간단 인증에. (무거운 로직·네트워크 호출은 Lambda@Edge)

**전부 실제 `test-function` API 로 컴파일+실행 검증됨.** 런타임 `cloudfront-js-2.0`.

| 파일 | 이벤트 | 용도 |
|---|---|---|
| `viewer-request.js` | viewer-request | A/B 쿠키 배정 + 경로 리라이트 |
| `viewer-response-headers.js` | viewer-response | 보안 헤더(HSTS/nosniff/X-Frame) 추가 |
| `redirect-apex-to-www.js` | viewer-request | apex → www 301 리다이렉트 |
| `basic-auth.js` | viewer-request | HTTP Basic 인증(없으면 401) |
| `spa-rewrite.js` | viewer-request | SPA 라우팅(확장자 없는 경로 → /index.html) |
| `normalize-cache-key.js` | viewer-request | 경로 소문자화 + utm_*/fbclid/gclid 제거(캐시 통합) |
| `geo-country-route.js` | viewer-request | CloudFront-Viewer-Country 로 국가별 경로 분기 |

## 배포

```bash
# 1) 생성 (LIVE 승격 전 DEVELOPMENT 에서 test)
ET=$(aws cloudfront create-function --name lab-fn \
  --function-config "Comment=lab,Runtime=cloudfront-js-2.0" \
  --function-code fileb://viewer-request.js --query ETag --output text)

# 2) 테스트 (배포 없이 실행 — 이벤트 객체로)
aws cloudfront test-function --name lab-fn --if-match "$ET" \
  --stage DEVELOPMENT --event-object fileb://event.json \
  --query 'TestResult.[FunctionErrorMessage,FunctionOutput]' --output text

# 3) LIVE 승격
aws cloudfront publish-function --name lab-fn --if-match "$ET"

# 4) behavior 에 연결 (distribution config 의 DefaultCacheBehavior)
#   "FunctionAssociations":{"Quantity":1,"Items":[
#     {"EventType":"viewer-request","FunctionARN":"<fn-arn>"}]}
```

## 함정

- **런타임 제약**: `cloudfront-js-2.0`. `fetch`·타이머·Buffer 없음. 순수 변환만. 무거운 건 Lambda@Edge.
- **querystring 재할당은 키 순서를 못 바꾼다**(검증됨) — 정렬로 캐시 통합 시도는 no-op. 삭제(delete)로 정규화.
- **viewer-response 에서는 request.uri 수정 불가** — 응답 단계라 이미 늦음. 헤더만.
- **geo/country 헤더**는 배포가 `CloudFront-Viewer-Country` 를 전달하도록 cache/origin request policy 설정 필요.
- **1MB·10ms 제한** — 초과 시 함수 실패(뷰어에 오류). Lambda@Edge 는 더 여유.
- LIVE 승격 전 반드시 `test-function` — 잘못 배포하면 전 트래픽 영향.

## 참고 문서

- CloudFront Functions: https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/cloudfront-functions.html
- 함수 예제: https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/functions-example-code.html
- Lambda@Edge 와 비교: https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/edge-functions-choosing.html
