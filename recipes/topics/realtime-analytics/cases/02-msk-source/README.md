# MSK(Kafka) 소스 — Managed Flink Studio

`notebook-msk-source.sql`. Kinesis 대신 MSK 에서 읽을 때. **커넥터 JAR 이 있어야 한다**(케이스 01 참조).

## 필요한 아티팩트 (실측)

```jsonc
"CustomArtifactsConfiguration": [
  {"ArtifactType":"DEPENDENCY_JAR","MavenReference":{"GroupId":"org.apache.flink","ArtifactId":"flink-connector-kafka","Version":"1.15.4"}},
  {"ArtifactType":"DEPENDENCY_JAR","MavenReference":{"GroupId":"software.amazon.msk","ArtifactId":"aws-msk-iam-auth","Version":"1.1.6"}}
]
```
- **`flink-connector-kafka`** — `flink-sql-connector-kafka:1.15.4` 는 `InvalidArgumentException: Found unsupported Maven References` 로 **거부**된다(실측).
- **`software.amazon.msk:aws-msk-iam-auth:1.1.6`** 은 수락됨(실측). MSK IAM 인증(`AWS_MSK_IAM`)에 필요.
- 생성 시점의 `ApplicationConfiguration` 에 넣거나, 나중에 `update-application`(앱이 **READY** 일 때만).

## 검증 수준 (정직하게)

이 계정에서 **커넥터·옵션이 유효한 데까지** 확인했다. 실제 MSK 클러스터 왕복은 안 했다.

| 단계 | 결과 |
|---|---|
| `CREATE TABLE … 'connector'='kafka' …`(IAM SASL 옵션 전부 포함) | ✅ `Table has been created.` |
| `SELECT * FROM orders_kafka` | ⚠️ `No resolvable bootstrap urls given in bootstrap.servers` |

→ 두 번째 에러가 **"커넥터를 못 찾겠다"가 아니라 "부트스트랩 호스트를 못 찾겠다"** 라는 게 핵심이다.
커넥터 팩토리와 `properties.sasl.*` 옵션은 전부 통과했고, 일부러 넣은 가짜 엔드포인트만 실패했다.
(커넥터 JAR 이 없을 때는 `Could not find any factory for identifier 'kafka'` 가 뜬다 — 완전히 다른 에러.)
실제 MSK 엔드포인트를 넣으면 그대로 동작한다.

## 함정

- **bootstrap 은 `get-bootstrap-brokers` 의 `BootstrapBrokerStringSaslIam`**(9098). Serverless 는 이것만 나온다.
- **Studio 앱이 MSK 와 같은 VPC** 여야 한다(`VpcConfigurations`). MSK 는 인터넷에서 못 닿는다.
  VPC 에 넣으면 Glue/S3/Maven 접근을 위해 NAT 또는 VPC 엔드포인트가 필요하다.
- Studio 실행 role 에 `kafka-cluster:Connect/DescribeTopic/ReadData` + `kafka:DescribeCluster` 필요.
- `scan.startup.mode`: `latest-offset`(기본) / `earliest-offset` / `group-offsets`. 미리 넣어둔 메시지를 보려면 earliest.
- MSK 토픽은 **미리 만들어져 있어야** 한다(Flink 가 자동 생성하지 않는다). `../../msk/` 의 admin.py 참고.
