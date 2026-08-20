# DynamoDB

**트리거 문구** — "DynamoDB 테이블", "GSI/LSI", "TTL", "Streams", "PITR/복원", "삭제 방지", "트랜잭션", "빠른 읽기/쓰기"(NoSQL 모듈).

**전제**
```bash
export R=ap-northeast-2
```

---

## ★ 케이스 A — GSI + LSI + Stream + TTL [검증됨]

한 번에 다 갖춘 테이블. 과제지가 요구하는 조합을 골라 쓴다.

```bash
aws dynamodb create-table --region $R --table-name lab-ddb \
  --attribute-definitions \
    AttributeName=pk,AttributeType=S AttributeName=sk,AttributeType=S \
    AttributeName=gsipk,AttributeType=S AttributeName=lsi_sk,AttributeType=N \
  --key-schema AttributeName=pk,KeyType=HASH AttributeName=sk,KeyType=RANGE \
  --global-secondary-indexes 'IndexName=gsi1,KeySchema=[{AttributeName=gsipk,KeyType=HASH}],Projection={ProjectionType=ALL}' \
  --local-secondary-indexes 'IndexName=lsi1,KeySchema=[{AttributeName=pk,KeyType=HASH},{AttributeName=lsi_sk,KeyType=RANGE}],Projection={ProjectionType=ALL}' \
  --billing-mode PAY_PER_REQUEST \
  --stream-specification StreamEnabled=true,StreamViewType=NEW_AND_OLD_IMAGES
aws dynamodb wait table-exists --region $R --table-name lab-ddb
```

- **GSI**: 다른 PK 로 조회. `--billing-mode PAY_PER_REQUEST` 면 GSI 도 자동. 별도 용량 불필요.
- **LSI**: 같은 PK, 다른 SK. **테이블 생성 시에만** 추가 가능(나중에 못 붙임). GSI 는 나중에 `update-table` 로 추가 가능.
- **Attribute 정의**는 키·인덱스에 쓰는 것만. 나머지는 스키마리스.
- **StreamViewType**: `KEYS_ONLY`/`NEW_IMAGE`/`OLD_IMAGE`/`NEW_AND_OLD_IMAGES`.

## 케이스 B — TTL + PITR + 삭제 방지 [검증됨]

```bash
# TTL (epoch 초 값을 가진 속성)
aws dynamodb update-time-to-live --region $R --table-name lab-ddb \
  --time-to-live-specification "Enabled=true,AttributeName=ttl"

# PITR (35일 연속 백업). ★ 테이블 생성 직후엔 "being enabled" 로 실패 → 20초 후 재시도
aws dynamodb update-continuous-backups --region $R --table-name lab-ddb \
  --point-in-time-recovery-specification PointInTimeRecoveryEnabled=true

# 삭제 방지
aws dynamodb update-table --region $R --table-name lab-ddb --deletion-protection-enabled
```

## 케이스 C — 트랜잭션 / 조건부 쓰기 [검증됨]

```bash
# 트랜잭션: 여러 항목을 원자적으로 (전부 성공 or 전부 실패)
aws dynamodb transact-write-items --region $R --transact-items '[
  {"Put":{"TableName":"lab-ddb","Item":{"pk":{"S":"acct#1"},"sk":{"S":"balance"},"amount":{"N":"1000"}}}},
  {"Put":{"TableName":"lab-ddb","Item":{"pk":{"S":"acct#1"},"sk":{"S":"tx#001"},"amount":{"N":"-100"}}}}
]'

# 조건부 쓰기: 없을 때만 생성 (중복 방지)
aws dynamodb put-item --region $R --table-name lab-ddb \
  --item '{"pk":{"S":"acct#1"},"sk":{"S":"balance"},"amount":{"N":"9999"}}' \
  --condition-expression "attribute_not_exists(pk)"   # 있으면 ConditionalCheckFailedException

# 원자적 카운터
aws dynamodb update-item --region $R --table-name lab-ddb \
  --key '{"pk":{"S":"acct#1"},"sk":{"S":"balance"}}' \
  --update-expression "SET amount = amount - :d" \
  --expression-attribute-values '{":d":{"N":"100"}}'
```

