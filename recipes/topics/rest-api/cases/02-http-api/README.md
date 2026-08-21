# HTTP API (apigatewayv2) + Lambda + DDB

`handler.py` — REST proxy 와 HTTP API v2 이벤트를 둘 다 처리하는 CRUD 핸들러. 실검증됨(us-west-1: POST→GET 왕복).

## 배포 (quick-create)

```bash
export R=ap-northeast-2 ACCT=$(aws sts get-caller-identity --query Account --output text)
# DDB + Lambda(핸들러) 먼저(케이스 01 참고), 그 다음 HTTP API 를 --target 으로 원샷 생성:
aws apigatewayv2 create-api --region $R --name lab-http --protocol-type HTTP \
  --target "arn:aws:lambda:$R:$ACCT:function:lab-crud"
# Lambda 권한: apigateway 가 호출하도록 add-permission (principal apigateway.amazonaws.com)
# → 반환된 ApiEndpoint 로 curl:
#   curl -XPOST "$EP/lab-crud" -d '{"id":"a1","name":"x"}'   → {"id":"a1"}
#   curl "$EP/lab-crud?id=a1"                                 → {"id":"a1","name":"x"}
```

## 함정 (실측)

- **이벤트 형태 차이**: HTTP API v2 는 `PayloadFormatVersion=2.0` → method 가 `requestContext.http.method`, REST proxy 는 `httpMethod`. `_parse` 가 양쪽 흡수(그래서 같은 handler.py 를 REST/HTTP 둘 다 재사용 가능 — 실검증).
- **★ body base64 인코딩(실측 함정)**: HTTP API 는 `isBase64Encoded:true` 로 body 를 base64 로 줄 수 있다 → 그대로 `json.loads` 하면 `JSONDecodeError: Expecting value: line 1 column 1`. `_parse` 가 base64 디코드 후 파싱(이거 안 하면 POST 가 500). 실검증 중 실제로 밟은 버그.
- quick-create(`--target`)는 `$default` 스테이지 자동 배포 + AWS_PROXY 통합.
- REST 통합 버전은 케이스 01(`../../../rest-api/README.md`) 참조.
