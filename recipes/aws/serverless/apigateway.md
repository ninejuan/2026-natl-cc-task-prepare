# API Gateway

**트리거 문구** — "REST API 를 제공", "integration type은 AWS Service Proxy", "Lambda 없이", "GET 요청만 지원", "query string 으로 ~를 받으면 403", "Stage name: v1".

**전제**
```bash
export R=ap-northeast-2 ACCT=$(aws sts get-caller-identity --query Account --output text)
```

> ⚠️ **zsh 함정 (검증 환경이 macOS zsh 일 때).** `"$ACCT:role"`, `"$R:states"` 처럼 **변수 바로 뒤에 `:영문자`** 가 오면 zsh 가 `:r`(root)·`:s`(subst) 등 변수 modifier 로 해석해 값을 잘라먹는다 (`156041424727ole`, `ap-northeast-2tates`). 두 가지 회피:
> 1. **중괄호로 감싼다**: `arn:aws:apigateway:${R}:states:action/StartExecution` ← 확실.
> 2. **ARN 은 조회로 받는다**: `ROLE=$(aws iam get-role --role-name X --query Role.Arn --output text)`.
> 현장 지급 PC(Windows PowerShell)는 무관하지만 로컬 zsh 검증에서 계속 밟는다. bash 는 영향 없음.

## VTL 템플릿 라이브러리

`vtl/` 에 검증된 매핑 템플릿이 있다. 상황에 맞는 걸 골라 `--request-templates`/`--response-templates` 로 넣는다.

| 파일 | 용도 | 검증 |
|---|---|---|
| `vtl/ddb-getitem-req.vtl` | querystring→GetItem, 빈값 400, mysecret* 403 | ✅ |
| `vtl/ddb-value-raw-res.vtl` | value.N 만 raw 출력(따옴표 없이), 없으면 404 | ✅ |
| `vtl/ddb-query-json-res.vtl` | Query 결과(Items[])→깔끔한 JSON 배열(`#foreach`+콤마) | ✅ 실 API 확인 |
| `vtl/sns-publish-req.vtl` | POST body→SNS Publish (form-urlencoded) | 문법 |
| `vtl/sfn-start-req.vtl` | POST body→SFN StartExecution input | ✅ 실 API 확인 |
| `vtl/validate-transform-req.vtl` | 필수필드 검증+400, context/stage 값 주입 | 문법 |

넣는 법(VTL 을 JSON 문자열로 안전하게 감싸기):
```bash
python3 -c "import json;print(json.dumps({'application/json':open('vtl/ddb-getitem-req.vtl').read()}))" > /tmp/req.json
aws apigateway put-integration ... --request-templates file:///tmp/req.json
```

---

## ★ 케이스 A — AWS Service 직접통합 (Lambda 없이 DynamoDB) [검증됨: topics/workflow 05 — lambda=[] 로 SFN·DDB 직접통합]

**2025 inventory 과제가 이거였다.** "별도 컴퓨팅 서비스 사용 불가, integration type AWS Service Proxy" → API Gateway 가 DynamoDB 를 직접 호출. 아래는 실제로 `1000`/`100` raw 출력 + `mysecret*`→403 까지 검증된 전체 흐름.

### 1) DynamoDB + 시드
```bash
aws dynamodb create-table --region $R --table-name lab-inv \
  --attribute-definitions AttributeName=name,AttributeType=S \
  --key-schema AttributeName=name,KeyType=HASH --billing-mode PAY_PER_REQUEST
aws dynamodb wait table-exists --region $R --table-name lab-inv
aws dynamodb put-item --region $R --table-name lab-inv --item '{"name":{"S":"balance"},"value":{"N":"1000"}}'
aws dynamodb put-item --region $R --table-name lab-inv --item '{"name":{"S":"stock"},"value":{"N":"100"}}'
```

### 2) API Gateway 가 GetItem 하도록 role
```bash
cat > agw-trust.json <<'JSON'
{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":"apigateway.amazonaws.com"},"Action":"sts:AssumeRole"}]}
JSON
aws iam create-role --role-name lab-apigw-ddb --assume-role-policy-document file://agw-trust.json
cat > agw-perm.json <<'JSON'
{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Action":["dynamodb:GetItem"],"Resource":"*"}]}
JSON
aws iam put-role-policy --role-name lab-apigw-ddb --policy-name ddb --policy-document file://agw-perm.json
sleep 8
ROLE=$(aws iam get-role --role-name lab-apigw-ddb --query Role.Arn --output text)   # 조립 금지
```

