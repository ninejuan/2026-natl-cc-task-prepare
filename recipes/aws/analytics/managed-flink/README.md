# Managed Service for Apache Flink (Studio)

**트리거 문구** — "실시간 데이터 분석 환경", "Managed Service for Apache Flink", "Notebook 에서 SQL", "Flink 애플리케이션 프로그래밍은 금지".

**전제**
```bash
export R=ap-northeast-2 ACCT=$(aws sts get-caller-identity --query Account --output text)
```
> ⚠️ ARN 조립은 `${R}:${ACCT}:...` 중괄호로. (zsh modifier 함정)

**가이드 제약**: "Flink 애플리케이션을 프로그래밍하는 형태는 금지, Notebook 에서 SQL 로". → **Studio(Zeppelin) + SQL** 만. JAR 앱 배포 형태(`FLINK-1_x` + INTERACTIVE=no)는 이 제약에 걸린다.

`notebook-kinesis-windows.sql` 이 노트북 SQL 예제(소스 정의·TUMBLE/HOP/SESSION 윈도우·S3 싱크). 문단마다 `%flink.ssql`.

---

## Studio 앱 생성 [검증됨: RUNNING 확인]

```bash
# 1) role: Glue(메타스토어)·S3·Kinesis·logs 접근
cat > flink-trust.json <<'JSON'
{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":"kinesisanalytics.amazonaws.com"},"Action":"sts:AssumeRole"}]}
JSON
aws iam create-role --role-name lab-flink-role --assume-role-policy-document file://flink-trust.json
# 최소권한 원칙 요구 시 glue/s3/kinesis 를 리소스 단위로 좁혀라. 아래는 검증용 광범위.
cat > flink-perm.json <<'JSON'
{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Action":["glue:*","s3:*","kinesis:*","logs:*","cloudwatch:*"],"Resource":"*"}]}
JSON
aws iam put-role-policy --role-name lab-flink-role --policy-name p --policy-document file://flink-perm.json
sleep 10
FROLE=$(aws iam get-role --role-name lab-flink-role --query Role.Arn --output text)

# 2) Studio 는 Glue database 를 메타스토어로 쓴다 (필수)
aws glue create-database --region $R --database-input '{"Name":"lab_flink_db"}'

# 3) Studio 앱 (INTERACTIVE + ZEPPELIN-FLINK)
cat > app.json <<JSON
{
  "ApplicationName": "lab-flink-studio",
  "RuntimeEnvironment": "ZEPPELIN-FLINK-3_0",
  "ApplicationMode": "INTERACTIVE",
  "ServiceExecutionRole": "$FROLE",
  "ApplicationConfiguration": {
    "FlinkApplicationConfiguration": {"ParallelismConfiguration": {"ConfigurationType": "CUSTOM", "Parallelism": 1, "ParallelismPerKPU": 1}},
    "ZeppelinApplicationConfiguration": {
      "CatalogConfiguration": {"GlueDataCatalogConfiguration": {"DatabaseARN": "arn:aws:glue:${R}:${ACCT}:database/lab_flink_db"}}
    }
  }
}
JSON
aws kinesisanalyticsv2 create-application --region $R --cli-input-json file://app.json

# 4) 시작 (STARTING → RUNNING, 수 분)
aws kinesisanalyticsv2 start-application --region $R --application-name lab-flink-studio
aws kinesisanalyticsv2 describe-application --region $R --application-name lab-flink-studio \
  --query 'ApplicationDetail.ApplicationStatus' --output text   # RUNNING
```

## SQL 노트북 작성

RUNNING 되면 **콘솔에서 "Open in Apache Zeppelin"** → 노트북에 `notebook-kinesis-windows.sql` 의 문단을 붙여 실행. CLI 로 SQL 직접 실행은 없다(Zeppelin UI 기반).

SQL 노트북 예제:
- `notebook-kinesis-windows.sql` — Kinesis 소스 + TUMBLE/HOP/SESSION 윈도우 + S3 싱크
- `notebook-msk-source.sql` — MSK(Kafka) 소스, Kafka→Kafka, 실시간 매출 집계
- `notebook-topn-join.sql` — 윈도우 Top-N, 차원 조인, 인터벌 조인
- `notebook-anomaly-s3sink.sql` — 급증/임계 이상탐지, Parquet 파티션 싱크

