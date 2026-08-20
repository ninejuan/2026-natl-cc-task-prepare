# FireLens → S3 아카이브

`containerdef-s3.json` — 02-firelens-cw 와 VPC/역할/클러스터는 동일하고, app 컨테이너의
`logConfiguration.options` 만 Fluent Bit **S3 output** 플러그인으로 바꾼 것.

- `Name: s3`, `bucket`, `total_file_size`/`upload_timeout`(버퍼 후 업로드), `s3_key_format`(파티션 경로).
- **task role 에 `s3:PutObject`** (대상 버킷) 필요 — 없으면 로그 유실.
- `ACCT` 를 계정 ID 로 치환. 컨테이너 정의는 순수 JSON(주석키 없음) → `register-task-definition --container-definitions file://containerdef-s3.json` 그대로 사용.

기반: 02-firelens-cw(CloudWatch 경로, live 검증됨) — VPC/ECS/역할 셋업은 그 setup.sh 재사용, output options 만 위로 교체.
