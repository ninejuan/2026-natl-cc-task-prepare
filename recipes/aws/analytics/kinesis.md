# Kinesis (Data Streams · Firehose)

**트리거 문구** — "실시간 데이터", "스트리밍 수집", "로그를 S3/OpenSearch 로", "클릭스트림", "실시간 분석 환경".

**전제**
```bash
export R=ap-northeast-2 ACCT=$(aws sts get-caller-identity --query Account --output text)
```
> ⚠️ ARN 조립 시 `${R}:...` 중괄호 또는 조회로. (zsh modifier 함정)

> **코드**: `kinesis/producer.py`(put_records 배치 발행, 실검증), `kinesis/transform-lambda.py`(Firehose 변환), `kinesis/firehose-parquet-conf.json`(JSON→Parquet 변환 설정).

Data Streams(샤드 기반 스트림)와 Firehose(→S3/OpenSearch 배달)는 다른 서비스다. **실시간 분석 파이프라인은 보통 둘을 잇는다.**

---

## 케이스 A — Data Streams

```bash
# on-demand (샤드 관리 불필요, 대회 권장). provisioned 는 --shard-count N
aws kinesis create-stream --region $R --stream-name lab-stream \
  --stream-mode-details StreamMode=ON_DEMAND
aws kinesis wait stream-exists --region $R --stream-name lab-stream

# 발행
aws kinesis put-record --region $R --stream-name lab-stream \
  --partition-key "p1" --data "$(echo '{"event_type":"click","dt":"2026-08-20"}' | base64)"

# 소비 (샤드 이터레이터)
SHARD=$(aws kinesis list-shards --region $R --stream-name lab-stream --query 'Shards[0].ShardId' --output text)
IT=$(aws kinesis get-shard-iterator --region $R --stream-name lab-stream \
  --shard-id $SHARD --shard-iterator-type TRIM_HORIZON --query ShardIterator --output text)
aws kinesis get-records --region $R --shard-iterator "$IT" --query 'Records[].Data' --output text | base64 -d
```
- **데이터는 base64** 로 넣고 받는다.
- Lambda 소비는 `../serverless/lambda/kinesis-consumer/` + ESM(`--starting-position LATEST`).
- **enhanced fan-out**(전용 처리량): `register-stream-consumer`. 여러 소비자가 경합 없이.
- resharding: on-demand 면 자동. provisioned 는 `update-shard-count`.

## ★ 케이스 B — Firehose → S3 (동적 파티셔닝) [검증됨]

Kinesis → Firehose → S3, `dt` 값으로 파티션 경로 생성. 클릭스트림 적재 전형.

```bash
BUCKET=lab-analytics-$ACCT
aws s3api create-bucket --region $R --bucket $BUCKET \
  --create-bucket-configuration LocationConstraint=$R

# Firehose role: S3 쓰기 + Kinesis 읽기
cat > fh-trust.json <<'JSON'
{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":"firehose.amazonaws.com"},"Action":"sts:AssumeRole"}]}
JSON
aws iam create-role --role-name lab-fh-role --assume-role-policy-document file://fh-trust.json
cat > fh-perm.json <<JSON
{"Version":"2012-10-17","Statement":[
 {"Effect":"Allow","Action":["s3:PutObject","s3:GetBucketLocation","s3:ListBucket","s3:AbortMultipartUpload"],"Resource":["arn:aws:s3:::$BUCKET","arn:aws:s3:::$BUCKET/*"]},
 {"Effect":"Allow","Action":["kinesis:DescribeStream","kinesis:GetShardIterator","kinesis:GetRecords","kinesis:ListShards"],"Resource":"*"}]}
JSON
aws iam put-role-policy --role-name lab-fh-role --policy-name p --policy-document file://fh-perm.json
sleep 10
FHROLE=$(aws iam get-role --role-name lab-fh-role --query Role.Arn --output text)
STREAMARN=$(aws kinesis describe-stream-summary --region $R --stream-name lab-stream --query 'StreamDescriptionSummary.StreamARN' --output text)
```

S3 설정(`s3conf.json`) — **키 이름은 `DynamicPartitioningConfiguration`** (`DynamicPartitioning` 아님):
```json
{
  "RoleARN": "<FHROLE>",
  "BucketARN": "arn:aws:s3:::<BUCKET>",
  "Prefix": "events/dt=!{partitionKeyFromQuery:dt}/",
  "ErrorOutputPrefix": "errors/",
  "BufferingHints": {"SizeInMBs": 64, "IntervalInSeconds": 60},
  "DynamicPartitioningConfiguration": {"Enabled": true},
  "ProcessingConfiguration": {
    "Enabled": true,
    "Processors": [{"Type": "MetadataExtraction", "Parameters": [
      {"ParameterName": "MetadataExtractionQuery", "ParameterValue": "{dt:.dt}"},
      {"ParameterName": "JsonParsingEngine", "ParameterValue": "JQ-1.6"}
    ]}]
  }
}
```
```bash
echo "{\"RoleARN\":\"$FHROLE\",\"KinesisStreamARN\":\"$STREAMARN\"}" > fh.json
aws firehose create-delivery-stream --region $R --delivery-stream-name lab-firehose \
  --delivery-stream-type KinesisStreamAsSource \
  --kinesis-stream-source-configuration file://fh.json \
  --extended-s3-destination-configuration file://s3conf.json
# ACTIVE 대기 후 Kinesis 로 발행 → 60초 버퍼 후 S3 에 events/dt=.../ 로 적재
aws s3 ls s3://$BUCKET/events/ --recursive
```
- **`!{partitionKeyFromQuery:dt}`** 가 MetadataExtraction 으로 뽑은 `dt` 를 경로에 넣는다.
- **JSON→Parquet 변환**: `DataFormatConversionConfiguration` 에 Glue 테이블 스키마 지정. 컬럼형이라 Athena 스캔이 훨씬 싸다.
- **버퍼**: `IntervalInSeconds` 최소 60(동적 파티셔닝 시). 채점 대기와 안 맞으면 직접 발행 후 기다려야 한다 — **Firehose 는 즉시 안 나온다**.

