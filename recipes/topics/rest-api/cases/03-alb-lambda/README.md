# ALB → Lambda (다른 이벤트 형식)
`handler.py`(alb-response) — ALB target group=lambda. ★ ALB 이벤트는 APIGW 와 다르고, 응답에 statusDescription + isBase64Encoded 필요(없으면 502). 기반: ../../../../aws/serverless/lambda/alb-response/.