### 3) REST API + /inventory + GET
```bash
API=$(aws apigateway create-rest-api --region $R --name lab-inv-api --query id --output text)
ROOT=$(aws apigateway get-resources --region $R --rest-api-id $API --query 'items[0].id' --output text)
RES=$(aws apigateway create-resource --region $R --rest-api-id $API --parent-id $ROOT --path-part inventory --query id --output text)
aws apigateway put-method --region $R --rest-api-id $API --resource-id $RES \
  --http-method GET --authorization-type NONE \
  --request-parameters "method.request.querystring.item=false"
```

### 4) 요청 VTL — querystring → GetItem, mysecret* → 403
`req.vtl`:
```
#set($item = $input.params('item'))
#if($item.startsWith("mysecret"))
#set($context.responseOverride.status = 403)
{}
#else
{
  "TableName": "lab-inv",
  "Key": { "name": { "S": "$item" } }
}
#end
```
`$context.responseOverride.status` 로 상태코드를 강제 덮어쓴다 — gateway response 를 안 건드리고 403 을 낸다.

### 5) 통합 (type AWS, action GetItem)
```bash
# VTL 을 JSON 문자열로 안전하게 감싼다
python3 -c 'import json;print(json.dumps({"application/json":open("req.vtl").read()}))' > /tmp/req.json
aws apigateway put-integration --region $R --rest-api-id $API --resource-id $RES \
  --http-method GET --type AWS --integration-http-method POST \
  --uri "arn:aws:apigateway:$R:dynamodb:action/GetItem" \
  --credentials "$ROLE" \
  --request-templates file:///tmp/req.json
```
- **`--type AWS`** (not `AWS_PROXY` — 그건 Lambda proxy).
- **`--integration-http-method POST`** — AWS 서비스 호출은 무조건 POST. GET API 여도 백엔드는 POST.
- **URI 형식**: `arn:aws:apigateway:{region}:{service}:action/{Action}`.

### 6) 응답 VTL — value.N 만 raw 출력 (큰따옴표 없이)
```bash
aws apigateway put-method-response --region $R --rest-api-id $API --resource-id $RES \
  --http-method GET --status-code 200
python3 -c 'import json;print(json.dumps({"application/json":"#set($v = $input.path($'"'"'\$.Item.value.N'"'"')) \n$v"}))' > /tmp/res.json
# res.vtl 내용:  #set($v = $input.path('$.Item.value.N'))\n$v
aws apigateway put-integration-response --region $R --rest-api-id $API --resource-id $RES \
  --http-method GET --status-code 200 --response-templates file:///tmp/res.json
```
`$input.path('$.Item.value.N')` 로 값만 꺼내 그대로 출력 → `1000` (JSON `"1000"` 아님). 채점이 "큰따옴표 없이" 를 요구하는 지점.

### 7) 배포 + 검증
```bash
aws apigateway create-deployment --region $R --rest-api-id $API --stage-name v1
BASE="https://$API.execute-api.$R.amazonaws.com/v1/inventory"
curl -s "$BASE?item=balance"        # 1000
curl -s "$BASE?item=stock"          # 100
curl -s -o /dev/null -w '%{http_code}\n' "$BASE?item=mysecret123"   # 403
```

같은 방식으로 다른 AWS 서비스 직접통합 가능. 아래 A-2/A-3 는 실 API 로 확인됨.

### A-2. Step Functions StartExecution (Lambda 없이 워크플로우 트리거)

```bash
# role 에 states:StartExecution 필요
aws apigateway put-integration --region $R --rest-api-id $API --resource-id $RES \
  --http-method POST --type AWS --integration-http-method POST \
  --uri "arn:aws:apigateway:${R}:states:action/StartExecution" \
  --credentials "$ROLE" \
  --request-templates file:///tmp/sfn-req.json   # vtl/sfn-start-req.vtl
# stage variable 로 SM ARN 주입
aws apigateway create-deployment --region $R --rest-api-id $API --stage-name v1 \
  --variables stateMachineArn="$SMARN"
curl -s -X POST "https://${API}.execute-api.${R}.amazonaws.com/v1/run" -d '{"sales":5}'
# {"executionArn":"...","startDate":...}  ← 검증됨
```
`vtl/sfn-start-req.vtl` 이 body 를 `$util.escapeJavaScript($input.json('$'))` 로 SFN input(문자열)에 넣는다. **input 은 반드시 문자열** — JSON 객체로 주면 실패.

### A-3. SNS Publish

```bash
aws apigateway put-integration --region $R --rest-api-id $API --resource-id $RES \
  --http-method POST --type AWS --integration-http-method POST \
  --uri "arn:aws:apigateway:${R}:sns:action/Publish" \
  --credentials "$ROLE" \
  --request-templates file:///tmp/sns-req.json   # vtl/sns-publish-req.vtl
```
SNS 는 form-urlencoded 를 받으므로 `vtl/sns-publish-req.vtl` 이 `Action=Publish&TopicArn=...&Message=...` 형식으로 만든다. `$util.urlEncode` 필수.

