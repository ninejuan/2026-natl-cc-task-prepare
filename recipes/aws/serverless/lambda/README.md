# Lambda 코드 라이브러리

바로 배포되는 Python 핸들러 모음. 배포는 `../scripts/deploy-lambda.sh`.
카드(개념·CLI·함정)는 `../lambda.md`.

```bash
../scripts/deploy-lambda.sh <함수명> <디렉토리> [핸들러] [리전]
# 예: ../scripts/deploy-lambda.sh book-fn ./crud-booking
```
전부 핸들러가 `handler.handler` (파일 `handler.py` 의 `handler` 함수).

## 핸들러 목록

| 디렉토리 | 무엇 | 트리거 문구 | 검증 |
|---|---|---|---|
| `crud-booking/` | POST 저장 + GET 조회(booking_id/client_id GSI). **API GW·ALB·Function URL 3형식 자동 파싱** + 필드검증 | "예약 정보 POST", "저장한 데이터 조회", "REST API 구현" | ✅ 실배포·GSI 2건 확인 |
| `dynamodb-scan-api/` | 조회 전용. optional 필터(email/concert_name) → FilterExpression. GSI 우선, 없으면 scan | "GET 호출 API", "optional field 검색" | 구문 |
| `alb-response/` | ALB target 전용 응답형(`statusDescription` 필수) | "ALB 뒤 Lambda", "CloudFront→ALB→Lambda" | 구문 |
| `sqs-batch/` | SQS ESM 소비 + **ReportBatchItemFailures**(실패분만 재시도) | "메시지 큐 처리", "Spike 트래픽" | ✅ 실ESM·partial failure 확인 |
| `s3-event/` | S3 업로드 → 객체 읽기 → DynamoDB (S3 알림·EventBridge 양쪽) | "Workflow 수집 단계", "S3 이벤트" | 구문 |
| `ddb-stream/` | DynamoDB Streams(INSERT/MODIFY/REMOVE) 후처리·집계 | "변경 감지", "스트림" | ✅ _deser 단위테스트 |
| `kinesis-consumer/` | Kinesis 레코드 base64 디코딩 + 집계 | "실시간 분석 소비", "스트리밍" | 구문 |
| `image-resize/` | S3 이미지 → 썸네일 (Pillow). 무한루프 방지 | "이미지 리사이징", "CDN 엣지 처리" | 구문 |

## 공통 규약

- **이벤트 파싱**: `crud-booking` 의 `_parse()` 가 API GW proxy(`httpMethod`)·ALB(`requestContext.http`)·Function URL(`rawPath`)을 통일해 처리. 어느 앞단이든 같은 핸들러가 동작한다.
- **응답**: `{statusCode, headers, body(문자열)}`. ALB 는 `statusDescription` 도 필요(`alb-response`).
- **입력 검증**: 신뢰 경계다. `crud-booking` 이 필수 필드·이메일 형식을 400 으로 막는다 — 채점 데이터가 깨지지 않게.
- **의존성**: 순수 boto3 는 런타임 내장이라 zip 만. Pillow 등 네이티브 확장은 `requirements.txt` 를 두면 `deploy-lambda.sh` 가 함께 패키징하지만, **로컬 OS 와 Lambda 아키텍처가 다르면 실패** — 그땐 컨테이너 이미지 배포나 AWS 제공 layer.

## requirements.txt 예 (image-resize)

```
Pillow==11.0.0
```
`deploy-lambda.sh` 가 `pip install -t` 로 함께 싼다. x86_64 manylinux wheel 이 필요하면:
```bash
pip install --platform manylinux2014_x86_64 --only-binary=:all: -t ./pkg Pillow
```