핵심 SQL 패턴 (`notebook-kinesis-windows.sql` 참조):
- **소스 테이블**: `CREATE TABLE ... WITH ('connector'='kinesis', ...)` + `WATERMARK`
- **TUMBLE**: 겹치지 않는 고정 창. `TABLE(TUMBLE(TABLE t, DESCRIPTOR(event_time), INTERVAL '1' MINUTE))`
- **HOP**: 슬라이딩(겹치는) 창. slide + size 두 인자
- **SESSION**: 비활동 간격 기준. `SESSION(event_time, INTERVAL '30' SECOND)`
- **싱크**: `CREATE TABLE ... WITH ('connector'='filesystem','path'='s3://.../','format'='json')` + `INSERT INTO`

## 검증

```bash
aws kinesisanalyticsv2 describe-application --region $R --application-name lab-flink-studio \
  --query 'ApplicationDetail.[ApplicationStatus,RuntimeEnvironment,ApplicationConfigurationDescription.ZeppelinApplicationConfigurationDescription.CatalogConfigurationDescription.GlueDataCatalogConfigurationDescription.DatabaseARN]' --output text
# RUNNING  ZEPPELIN-FLINK-3_0  arn:aws:glue:...:database/lab_flink_db
```
채점은 보통 노트북에서 쿼리 결과가 나오는지 + 싱크(S3)에 데이터가 쌓이는지 본다.

## Terraform

```hcl
resource "aws_kinesisanalyticsv2_application" "studio" {
  name                   = "lab-flink-studio"
  runtime_environment    = "ZEPPELIN-FLINK-3_0"
  application_mode       = "INTERACTIVE"
  service_execution_role = aws_iam_role.flink.arn
  application_configuration {
    flink_application_configuration {
      parallelism_configuration {
        configuration_type = "CUSTOM"
        parallelism        = 1
        parallelism_per_kpu = 1
      }
    }
    # zeppelin + Glue 카탈로그는 리소스 스키마가 길다 — 콘솔/CLI 가 실용적.
  }
}
```
Studio 는 노트북 SQL 을 콘솔(Zeppelin UI)에서 작성하므로 TF 로 앱만 만들고 SQL 은 UI. 대회에선 CLI(README 상단) 또는 콘솔이 낫다.

## Console 팁

- **Studio 노트북 = 콘솔 필수**: "Open in Apache Zeppelin" → 문단에 `%flink.ssql` 로 SQL 붙여 실행. CLI 로 SQL 실행 불가. `notebook-*.sql` 을 문단별로 복붙.
- **결과 시각화**: Zeppelin 이 SELECT 결과를 표·차트로. 윈도우 집계가 실시간 갱신되는 걸 눈으로.
- **Deploy as application**: 노트북을 상시 실행 앱으로 승격(INTERACTIVE→streaming). 단 가이드가 "노트북 SQL" 을 요구하면 노트북 그대로.
- **소스/싱크 커넥터**: Studio 에 Kinesis/MSK/S3 커넥터 JAR 이 기본 포함. 추가 커넥터는 S3 에서 로드.

## 참고 문서

- Managed Flink: https://docs.aws.amazon.com/managed-flink/latest/java/
- Studio 노트북: https://docs.aws.amazon.com/managed-flink/latest/java/how-notebook.html
- Flink SQL 윈도우: https://nightlies.apache.org/flink/flink-docs-stable/docs/dev/table/sql/queries/window-tvf/
- Terraform `aws_kinesisanalyticsv2_application`: https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/kinesisanalyticsv2_application

## 함정

- **INTERACTIVE 모드 + ZEPPELIN 런타임** 이어야 노트북 SQL 이다. `FLINK-1_x` 는 JAR 배포용(가이드 금지).
- **Glue database 필수** — 메타스토어. 없으면 create-application 실패.
- **KPU 과금** — RUNNING 동안 시간당. 검증 후 즉시 stop+delete. Serverless 아님(항상 실행).
- **워터마크 없으면 윈도우가 안 닫힌다** — 소스 테이블에 `WATERMARK FOR` 필수.
- **`event_time` 은 TIMESTAMP(3)** — Kinesis JSON 의 시각 필드를 이 타입으로. 형식 안 맞으면 파싱 실패.
- **RUNNING 까지 수 분** — 채점 대기 고려. 미리 띄워둔다.
- **delete 는 create-timestamp 필요** — `describe` 로 받아서 넘긴다.

## 정리
```bash
aws kinesisanalyticsv2 stop-application --region $R --application-name lab-flink-studio --force
CT=$(aws kinesisanalyticsv2 describe-application --region $R --application-name lab-flink-studio --query 'ApplicationDetail.CreateTimestamp' --output text)
aws kinesisanalyticsv2 delete-application --region $R --application-name lab-flink-studio --create-timestamp "$CT"
aws glue delete-database --region $R --name lab_flink_db
aws iam delete-role-policy --role-name lab-flink-role --policy-name p; aws iam delete-role --role-name lab-flink-role
```