---

## 케이스 B — Lambda proxy 통합 [검증됨: topics/rest-api 01 — POST→GET 왕복]

가장 흔한 기본형. Lambda 가 `{statusCode,headers,body}` 를 반환.

```bash
aws apigateway put-integration --region $R --rest-api-id $API --resource-id $RES \
  --http-method ANY --type AWS_PROXY --integration-http-method POST \
  --uri "arn:aws:apigateway:$R:lambda:path/2015-03-31/functions/arn:aws:lambda:$R:$ACCT:function:lab-fn/invocations"
aws lambda add-permission --region $R --function-name lab-fn \
  --statement-id apigw --action lambda:InvokeFunction \
  --principal apigateway.amazonaws.com \
  --source-arn "arn:aws:execute-api:$R:$ACCT:$API/*/*/*"
```
`AWS_PROXY` 는 매핑 템플릿이 없다 — 요청 전체가 Lambda 로 간다. **add-permission 을 빠뜨리면 502**. `source-arn` 의 `*/*/*` = stage/method/path.

## 케이스 C — HTTP API (v2, 더 저렴·빠름) [검증됨: topics/rest-api 02 — base64 body 함정 포함]

```bash
APIID=$(aws apigatewayv2 create-api --region $R --name lab-http --protocol-type HTTP \
  --target arn:aws:lambda:$R:$ACCT:function:lab-fn --query ApiId --output text)
```
`--target` 하나로 Lambda proxy + route + stage($default) + 통합을 자동 생성. **단 HTTP API 는 VTL 매핑 템플릿을 못 쓴다** — 케이스 A 같은 직접통합·변환이 필요하면 REST API 를 써야 한다.

## 케이스 D — Gateway Response 커스터마이즈

VTL responseOverride 말고, 인증 실패 등 API GW 레벨 응답을 바꿀 때.
```bash
aws apigateway put-gateway-response --region $R --rest-api-id $API \
  --response-type MISSING_AUTHENTICATION_TOKEN --status-code 404 \
  --response-templates '{"application/json":"{\"message\":\"not found\"}"}'
```
자주 쓰는 타입: `DEFAULT_4XX`, `DEFAULT_5XX`, `ACCESS_DENIED`, `UNAUTHORIZED`, `THROTTLED`.

## 케이스 E — endpoint 타입 / authorizer / CORS

```bash
# private (VPC 내부만) — endpoint-configuration
aws apigateway create-rest-api --region $R --name lab-priv \
  --endpoint-configuration types=PRIVATE
# regional (기본 edge 대신)
aws apigateway create-rest-api --region $R --name lab-reg \
  --endpoint-configuration types=REGIONAL

# Lambda authorizer (TOKEN)
aws apigateway create-authorizer --region $R --rest-api-id $API --name lab-auth \
  --type TOKEN --authorizer-uri "arn:aws:apigateway:$R:lambda:path/2015-03-31/functions/arn:aws:lambda:$R:$ACCT:function:authfn/invocations" \
  --identity-source "method.request.header.Authorization"

# IAM authorization (SigV4 서명 요청만)
aws apigateway put-method --region $R --rest-api-id $API --resource-id $RES \
  --http-method GET --authorization-type AWS_IAM
```

## 검증

```bash
aws apigateway get-rest-apis --region $R --query "items[?name=='lab-inv-api'].[id,name]" --output text
aws apigateway get-stages --region $R --rest-api-id $API --query 'item[].stageName' --output text
curl -s "https://$API.execute-api.$R.amazonaws.com/v1/inventory?item=balance"
```
채점이 하는 방식: `aws apigateway get-rest-apis --query items[].name` 로 이름 확인 → 도메인 조립 → curl.

## Terraform [검증됨: apply→curl(1000/100/403)→destroy]

`terraform-apigw/main.tf` — REST API + DynamoDB 직접통합(VTL) + 시드 + stage 를 한 스택으로. 2025 inventory 를 통째로 재현. CLI 로 리소스/메서드/통합/배포를 하나씩 거는 것보다 훨씬 안정적이다(순서·의존성 자동).

