# NoSQL 플레이북 (2025 #2 / 2026 #1)

**가이드 원문** — "NoSQL(DynamoDB, DocumentDB)로 빠른 읽기/쓰기 + 비정형 데이터. DAX, GSI/LSI, Global Table 등. 앱/코드는 배포파일로. 선수는 NoSQL 서비스에 집중."
- 필수: DynamoDB **or** DocumentDB / 선택: VPC, EC2, Lambda, Python

**트리거 문구** — "NoSQL", "DynamoDB 읽기/쓰기", "GSI/LSI", "DAX 캐시", "Global Table", "DocumentDB", "MongoDB 호환".

**리전 격리** — 전용. 예시 `ap-northeast-2`.

**기반 카드**: DynamoDB 전 기능 `../../aws/tier2/dynamodb.md`, PartiQL 15종 `../../aws/tier2/dynamodb/partiql.sql`(실검증), Streams 핸들러 `../../aws/serverless/lambda/ddb-stream/`, scan API `../../aws/serverless/lambda/dynamodb-scan-api/`.

---

## 케이스 인덱스

| # | 케이스 | 서비스 | 검증 |
|---|---|---|---|
| 01 | DynamoDB GSI/LSI/Stream/TTL | DDB | tier2 ✓ + partiql 15종 ✓ |
| 02 | DAX (마이크로초 캐시) | DDB + DAX | `cases/02-dax/`(스크립트, VPC 클러스터) |
| 03 | Global Table (멀티리전 복제) | DDB | `cases/03-global-table/`(live) |
| 04 | DocumentDB (MongoDB 호환) | DocumentDB | `cases/04-documentdb/`(스크립트, ~10분) |
| 05 | boto3 CRUD 앱(배포파일 형) | DDB | `cases/05-crud-app/crud.py` |

## 서비스 선택

| | DynamoDB | DocumentDB |
|---|---|---|
| 모델 | key-value/document | MongoDB 호환 document |
| 확장 | 완전관리 서버리스 | 인스턴스 기반(VPC) |
| 쿼리 | PartiQL / API | MongoDB 쿼리(mongosh) |
| 언제 | 대부분 | MongoDB 마이그레이션·복잡 쿼리 |

## 검증 (채점자 문체)

```bash
# DDB 속성별 (채점은 옵션 하나하나 확인)
aws dynamodb describe-table --region $R --table-name lab-ddb \
  --query 'Table.{Billing:BillingModeSummary.BillingMode,GSI:GlobalSecondaryIndexes[0].IndexName,Stream:StreamSpecification.StreamViewType,Delete:DeletionProtectionEnabled}' --output json
# Global Table 복제
aws dynamodb describe-table --region $R --table-name lab-ddb --query 'Table.Replicas[].RegionName' --output text
# DocumentDB
aws docdb describe-db-clusters --region $R --query 'DBClusters[?DBClusterIdentifier==`lab-docdb`].Status' --output text
# 앱 왕복: 제공된 crud.py 로 put→get
```

## 함정

- **LSI 는 테이블 생성 시에만**, GSI 는 나중에 추가 가능.
- **DAX 는 VPC 클러스터 + 시간과금** — 마이크로초 캐시 필요할 때만. 서브넷그룹+SG 필요.
- **Global Table 은 스트림 필수**(NEW_AND_OLD_IMAGES) + 각 리전 동일 테이블명.
- **DocumentDB 는 VPC 내부 + TLS** — mongosh 로 `--tls --tlsCAFile global-bundle.pem`. 인터넷 직결 불가.
- **DocumentDB 생성 ~10분** — 채점은 미리 뜬 전제.
- N(숫자) 타입도 문자열로(`{"N":"1000"}`).

## context7 참고

- `aws_dynamodb_table`(replica, dax) / `aws_docdb_cluster` (TF AWS v6)
- DAX: https://docs.aws.amazon.com/amazondynamodb/latest/developerguide/DAX.html
- Global Tables: https://docs.aws.amazon.com/amazondynamodb/latest/developerguide/GlobalTables.html
- DocumentDB: https://docs.aws.amazon.com/documentdb/latest/developerguide/
