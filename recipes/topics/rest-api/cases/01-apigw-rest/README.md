# APIGW REST + Lambda + DDB CRUD
`handler.py`(crud-booking 기반) — REST API AWS_PROXY 통합. 실검증(us-west-1 agent: POST /v1/book → GET 왕복).
```bash
aws apigateway create-rest-api --name lab-api
# {proxy+}/ANY → Lambda(AWS_PROXY), deploy stage v1
# curl -XPOST https://<id>.execute-api.<r>.amazonaws.com/v1/book -d '{...}' → {"booking_id":..}
```
기반: ../../../../aws/serverless/lambda/crud-booking/, ../../../../aws/serverless/apigateway.md.
