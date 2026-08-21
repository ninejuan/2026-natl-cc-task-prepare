# REST API Implement 플레이북 (2026 #12)

**가이드 원문(2026 #12)** — "Python 으로 데이터 저장/읽기 **POST, GET API** 구현하고 **Lambda 에 배포**. 선수가 코드를 직접 구현."
- 필수: Lambda / 선택: DynamoDB, DocumentDB, APIGW, ELB

**트리거 문구** — "REST API 구현", "POST/GET 직접 구현", "Lambda 로 API", "CRUD API", "API 코드 작성".

**리전 격리** — 전용. 예시 `ap-northeast-2`.

**기반 카드**: CRUD 핸들러 `../../aws/serverless/lambda/crud-booking/handler.py`(실검증), scan API `../../aws/serverless/lambda/dynamodb-scan-api/`, ALB 응답 `../../aws/serverless/lambda/alb-response/`, APIGW `../../aws/serverless/apigateway.md`.

> ★ 선수가 **코드를 직접 구현**하는 모듈. 노출 방식(APIGW/ALB/Function URL)은 선택.

---

## 노출 방식 3종

| 방식 | 특징 | 이벤트 형식 |
|---|---|---|
| **API Gateway REST/HTTP** | 스테이지·인증·매핑 | APIGW proxy event |
| **ALB target** | L7 LB, 헬스체크 | ALB event(다른 형식!) |
| **Function URL** | 최단(단, org SCP 로 auth NONE 막힐 수 있음) | APIGW v2 형식 |

## 케이스 인덱스

| # | 케이스 | 저장소 | 기반 |
|---|---|---|---|
| 01 | APIGW REST + Lambda + DDB CRUD | DynamoDB | `cases/01-apigw-rest/` ✅ live(POST→GET 왕복) |
| 02 | HTTP API(v2) + Lambda | DynamoDB | ✅ live(POST→GET 왕복, base64 body 함정 수정) |
| 03 | ALB → Lambda(다른 이벤트 형식) | DynamoDB | `cases/03-alb-lambda/` ✓ |
| 04 | DocumentDB CRUD | DocumentDB | 코드(handler.py) — DocDB 클러스터+VPC 필요 |
| 05 | 입력 검증 + 에러 응답 | - | `cases/05-input-validation/` ✅ live(필수필드 누락→400) |

## 핵심: POST/GET 핸들러 (이벤트 형식 주의)

```python
# APIGW proxy: event["httpMethod"], event["queryStringParameters"], event["body"]
# HTTP API v2:  event["requestContext"]["http"]["method"], event["rawQueryString"]
# ALB:          event["httpMethod"], event["queryStringParameters"] (+ 응답에 statusDescription 필요)
def handler(event, context):
    method = event.get("httpMethod") or event["requestContext"]["http"]["method"]
    if method == "POST":
        item = json.loads(event["body"]); table.put_item(Item=item)
        return {"statusCode": 201, "body": json.dumps({"id": item["id"]})}
    if method == "GET":
        key = event["queryStringParameters"]["id"]
        r = table.get_item(Key={"id": key})
        return {"statusCode": 200, "body": json.dumps(r.get("Item", {}))}
```

## 검증 (채점자 문체 — curl 왕복)

```bash
# POST 로 넣고 GET 으로 확인 (MARK-PATTERNS 패턴 4)
ID=$(curl -s -X POST "https://$API/v1/items" -d '{"id":"a1","name":"x"}' | jq -r .id)
curl -s "https://$API/v1/items?id=$ID" | jq .
# APIGW 배포 확인
aws apigateway get-rest-apis --region $R --query "items[?name=='lab-api'].id" --output text
```

## 함정

- **이벤트 형식이 노출 방식마다 다르다** — APIGW REST vs HTTP API v2 vs ALB. `httpMethod` 위치 다름.
- **ALB 응답은 `statusDescription` + `isBase64Encoded`** 필요 — 없으면 502.
- **Function URL 은 org SCP 로 auth NONE 막힐 수 있음**(실검증 — 403). 대회 계정이면 APIGW/ALB.
- **APIGW proxy 통합**: `AWS_PROXY` → Lambda 가 전체 응답 구성. 논프록시면 VTL 매핑.
- **CORS** — 브라우저 호출이면 OPTIONS + 헤더.
- DDB 권한(role) + 입력 검증(400) 필수.

## context7 참고

- `aws_lambda_function`·`aws_apigatewayv2_api`(HTTP API)·`aws_lb_target_group`(lambda) (TF AWS v6)
- Lambda + ALB: https://docs.aws.amazon.com/lambda/latest/dg/services-alb.html
- APIGW proxy: https://docs.aws.amazon.com/apigateway/latest/developerguide/set-up-lambda-proxy-integrations.html
