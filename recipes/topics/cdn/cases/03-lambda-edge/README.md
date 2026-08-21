# Lambda@Edge 이미지 리사이징 (origin-response) — ✅ **live E2E 검증**

`index.js`(Node.js 20 + sharp) · `package.json` · `verify.sh`(S3+OAC+배포+함수 생성→curl 검증→정리) · `mkpng.py`(테스트 이미지 생성) · `handler.py`(Python 참고본, **런타임 제약으로 비추천**).

## 실검증 결과 (us-east-1 + CloudFront, 2026-08-21)

| 요청 | 결과 |
|---|---|
| `GET /sample.png` | `200`, `x-resized-by: skip`, **PNG 400×300**(원본) |
| `GET /sample.png?w=100` | `200`, `x-resized-by: w=100`, **PNG 100×75** (15,642 B) |
| `GET /sample.png?w=64` | `200`, `x-resized-by: w=64`, **PNG 64×48** |
| S3 직접 접근 | `403` (OAC + PAB) |

→ 엣지에서 **실제로 이미지가 리사이즈되어** 반환된다. 비율은 sharp 가 자동 유지.

## 배포

```bash
# 0) sharp 를 리눅스용으로 받아 함께 zip (macOS 에서 빌드해도 됨)
npm install --os=linux --cpu=x64 --libc=glibc sharp@0.33.5
zip -qr fn.zip index.js node_modules          # 실측 7.1MB (origin-response 한도 50MB)

# 1) us-east-1 에 함수 생성(Lambda@Edge 는 us-east-1 필수) + 버전 published
aws lambda create-function --region us-east-1 --function-name edge-resize \
  --runtime nodejs20.x --handler index.handler --role <edge-role> --zip-file fileb://fn.zip \
  --timeout 15 --memory-size 1024
VER=$(aws lambda publish-version --region us-east-1 --function-name edge-resize --query FunctionArn --output text)

# 2) 배포의 origin-response 에 버전 ARN 연결 (별칭/$LATEST 불가)
#    DefaultCacheBehavior.LambdaFunctionAssociations
#      [{"EventType":"origin-response","LambdaFunctionARN":"<arn>:<VER>","IncludeBody":false}]
```
- edge role trust: **`lambda.amazonaws.com` + `edgelambda.amazonaws.com` 둘 다**. 권한은 `s3:GetObject` + logs.
- 캐시정책 `CachingDisabled`(4135ea2d-…) + 오리진요청정책 **`AllViewerExceptHostHeader`(b689b0a8-…)**.

## ★ 502 를 만드는 함정 3종 (전부 실측으로 뚫음)

1. **`X-Edge-*` 접두사 헤더 금지** — `x-edge-resize` 를 추가했더니
   `502 … The function tried to add a blacklisted header.` CloudFront 예약 접두사다. `x-resized-by` 처럼 다른 이름을 써라.
2. **새 응답 객체를 만들어 반환하지 마라** — `return {status, headers, body}` 로 통째로 갈아끼우면
   `502 … The function tried to add, delete, or change a read-only header.`
   origin 이 준 read-only 헤더(`via`, `transfer-encoding` 등)가 사라지기 때문. **받은 `response` 를 수정해서 반환**할 것(`index.js` 방식). 길이가 바뀌므로 `content-length` 는 `delete`.
3. **OAC 오리진에 `AllViewer` 오리진요청정책을 쓰면 S3 가 403** — `AllViewer` 는 뷰어의 `Host` 헤더까지 전달해 SigV4 서명이 깨진다. **`AllViewerExceptHostHeader`(b689b0a8-53d0-40ab-baf2-68738e2966ac)** 를 써라. (쿼리스트링은 이 정책도 전달하므로 `?w=` 가 함수에 들어온다.)

## 그 외 함정

- **런타임**: `python3.12` 로 만들면 edge 에서 `502 LambdaValidationError`(실측). **Node.js 20 은 정상 동작 확인**.
- **환경변수 불가** — Lambda@Edge 는 env 를 못 쓴다. 버킷/리전은 `request.origin.s3.domainName` 에서 파싱한다(`index.js`).
- **생성 응답 본문 1MB 제한**(origin-request/response). 큰 이미지는 리사이즈 후에도 넘을 수 있다.
- **삭제가 오래 걸린다** — 배포에서 association 을 떼고 Deployed 될 때까지 기다린 뒤 배포 삭제. **함수 자체는 엣지 복제본이 회수될 때까지(수 시간) 삭제 불가**(과금은 없음).
- 경량 헤더/리라이트는 CloudFront Functions(케이스 02)가 더 싸고 빠르다. 이미지 처리·네트워크 호출만 Lambda@Edge.
