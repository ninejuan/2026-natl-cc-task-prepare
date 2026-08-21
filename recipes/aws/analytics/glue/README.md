# Glue (Crawler · ETL)

**트리거 문구** — "스키마 자동 발견", "ETL", "데이터 변환", "카탈로그", "JSON → Parquet".

**전제**
```bash
export R=ap-northeast-2 ACCT=$(aws sts get-caller-identity --query Account --output text)
BUCKET=lab-analytics-$ACCT
```

Crawler(스키마 자동 발견 → 카탈로그)와 ETL Job(Spark 변환)은 별개다. Athena 와 카탈로그(Glue Data Catalog)를 공유한다.

---

## 공통 role

```bash
cat > glue-trust.json <<'JSON'
{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":"glue.amazonaws.com"},"Action":"sts:AssumeRole"}]}
JSON
aws iam create-role --role-name lab-glue-role --assume-role-policy-document file://glue-trust.json
aws iam attach-role-policy --role-name lab-glue-role \
  --policy-arn arn:aws:iam::aws:policy/service-role/AWSGlueServiceRole
# + 대상 S3 버킷 권한 (Get/Put/List)
sleep 10
GLUEROLE=$(aws iam get-role --role-name lab-glue-role --query Role.Arn --output text)
```

## ★ 케이스 A — Crawler (스키마 자동 발견) [검증됨]

S3 데이터를 스캔해 컬럼·타입·파티션을 자동으로 카탈로그에 등록. Athena 가 바로 쿼리.

```bash
aws glue create-crawler --region $R --name lab-crawler --role "$GLUEROLE" \
  --database-name lab_db \
  --targets "{\"S3Targets\":[{\"Path\":\"s3://$BUCKET/events/\"}]}"
aws glue start-crawler --region $R --name lab-crawler

# READY 될 때까지 (1~3분)
aws glue get-crawler --region $R --name lab-crawler --query 'Crawler.State' --output text
aws glue get-crawler --region $R --name lab-crawler --query 'Crawler.LastCrawl.Status' --output text  # SUCCEEDED

# 자동 생성된 테이블 + 스키마
aws glue get-tables --region $R --database-name lab_db --query 'TableList[].Name' --output text
aws glue get-table --region $R --database-name lab_db --name <table> \
  --query 'Table.StorageDescriptor.Columns[].[Name,Type]' --output text
```
- **테이블 이름은 S3 경로 끝 폴더명** 기반(`events/` → `events` 또는 해시 붙은 이름).
- `dt=.../` 형식 경로면 **파티션 컬럼 자동 인식**.
- 스케줄 실행: `--schedule "cron(0 * * * ? *)"`.
- 재크롤 정책: 새 파일만 볼지 전체 볼지 `RecrawlPolicy`.

## 케이스 B — ETL Job (JSON → Parquet) [검증됨: Glue 4.0 job SUCCEEDED → event_type 파티션 parquet]

`etl_json_to_parquet.py`(변환·Parquet) 또는 `etl_aggregate_join.py`(집계+조인+DQ, Spark SQL) 참조. S3 JSON 을 읽어 타입 정리 후 Parquet(dt 파티션)로 저장.

```bash
# 스크립트를 S3 에 업로드
aws s3 cp etl_json_to_parquet.py s3://$BUCKET/scripts/etl.py

aws glue create-job --region $R --name lab-etl \
  --role "$GLUEROLE" \
  --command "Name=glueetl,ScriptLocation=s3://$BUCKET/scripts/etl.py,PythonVersion=3" \
  --glue-version "4.0" \
  --number-of-workers 2 --worker-type G.1X \
  --default-arguments "{\"--SRC\":\"s3://$BUCKET/events/\",\"--DST\":\"s3://$BUCKET/parquet/\"}"

RUN=$(aws glue start-job-run --region $R --job-name lab-etl --query JobRunId --output text)
# 완료 대기 (2~3분, worker 프로비저닝 포함)
aws glue get-job-run --region $R --job-name lab-etl --run-id "$RUN" \
  --query 'JobRun.JobRunState' --output text   # RUNNING -> SUCCEEDED
```
- **G.1X worker 2개**가 대회 규모 최소. 프로비저닝에 1~2분.
- `DynamicFrame` 은 스키마가 들쭉날쭉해도 견딘다(Spark DataFrame 보다 유연).
- **비용 주의**: DPU-시간 과금. 작은 데이터면 worker 2개로 제한.
- Visual ETL(콘솔)로 만든 것도 스크립트로 저장된다.

