# Lambda@Edge 이미지 리사이징 (origin-response)

`handler.py` — origin-response 에서 이미지 변환/헤더 조작. ★ **런타임 주의(실검증 함정)**: Lambda@Edge 는 표준 Lambda 보다 지원 런타임이 뒤처진다. **python3.12 로 만들면 edge 에서 `502 LambdaValidationError`**(실측). Node.js(nodejs18.x/20.x) 또는 검증된 Python 버전을 쓸 것.

## 배포

```bash
# 1) us-east-1 에 함수 생성(Lambda@Edge 는 us-east-1 필수) + 버전 published
aws lambda create-function --region us-east-1 --function-name edge-resize \
  --runtime nodejs20.x --handler index.handler --role <edge-role> --zip-file fileb://fn.zip
VER=$(aws lambda publish-version --region us-east-1 --function-name edge-resize --query Version --output text)
# 2) 배포의 origin-response 에 <arn>:<VER> 연결(별칭 아님, 버전 ARN)
#    DistributionConfig.DefaultCacheBehavior.LambdaFunctionAssociations
#      [{EventType:"origin-response", LambdaFunctionARN:"<arn>:<VER>"}]
```
- edge role trust: `lambda.amazonaws.com` + `edgelambda.amazonaws.com` 둘 다.
- association·배포 자체는 실검증(config 수락, Deployed) — 런타임만 맞추면 동작.
- 경량 헤더/리라이트는 CloudFront Functions(케이스 02)가 더 싸고 빠름. 이미지 처리·네트워크 호출만 Lambda@Edge.