```bash
cd terraform-apigw
terraform init && terraform apply -auto-approve
URL=$(terraform output -raw url)
curl -s "$URL?item=balance"   # 1000
curl -s -o /dev/null -w '%{http_code}\n' "$URL?item=mysecret9"   # 403
terraform destroy -auto-approve
```
핵심 패턴:
```hcl
resource "aws_api_gateway_integration" "ddb" {
  type                    = "AWS"          # AWS_PROXY 아님(직접통합)
  integration_http_method = "POST"         # DDB 호출은 POST
  uri                     = "arn:aws:apigateway:${var.region}:dynamodb:action/GetItem"
  credentials             = aws_iam_role.agw.arn
  request_templates = { "application/json" = <<VTL
#set($item = $input.params('item'))
#if($item.startsWith("mysecret"))
#set($context.responseOverride.status = 403)
{}
#else
{ "TableName": "${aws_dynamodb_table.inv.name}", "Key": { "name": { "S": "$item" } } }
#end
VTL
  }
}
resource "aws_api_gateway_integration_response" "ok" {
  response_templates = { "application/json" = "$input.path('$.Item.value.N')" }  # raw 출력
  depends_on = [aws_api_gateway_integration.ddb]
}
```
- **v6 부터 stage 는 `aws_api_gateway_stage` 로 분리** — `aws_api_gateway_deployment` 의 `stage_name` 은 deprecated.
- **deployment `triggers`** 에 통합 해시를 넣어야 설정 변경 시 재배포된다. 없으면 옛 버전이 응답.
- `aws_dynamodb_table_item` 으로 시드까지 TF 안에서. (많은 데이터는 별도 스크립트)
- VTL 을 heredoc 으로 인라인 — `${...}` 는 TF 보간이라 DDB 테이블명 주입에 그대로 쓴다(VTL `$input` 은 `$` 라 충돌 없음).

## Console 팁

- **콘솔이 압도적으로 편한 곳**: REST API 는 리소스·메서드·통합·매핑템플릿·배포가 CLI 로 6~8단계인데, 콘솔은 "Create resource → Create method → Integration type 선택 → 매핑 템플릿 편집 → Deploy" 클릭 흐름이다. **VTL 편집기에 문법 힌트**가 있어 CLI 보다 실수가 준다.
- **Test 버튼**: 메서드 콘솔의 Test 로 배포 없이 통합·VTL 을 즉석 실행. `$input`/`$context` 값을 로그로 보여줘 매핑 디버깅이 빠르다.
- **Stages → SDK/Export**: OpenAPI 로 export/import 가능. 과제가 스펙을 주면 import.
- 대회 팁: **직접통합+VTL 은 콘솔로 만들고**, 완성 후 `get-export` 로 스펙을 뽑아 재현성 확보. 순수 CLI 는 매핑 템플릿 이스케이프가 지옥이다.

## 참고 문서

- REST API 개발자 가이드: https://docs.aws.amazon.com/apigateway/latest/developerguide/
- AWS service 통합(매핑 템플릿): https://docs.aws.amazon.com/apigateway/latest/developerguide/integrating-api-with-aws-services-dynamodb.html
- VTL 레퍼런스: https://docs.aws.amazon.com/apigateway/latest/developerguide/api-gateway-mapping-template-reference.html
- Terraform `aws_api_gateway_integration`: https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/api_gateway_integration
- Terraform v6 stage 마이그레이션: https://registry.terraform.io/providers/hashicorp/aws/latest/docs/guides/version-6-upgrade

## 함정

- **AWS 직접통합은 `--integration-http-method POST`** — GET API 여도 백엔드는 POST. 이거 틀리면 500.
- **`--type AWS` vs `AWS_PROXY`** — 직접통합/VTL 은 `AWS`, Lambda proxy 는 `AWS_PROXY`. 헷갈리면 매핑 템플릿이 무시된다.
- **배포를 다시 해야 반영**된다. put-integration 후 `create-deployment` 안 하면 옛 버전이 응답한다. 설정 바꾸고 curl 이 안 변하면 이것.
- **HTTP API 는 VTL 불가** — 변환/직접통합 필요하면 REST API.
- **Lambda proxy 502** — `add-permission` 누락 또는 Lambda 가 올바른 형식(`{statusCode,body}`)을 반환 안 함.
- **stage 이름**이 URL 경로에 들어간다(`/v1/inventory`). 과제지 지정 이름과 일치시켜라.
- **큰따옴표 없는 raw 출력**은 응답 VTL 에서 `$input.path(...)` 로 값만 뽑아야 한다. passthrough 면 DynamoDB JSON 이 그대로 나간다.

## 정리
```bash
aws apigateway delete-rest-api --region $R --rest-api-id $API
aws dynamodb delete-table --region $R --table-name lab-inv
aws iam delete-role-policy --role-name lab-apigw-ddb --policy-name ddb
aws iam delete-role --role-name lab-apigw-ddb
```
