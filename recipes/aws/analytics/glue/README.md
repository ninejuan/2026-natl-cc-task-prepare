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

## 케이스 B — ETL Job (JSON → Parquet)

`etl_json_to_parquet.py` 참조. S3 JSON 을 읽어 타입 정리 후 Parquet(dt 파티션)로 저장.

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

## 케이스 C — Workflow (Crawler → Job 오케스트레이션)

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
