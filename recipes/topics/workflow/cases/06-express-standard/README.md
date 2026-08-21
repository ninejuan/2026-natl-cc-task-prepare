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