## 케이스 D — 쿼리 (GSI / LSI) [검증됨]

```bash
# GSI: 다른 PK 로
aws dynamodb query --region $R --table-name lab-ddb --index-name gsi1 \
  --key-condition-expression "gsipk = :g" --expression-attribute-values '{":g":{"S":"acct"}}'

# LSI: 같은 PK, SK 정렬/범위
aws dynamodb query --region $R --table-name lab-ddb --index-name lsi1 \
  --key-condition-expression "pk = :p AND lsi_sk > :n" \
  --expression-attribute-values '{":p":{"S":"acct#1"},":n":{"N":"0"}}'

# 필터 (키 아닌 속성)
aws dynamodb query --region $R --table-name lab-ddb \
  --key-condition-expression "pk = :p" \
  --filter-expression "amount > :a" \
  --expression-attribute-values '{":p":{"S":"acct#1"},":a":{"N":"0"}}'
```

## 케이스 E — PITR 복원 / Streams / DAX / Global Table

```bash
# PITR 복원 (새 테이블로. 원본 유지)
aws dynamodb restore-table-to-point-in-time --region $R \
  --source-table-name lab-ddb --target-table-name lab-ddb-restored \
  --use-latest-restorable-time

# Streams → Lambda (../../serverless/lambda/ddb-stream/)
aws dynamodbstreams describe-stream --region $R --stream-arn <stream-arn>

# DAX (마이크로초 캐시, VPC 클러스터)
aws dax create-cluster --cluster-name lab-dax --node-type dax.t3.small \
  --replication-factor 1 --iam-role-arn <role> --subnet-group-name <sg>

# Global Table (멀티리전 복제)
aws dynamodb update-table --region $R --table-name lab-ddb \
  --replica-updates '[{"Create":{"RegionName":"us-west-2"}}]'
```

## 케이스 F — resource policy (리소스 기반 접근제어)

```bash
aws dynamodb put-resource-policy --region $R \
  --resource-arn arn:aws:dynamodb:$R:$ACCT:table/lab-ddb \
  --policy '{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"AWS":"arn:aws:iam::OTHER:root"},"Action":"dynamodb:GetItem","Resource":"arn:aws:dynamodb:'$R':'$ACCT':table/lab-ddb"}]}'
```

## 검증

```bash
aws dynamodb describe-table --region $R --table-name lab-ddb \
  --query 'Table.{Status:TableStatus,Billing:BillingModeSummary.BillingMode,GSI:GlobalSecondaryIndexes[0].IndexName,LSI:LocalSecondaryIndexes[0].IndexName,Stream:StreamSpecification.StreamViewType,Delete:DeletionProtectionEnabled}' --output json
aws dynamodb describe-time-to-live --region $R --table-name lab-ddb --query 'TimeToLiveDescription' --output json
aws dynamodb describe-continuous-backups --region $R --table-name lab-ddb \
  --query 'ContinuousBackupsDescription.PointInTimeRecoveryDescription.PointInTimeRecoveryStatus' --output text
```

## 함정

- **LSI 는 테이블 생성 시에만** — 나중에 못 붙인다. GSI 는 `update-table` 로 추가 가능.
- **PITR 은 생성 직후 실패** — "backups being enabled". 20초 후 재시도.
- **삭제 방지 켜면 delete-table 실패** — 지우려면 먼저 `--no-deletion-protection-enabled`.
- **Attribute 정의는 키/인덱스용만** — 안 쓰는 속성을 정의하면 에러.
- **PAY_PER_REQUEST 면 GSI 용량 자동** — provisioned 면 GSI 마다 RCU/WCU 지정.
- **트랜잭션은 최대 100개 항목** + 같은 리전. 2배 비용.
- **N(숫자) 타입도 문자열로** — `{"N":"1000"}`. `{"N":1000}` 아님.
- CMK 암호화: `--sse-specification Enabled=true,SSEType=KMS,KMSMasterKeyId=<key>`.

## 정리
```bash
aws dynamodb update-table --region $R --table-name lab-ddb --no-deletion-protection-enabled
aws dynamodb delete-table --region $R --table-name lab-ddb
```