## 케이스 C — Firehose → OpenSearch

```bash
# --opensearch-destination-configuration 로 대상 변경. 로그 검색 파이프라인.
# DomainARN, IndexName, RoleARN(es:* 권한), S3 backup 설정.
```
로그 분석(2025 logging 모듈)에서 ECS/앱 로그 → Firehose → OpenSearch → Dashboards.

## 검증

```bash
aws kinesis describe-stream-summary --region $R --stream-name lab-stream \
  --query 'StreamDescriptionSummary.[StreamName,StreamStatus,OpenShardCount]' --output text
aws firehose describe-delivery-stream --region $R --delivery-stream-name lab-firehose \
  --query 'DeliveryStreamDescription.[DeliveryStreamStatus,Destinations[0].ExtendedS3DestinationDescription.Prefix]' --output text
aws s3 ls s3://$BUCKET/events/ --recursive    # 적재 확인
```

## Terraform [검증됨: 전 구간 apply→발행→Athena click 5→destroy]

`terraform-pipeline/main.tf` — Kinesis→Firehose(동적 파티셔닝)→S3 + Athena workgroup/DB 를 한 스택으로. CLI 로 role·정책·Firehose JSON 을 조립하는 것보다 훨씬 안정적. **`analytics/` 최고의 시작점**(파이프라인 전체를 한 번에).

```bash
cd terraform-pipeline
terraform init && terraform apply -auto-approve
STREAM=$(terraform output -raw stream)
for i in 1 2 3; do aws kinesis put-record --region ap-northeast-2 --stream-name $STREAM \
  --partition-key p$i --data "$(echo '{"event_type":"click","dt":"2026-08-20"}'|base64)"; done
# 60초 버퍼 후 s3 + athena (README athena.md)
terraform destroy -auto-approve
```
핵심 패턴:
```hcl
resource "aws_kinesis_firehose_delivery_stream" "fh" {
  destination = "extended_s3"
  kinesis_source_configuration { kinesis_stream_arn = ..., role_arn = ... }
  extended_s3_configuration {
    buffering_interval = 60
    prefix             = "events/dt=!{partitionKeyFromQuery:dt}/"
    dynamic_partitioning_configuration { enabled = "true" }
    processing_configuration {
      enabled = "true"
      processors {
        type = "MetadataExtraction"
        parameters { parameter_name = "JsonParsingEngine"      parameter_value = "JQ-1.6" }
        parameters { parameter_name = "MetadataExtractionQuery" parameter_value = "{dt:.dt}" }
      }
    }
  }
}
```
- **CLI 의 `DynamicPartitioningConfiguration` 키명 함정이 TF 엔 없다** — `dynamic_partitioning_configuration` 블록.
- Parquet 변환: `data_format_conversion_configuration` 블록(Glue 테이블 스키마 참조).
- Lambda 변환: `processors { type = "Lambda" ... LambdaArn }`.

## Console 팁

- **Firehose 생성 마법사**: source(Kinesis/Direct PUT)·destination·동적 파티셔닝·변환을 단계 폼으로. JQ 쿼리·prefix 를 예제와 함께 보여줘 CLI JSON 조립보다 안전.
- **Test with demo data**: Firehose 콘솔이 샘플 데이터를 발행해 S3 도착까지 테스트해준다.
- **Kinesis 모니터링**: 스트림 콘솔의 IncomingRecords/IteratorAge 그래프로 소비 지연 확인.
- **Data Viewer**: 스트림 콘솔에서 샤드의 실제 레코드를 브라우저로 열람(base64 자동 디코딩).

## 참고 문서

- Kinesis Data Streams: https://docs.aws.amazon.com/streams/latest/dev/
- Firehose 동적 파티셔닝: https://docs.aws.amazon.com/firehose/latest/dev/dynamic-partitioning.html
- Firehose 데이터 변환: https://docs.aws.amazon.com/firehose/latest/dev/data-transformation.html
- Terraform `aws_kinesis_firehose_delivery_stream`: https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/kinesis_firehose_delivery_stream

## 함정

- **Firehose 는 즉시 배달 안 한다.** 버퍼(크기 or 시간) 조건 충족까지 대기. 동적 파티셔닝이면 최소 60초. 채점 시 이걸 명시하거나 미리 발행.
- **키 이름 `DynamicPartitioningConfiguration`** — `DynamicPartitioning` 은 검증 에러.
- **데이터 base64** — put-record `--data` 는 base64, get-records 도 base64 반환.
- **동적 파티셔닝은 생성 후 비활성화 불가** — 스트림 재생성 필요.
- **role 전파** — 만들고 바로 create-delivery-stream 하면 assume 실패. `sleep 10`.
- Firehose 는 **한 번 만들면 source 타입 변경 불가**(Direct PUT ↔ Kinesis).

## 정리
```bash
aws firehose delete-delivery-stream --region $R --delivery-stream-name lab-firehose
aws kinesis delete-stream --region $R --stream-name lab-stream --enforce-consumer-deletion
aws iam delete-role-policy --role-name lab-fh-role --policy-name p; aws iam delete-role --role-name lab-fh-role
aws s3 rb s3://$BUCKET --force
```
