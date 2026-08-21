# Express vs Standard State Machine

`create-state-machine --type` 로 결정. ASL 은 동일, 실행 특성만 다르다.

| | STANDARD (기본) | EXPRESS |
|---|---|---|
| 최대 실행시간 | 1년 | 5분 |
| 실행이력 | 콘솔/`describe-execution` 조회 가능 | 없음(CloudWatch Logs 로만) |
| 과금 | 상태전이 수 | 실행수+시간+메모리 |
| 멱등/at-least-once | Exactly-once | At-least-once(Express async) |
| 용도 | 장기 워크플로, 사람 개입, 감사 | 고빈도 단기 이벤트 처리(스트리밍/IoT) |

```bash
# Standard (이력 조회 필요 — 채점이 execution 이력 보면 이걸로)
aws stepfunctions create-state-machine --name lab-std --type STANDARD --definition file://wf.json --role-arn <role>
# Express (로깅 설정 권장)
aws stepfunctions create-state-machine --name lab-exp --type EXPRESS --definition file://wf.json --role-arn <role> \
  --logging-configuration '{"level":"ALL","includeExecutionData":true,"destinations":[{"cloudWatchLogsLogGroup":{"logGroupArn":"<lg-arn>:*"}}]}'
```

★ **채점이 `describe-execution`/실행이력을 확인하면 반드시 STANDARD.** Express 는 이력이 없어 관찰 불가.

## 실검증 (us-west-2, `verify.sh` — 동일 ASL 을 두 타입으로 생성→실행→정리)

`bash verify.sh` 한 방에 role/log group/SM 2종 생성 → 실행 → teardown 까지 간다. 실측 결과:

| 관찰 | STANDARD (`lab-std`) | EXPRESS (`lab-exp`) |
|---|---|---|
| 실행 시작 | `start-execution` → executionArn | `start-sync-execution` → **결과가 응답에 바로** |
| `describe-execution` | `SUCCEEDED {"at":...,"ok":"s-1"}` | (async 실행은 arn 없음) |
| `list-executions` | `run1 SUCCEEDED` | ❌ **`StateMachineTypeNotSupported`** — API 자체가 거부 |
| 이력 위치 | Step Functions 실행이력 | CloudWatch Logs 만 (`ExecutionStarted`→`PassStateEntered`→`PassStateExited`→`ExecutionSucceeded` 이벤트 실측) |

- **★ Express 는 `list-executions` 가 에러**(`This operation is not supported by this type of state machine`)다. "이력이 비어 있다"가 아니라 **API 가 아예 지원 안 함** — 채점 스크립트가 실행이력을 보면 EXPRESS 는 0점.
- Express 로깅은 **role 에 `logs:CreateLogDelivery`/`PutResourcePolicy` 등 8종**이 필요(`verify.sh` 의 `sfn-logs.json`). 없으면 create-state-machine 이 실패한다.
- 로그그룹 ARN 은 끝에 **`:*`** 를 붙인다(`arn:aws:logs:$R:$A:log-group:/aws/vendedlogs/states/lab-exp:*`).
- Express 로그가 CW 에 뜨기까지 **~20초** 지연(실측) — 바로 조회하면 비어 있다.