## 케이스 C — Workflow (Crawler → Job 오케스트레이션) [검증됨: 2 액션 전부 SUCCEEDED, 크롤러가 파티션키 인식]

```bash
aws glue create-workflow --region $R --name lab-wf
# trigger: crawler 완료 -> job 시작 (ON_DEMAND / SCHEDULED / CONDITIONAL)
```
Glue 자체 워크플로우. 단, 복잡하면 Step Functions(`../../serverless/stepfunctions/`)의 `glue:startJobRun.sync` 가 더 유연.

## 검증

```bash
aws glue get-crawler --region $R --name lab-crawler --query 'Crawler.[State,LastCrawl.Status]' --output text
aws glue get-tables --region $R --database-name lab_db --query 'TableList[].Name' --output text
aws glue get-job-run --region $R --job-name lab-etl --run-id "$RUN" --query 'JobRun.[JobRunState,ExecutionTime]' --output text
# ETL 결과 확인
aws s3 ls s3://$BUCKET/parquet/ --recursive
```

## Terraform [validate 통과]

```hcl
resource "aws_glue_catalog_database" "db" { name = "lab_db" }
resource "aws_glue_crawler" "c" {
  name          = "lab-crawler"
  role          = aws_iam_role.glue.arn
  database_name = aws_glue_catalog_database.db.name
  s3_target { path = "s3://bucket/events/" }
  # schedule = "cron(0 * * * ? *)"  # 주기 실행
}
resource "aws_glue_job" "j" {
  name         = "lab-job"
  role_arn     = aws_iam_role.glue.arn
  glue_version = "4.0"
  command {
    script_location = "s3://bucket/scripts/etl.py"
    python_version  = "3"
  }
  number_of_workers = 2
  worker_type       = "G.1X"
  default_arguments = { "--SRC" = "s3://bucket/events/", "--DST" = "s3://bucket/parquet/" }
}
```
crawler·job 은 CLI 로 실검증(위). TF 는 스택 관리용. 스크립트는 `aws_s3_object` 로 함께 올린다.

## Console 팁

- **Glue Studio(Visual ETL)**: 노드(source→transform→target)를 드래그로 연결하면 PySpark 스크립트 자동 생성. 조인·집계·필터를 코드 없이. 생성된 스크립트를 `etl_*.py` 로 저장해 재현.
- **크롤러 실행·스키마 확인**: 콘솔에서 crawler Run → 생성된 테이블 스키마를 즉시 확인. 해시 붙은 테이블명도 UI 에서 바로 보임.
- **Job 실행 모니터링**: Run 탭에서 각 실행의 DPU·시간·에러. CloudWatch 로그 링크.
- **Data Quality**: Studio 에서 DQ 규칙(룰셋)을 UI 로 추가.

## 참고 문서

- Glue 개발자 가이드: https://docs.aws.amazon.com/glue/latest/dg/
- 크롤러: https://docs.aws.amazon.com/glue/latest/dg/add-crawler.html
- Glue Studio: https://docs.aws.amazon.com/glue/latest/ug/
- Terraform `aws_glue_crawler`: https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/glue_crawler
- Terraform `aws_glue_job`: https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/glue_job

## 함정

- **crawler 는 시간이 걸린다**(1~3분). 채점 대기와 안 맞으면 미리 돌려 카탈로그를 채워둬라.
- **ETL job 첫 실행은 worker 프로비저닝** 때문에 느리다(1~2분 추가).
- **테이블 이름 예측 어려움** — crawler 가 해시를 붙일 수 있다. `get-tables` 로 확인 후 Athena 쿼리.
- **role 에 S3 버킷 권한** 별도 필요(AWSGlueServiceRole 만으론 대상 버킷 접근 불가).
- **Glue 버전**: 4.0/5.0. `--glue-version` 명시. 라이브러리 호환 주의.
- crawler DB = Athena DB. 지울 때 `DROP DATABASE ... CASCADE` 로 테이블까지.

## 정리
```bash
aws glue delete-crawler --region $R --name lab-crawler
aws glue delete-job --region $R --job-name lab-etl
aws iam detach-role-policy --role-name lab-glue-role --policy-arn arn:aws:iam::aws:policy/service-role/AWSGlueServiceRole
aws iam delete-role-policy --role-name lab-glue-role --policy-name s3
aws iam delete-role --role-name lab-glue-role
```
