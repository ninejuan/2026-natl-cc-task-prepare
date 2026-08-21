# DynamoDB 코어 (GSI/LSI/Stream/TTL/PITR/PartiQL) — ✅ live 검증

`partiql.sql`(15종 execute-statement 실검증) + 아래 테이블 기능 전수 실검증(ap-northeast-1, 2026-08-21).
기반: `../../../../aws/tier2/dynamodb.md` + `aws/tier2/dynamodb/partiql.sql`.

## 한 방에 만들기 (LSI 는 생성 시에만!)

```bash
aws dynamodb create-table --region $R --table-name lab-ddb-core \
 --attribute-definitions AttributeName=pk,AttributeType=S AttributeName=sk,AttributeType=S \
                         AttributeName=lsi_sk,AttributeType=N AttributeName=gsi_pk,AttributeType=S \
 --key-schema AttributeName=pk,KeyType=HASH AttributeName=sk,KeyType=RANGE \
 --local-secondary-indexes 'IndexName=lsi1,KeySchema=[{AttributeName=pk,KeyType=HASH},{AttributeName=lsi_sk,KeyType=RANGE}],Projection={ProjectionType=ALL}' \
 --global-secondary-indexes 'IndexName=gsi1,KeySchema=[{AttributeName=gsi_pk,KeyType=HASH}],Projection={ProjectionType=ALL}' \
 --billing-mode PAY_PER_REQUEST \
 --stream-specification StreamEnabled=true,StreamViewType=NEW_AND_OLD_IMAGES
aws dynamodb update-time-to-live --table-name lab-ddb-core \
  --time-to-live-specification Enabled=true,AttributeName=expires_at
aws dynamodb update-continuous-backups --table-name lab-ddb-core \
  --point-in-time-recovery-specification PointInTimeRecoveryEnabled=true
```

## 실측 결과

| 항목 | 확인 명령 | 실측 |
|---|---|---|
| LSI | `query --index-name lsi1` | `o#2 50` / `o#1 100` — **lsi_sk 오름차순 정렬**(테이블 sk 와 다른 정렬축) |
| GSI | `query --index-name gsi1` | `u1 o#2` / `u1 o#1` — `gsi_pk='paid'` 로 조회, `IndexStatus=ACTIVE` |
| Stream | `dynamodbstreams get-records` | `INSERT o#1 100` / `INSERT o#2 50` (**NEW_AND_OLD_IMAGES**) |
| TTL | `describe-time-to-live` | `{"TimeToLiveStatus":"ENABLED","AttributeName":"expires_at"}` |
| PITR | `update-continuous-backups` | `ENABLED` |
| GSI 나중 추가 | `update-table --global-secondary-index-updates '[{"Create":…}]'` | `gsi1 ACTIVE` / `gsi2 CREATING` → **가능** |
| LSI 나중 추가 | — | `update-table` 에 **`--local-secondary-index*` 옵션 자체가 없다** → 불가 |

## 함정 (실측)

- **★ LSI 는 create-table 에서만.** 나중에 못 붙인다(옵션이 존재하지 않음). 설계 때 결정.
- **GSI 는 나중에 추가 가능**하지만 **backfill 중엔 테이블을 못 지운다** — `delete-table` 이 `ResourceInUseException: Cannot delete table while indexes are being created`. GSI 가 `ACTIVE` 될 때까지 대기.
- **LSI 는 파티션키가 테이블과 같아야** 하고 정렬키만 다르다. GSI 는 파티션키부터 자유.
- **Stream 은 `LatestStreamArn`** 으로 `dynamodbstreams` API 를 따로 쓴다(`describe-stream` → `get-shard-iterator` → `get-records`).
- `describe-table --query` 는 **`Table.` 접두사**가 필요(`Table.GlobalSecondaryIndexes[]`). 빼면 조용히 `null` 이 나와 "설정이 안 됐다"고 오해한다(실측).
- TTL 삭제는 **최대 48시간 지연** — 채점이 즉시 삭제를 기대하면 TTL 로 풀지 말 것.
