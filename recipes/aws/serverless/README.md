# Serverless

Lambda·API Gateway·Step Functions·EventBridge·SQS/SNS. 2과제 Workflow / Message Queue / REST API Implement 모듈과 1과제 Lambda/Application 항목을 커버한다.

전부 실계정(`ap-northeast-2`)에서 배포·호출 검증했다. 검증 요약은 `../../../verify/RESULTS.md`.

## 카드

| 파일 | 다루는 것 |
|---|---|
| `lambda.md` + `lambda/` | 함수 생성·invoke·env·Function URL·ALB target·ESM·layer·VPC·동시성 + **코드 8종** |
| `apigateway.md` + `apigateway/vtl/` | REST/HTTP·통합 5종·**AWS 직접통합(DDB/SFN/SNS)**·**VTL 라이브러리 6종**·gateway response·authorizer |
| `stepfunctions/` | ASL 5종(inventory·choice/retry·map/parallel·distributed map·callback)·SDK 직접통합·데이터흐름 |
| `eventbridge.md` | Rule(패턴)·Scheduler(cron/rate)·Pipes(source→target)·custom bus |
| `sqs-sns.md` | DLQ redrive·FIFO·fan-out·filter policy |
| `scripts/deploy-lambda.sh` | zip 패키징+생성/갱신 멱등 배포 |

## Workflow 모듈 조립 (S3 → Lambda → DynamoDB + Step Functions)

2026 가이드 Workflow 모듈은 이 조합이다. 각 조각이 위 카드에 있다:

```
S3 (수집)  →  Lambda s3-event 핸들러 (처리)  →  DynamoDB (저장)
                        └ Step Functions 로 오케스트레이션 (stepfunctions/)
```

- 수집: S3 이벤트 알림 또는 EventBridge S3 이벤트 → `lambda/s3-event/`
- 처리: Lambda, 또는 Lambda 없이 SFN + SDK 직접통합
- 저장: DynamoDB (`../tier2/dynamodb.md` 참조 예정)
- 오케스트레이션: `stepfunctions/inventory-ddb.asl.json` 패턴

## "컴퓨팅 서비스 사용 불가" 제약 (2025 inventory 형)

Lambda·EC2·ECS 금지가 붙으면:
- API → DynamoDB: `apigateway.md` 케이스 A (AWS 직접통합 + VTL)
- API → Step Functions: `apigateway.md` A-2
- 워크플로우 내 서비스 호출: `stepfunctions/` SDK 직접통합 (`arn:aws:states:::aws-sdk:*`)
- 이벤트 라우팅: `eventbridge.md` Pipes (Lambda 없이 source→target)

제출 전 `bin/mark-self.sh --foul` 로 `aws lambda list-functions` 가 `[]` 인지 확인.

## zsh ARN 함정 (검증 환경 주의)

macOS zsh 에서 `"$VAR:영문자"` 는 변수 modifier 로 잘린다(`$ACCT:role`→`727ole`, `$R:states`→`2tates`). **`${VAR}:...` 중괄호로 감싸거나 ARN 을 조회로 받아라.** 현장 Windows PowerShell 은 무관.
