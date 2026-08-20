# RDS Connection 플레이북 (2026 #8)

**가이드 원문(2026 #8)** — "EC2 나 Lambda 에서 RDS 를 다양한 방법으로 연결. **RDS Proxy** 를 통해 연결하거나 **RDS 의 HTTP API(Data API)** 로 쿼리. 바이너리/코드는 출제자 제공."
- 필수: RDS, VPC / 선택: RDS Proxy, EC2, Lambda, IAM

**트리거 문구** — "RDS Proxy 로 연결", "Data API 로 쿼리", "IAM 인증으로 DB 접속", "커넥션 풀링", "Lambda 에서 RDS".

**리전 격리** — 전용 VPC. 예시 `ap-northeast-2`.

> 💸 **비용/시간 경고**: RDS/Aurora 클러스터 생성은 **~10분**, 인스턴스 시간과금. **Aurora Serverless v2 는 min_capacity=0(auto-pause)** 로 만들면 유휴 시 과금 최소. 검증 후 즉시 삭제.

**전제**
```bash
export R=ap-northeast-2 ACCT=$(aws sts get-caller-identity --query Account --output text)
```

---

## 연결 방식 4종 (개념)

| 방식 | 어떻게 | 언제 |
|---|---|---|
| **RDS Proxy** | 앱→Proxy→DB. 커넥션 풀링·페일오버·Secrets 인증 | Lambda 다수 동시연결, 커넥션 고갈 방지 |
| **Data API** | HTTP(SDK `rds-data`)로 SQL. 커넥션 없음 | Lambda 에서 VPC 없이 쿼리, 서버리스 |
| **IAM 인증** | 15분 토큰으로 접속(비번 없음) | 비밀번호 관리 제거, 최소권한 |
| **직접(Secrets)** | Secrets Manager 자격증명 + psql/드라이버 | 전통적, EC2 에서 |

## 케이스 인덱스

| # | 케이스 | 방식 | 검증 |
|---|---|---|---|
| 01 | `cases/01-rds-proxy/` | RDS Proxy + Secrets | ✅ live(proxy available, TLS, SECRETS, cluster target) |
| 02 | `cases/02-data-api/` | Aurora Serverless v2 + Data API | ✅ live(CREATE/INSERT/SELECT 왕복 + boto3 query.py) |
| 03 | `cases/03-iam-auth/` | IAM DB 인증(토큰) | ✅ live(generate-db-auth-token → 368자 SigV4 서명 토큰). psql 접속은 in-VPC EC2 필요 |
| 04 | `cases/04-secrets-rotation/` | Secrets Manager + 회전 | ✅ live(managed secret=02 확인, 수동 secret create/describe). Lambda 회전은 rotation-lambda 필요 |

## 개념 검증 (채점자 문체)

```bash
# Proxy 상태 + 엔드포인트
aws rds describe-db-proxies --region $R --db-proxy-name lab-proxy \
  --query 'DBProxies[0].{status:Status,endpoint:Endpoint,auth:Auth[0].AuthScheme}' --output json
# Data API 활성 여부 (Aurora)
aws rds describe-db-clusters --region $R --db-cluster-identifier lab-aurora \
  --query 'DBClusters[0].{http:HttpEndpointEnabled,engine:Engine,status:Status}' --output json
# Data API 실제 쿼리 (커넥션 없이)
aws rds-data execute-statement --region $R \
  --resource-arn <cluster-arn> --secret-arn <secret-arn> \
  --database lab --sql "SELECT 1 AS ok"
```

## 반칙 자가검사

```bash
# "다양한 방법으로 연결" — 요구된 방식이 실제로 구성됐는지
aws rds describe-db-proxies --region $R --query 'DBProxies[].DBProxyName' --output text   # Proxy 요구 시 존재
aws rds describe-db-clusters --region $R --query 'DBClusters[?HttpEndpointEnabled==`true`].DBClusterIdentifier' --output text  # Data API 요구 시
# 로컬 우회(로컬 postgres 설치) 금지 케이스 — netstat 로 로컬 5432 listen 없어야
```

## 함정

- **Data API 는 Aurora 전용**(PostgreSQL/MySQL). 일반 RDS 인스턴스는 불가. `--enable-http-endpoint`.
- **Serverless v2 는 `engine_mode=provisioned` + `db.serverless` 인스턴스** — 옛 Serverless v1(`engine_mode=serverless`)과 다르다. context7 확인 필수.
- **★ `--skip-final-snapshot` 은 create 옵션 아님**(실측) — delete-db-cluster 전용. create 에 넣으면 "Unknown options".
- **★ Data API 는 cluster-available 만으론 부족**(실측) — 인스턴스도 available 이어야. creating 중이면 `DatabaseNotFoundException: Cannot find DBInstance in DBCluster`. `wait db-instance-available` 까지.
- **RDS Proxy 는 Secrets Manager 필수** — 평문 자격증명 불가. `iam_auth=REQUIRED` 면 클라이언트도 IAM 토큰.
- **Proxy·DB 는 같은 VPC 서브넷 2개 AZ 이상** — subnet group 필요.
- **IAM 인증 토큰은 15분 유효** — `aws rds generate-db-auth-token` + SSL 필수.
- **Lambda→Proxy 는 VPC 연결**(서브넷·SG). Data API 는 VPC 불필요(HTTP).
- **manage_master_user_password** 쓰면 Secrets 를 RDS 가 자동 생성/회전 — Proxy 가 그 secret 참조하면 편함.
- 삭제: Proxy → 인스턴스 → 클러스터 → subnet group. `--skip-final-snapshot`.

## context7 참고

- `aws_db_proxy`·`aws_rds_cluster`(serverlessv2_scaling_configuration, enable_http_endpoint)·`aws_db_instance`(manage_master_user_password) (TF AWS v6)
- RDS Proxy: https://docs.aws.amazon.com/AmazonRDS/latest/userguide/rds-proxy.html
- Data API: https://docs.aws.amazon.com/AmazonRDS/latest/AuroraUserGuide/data-api.html
- IAM 인증: https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/UsingWithRDS.IAMDBAuth.html
