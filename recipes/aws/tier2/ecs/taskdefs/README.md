# ECS Task Definition 모음

과제가 요구하는 컨테이너 구성별 task definition JSON. **6종 전부 실제 `register-task-definition` 으로 검증됨.**
`EXEC_ROLE`/`TASK_ROLE`/`ACCT`/`FS_ID`/`AP_ID` 를 실제 값으로 치환 후:

```bash
aws ecs register-task-definition --region ap-northeast-2 --cli-input-json file://fargate-minimal.json
```

| 파일 | 구성 | 언제 |
|---|---|---|
| `fargate-minimal.json` | Fargate + awsvpc + awslogs | 기본. 단일 컨테이너 웹 |
| `healthcheck-deps.json` | healthCheck + dependsOn(HEALTHY) | 기동 순서 제어(DB 먼저 뜨고 앱) |
| `firelens-sidecar.json` | awsfirelens + Fluent Bit 사이드카 | 중앙집중 로깅(2025 logging 모듈) |
| `efs-volume.json` | EFS volume + access point + IAM | 공유 스토리지(File System security) |
| `secrets-injection.json` | secrets(SSM/Secrets Manager 주입) | 시크릿을 코드 밖에 |
| `ec2-bridge.json` | EC2 타입 + bridge + 동적 포트 | Fargate 아닌 EC2 런치, ALB 동적 매핑 |

## 핵심 구분

- **executionRoleArn**(ECS 가 사용: 이미지 pull·로그·secrets 읽기) vs **taskRoleArn**(컨테이너 앱이 사용: S3/DDB 등).
- **secrets 주입엔 executionRole** 에 `ssm:GetParameters`/`secretsmanager:GetSecretValue` + `kms:Decrypt`.
- **Fargate**: `networkMode=awsvpc`, cpu/memory 는 task 레벨 문자열(`"256"`). **EC2**: `bridge`/`host` 가능, cpu/memory 를 컨테이너 레벨 정수로도.
- **동적 포트 매핑**(`hostPort:0`)은 EC2 전용 — Fargate 는 각 task 가 ENI 라 불필요.

## 함정

- **firelens 는 log-router 사이드카가 essential** — 안 그러면 앱만 죽어도 로그 유실.
- **efsVolumeConfiguration.iam=ENABLED** 면 taskRole 에 `elasticfilesystem:ClientMount/ClientWrite` 필요.
- **dependsOn condition**: `START`/`COMPLETE`/`SUCCESS`/`HEALTHY`. HEALTHY 는 대상에 healthCheck 정의 필수.
- **secrets vs environment**: `environment` 는 평문(태스크 정의에 노출), `secrets` 는 런타임 주입(안전).
- cpu/memory 조합은 Fargate 가 허용하는 쌍만(256↔512/1024/2048 등). 틀리면 register 는 되나 run 에서 실패.

## 참고 문서

- Task definition 파라미터: https://docs.aws.amazon.com/AmazonECS/latest/developerguide/task_definition_parameters.html
- FireLens: https://docs.aws.amazon.com/AmazonECS/latest/developerguide/using_firelens.html
- 시크릿 주입: https://docs.aws.amazon.com/AmazonECS/latest/developerguide/specifying-sensitive-data.html
