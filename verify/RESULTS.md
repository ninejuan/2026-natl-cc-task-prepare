# 실검증 기록

계정 `156041424727`. 카드/스크립트를 실제로 돌린 결과만 적는다. 추정치는 적지 않는다.

> 주의: 이 계정에는 task3 연습 인프라(`apdev-*`, EKS `apdev-eks` 1.35)가 살아 있다. 검증용 리소스는 이름을 겹치지 않게 만들고, 남의 것을 지우지 않는다.

| 대상 | 리전 | 결과 | 소요 | 비용 | 비고 |
|---|---|---|---|---|---|
| `bin/discover.sh` | ap-northeast-2 | ✓ | ~20s | $0 | 41개 변수 추출. VPC/서브넷/SG/RT/EKS(+OIDC·버전·NG)/ALB·TG/CF/DDB/S3/Lambda/ECR/KMS/EC2 확인 |
| `bin/mark-self.sh --foul` | ap-northeast-2 | ✓ | 5.5s | $0 | 최초 120s+ → IAM 정책 조회 `xargs -P8` 병렬화로 5.5s. `Resource:"*"` 오탐 제거(Action/Principal만 검사) |
| `bin/build-all.sh` | — | ✓ | 즉시 | $0 | 카드 0개 상태 정상 종료 확인. bash 3.2 호환(mapfile 제거) |
| `bin/bootstrap.sh` | — | 부분 | — | $0 | macOS에서 실행 불가(Linux 바이너리). 다운로드 URL 6종 HTTP 200 확인, kustomize는 404라 제거(kubectl -k 사용). **CloudShell 실행 검증 필요** |

## recipes/aws/serverless — 실계정 배포·호출 검증

| 대상 | 결과 | 비고 |
|---|---|---|
| `lambda.md` zip 생성·invoke·env | ✓ | python3.13, query/env 정상 반환 |
| `lambda.md` Function URL (auth NONE) | ⚠️ | URL 발급은 정상이나 **org SCP 로 403**. 카드에 함정 기록. AWS_IAM/ALB/APIGW 로 우회 |
| `lambda.md` ESM(SQS) | ✓ | 메시지 2건 발행→소비, 큐 잔량 0 |
| `scripts/deploy-lambda.sh` | ✓ | 생성/갱신 멱등, invoke 로 코드 반영 확인 |
| `lambda/crud-booking` | ✓ | POST 저장·GET booking_id·**GSI client_id 2건**·검증 400·health 200 |
| `lambda/sqs-batch` | ✓ | ESM + **ReportBatchItemFailures**: 정상 2건 저장, broken 1건만 재시도(NotVisible) |
| `lambda/ddb-stream` `_deser` | ✓ | 단위테스트 (S/N/BOOL 변환) |
| 핸들러 8종 구문 | ✓ | `py_compile` 전부 통과 |
| `apigateway.md` A(DDB 직접통합+VTL) | ✓ | `1000`/`100` raw 출력, `mysecret*`→403. 2025 inventory 재현 |
| `apigateway/vtl/ddb-query-json-res` | ✓ | Query→JSON 배열 변환(`#foreach`+콤마) 실 API 확인 |
| `apigateway/vtl/sfn-start-req` | ✓ | API→SFN StartExecution, executionArn 200 |
| `stepfunctions/inventory-ddb` | ✓ | 실행 SUCCEEDED, stock 80·balance 1020 (SDK 직접통합) |
| `stepfunctions/map-parallel` | ✓ | Map 2항목 저장 + Parallel 2브랜치 결과 |
| `stepfunctions/` 나머지 3종 | ✓ | `validate-state-machine-definition` OK |
| `eventbridge.md` Scheduler | ✓ | rate(5min) 스케줄 ENABLED |
| `eventbridge.md` Pipes(SQS→SNS) | ✓ | 필터 포함 RUNNING |
| `sqs-sns.md` FIFO·DLQ·filter policy | ✓ | FIFO 순서 보장, redrive policy, SNS filter 확인 |

모든 lab 리소스 삭제 완료(함수·큐·API·SM·테이블·역할). 잔여 0.

### 발견한 함정 (카드에 반영됨)
- **zsh ARN modifier**: `"$VAR:영문자"` 가 `:r`/`:s` 로 잘림. `${VAR}:...` 또는 조회로 받기. 반복 발생 → 전 카드 공통 경고.
- **Function URL SCP 403**: org 계정에서 auth NONE 차단 가능.
- **DDB 키 스키마 불일치**: 핸들러 PK(`pk`)와 테이블 PK(`booking_id`) 다르면 PutItem 이 조용히 실패(ESM 은 NotVisible 로 쌓임).

## recipes/aws/analytics — 실계정 검증

| 대상 | 결과 | 비고 |
|---|---|---|
| `kinesis.md` Data Stream (on-demand) | ✓ | ACTIVE, put/get-record |
| `kinesis.md` Firehose→S3 동적 파티셔닝 | ✓ | `events/dt=2026-08-20/` 파티션 적재. **키명 `DynamicPartitioningConfiguration`** |
| `athena.md` partition projection | ✓ | crawler 없이 CREATE TABLE → click 5건 집계 SUCCEEDED |
| `glue/` Crawler | ✓ | S3 JSON 스캔 → 스키마(event_type/id)+파티션(dt) 자동발견, SUCCEEDED |
| `glue/etl_json_to_parquet.py` | 문서 | 스크립트 제공(구문). job 실행은 DPU 비용 커서 미실행 |
| `managed-flink/` Studio | ✓ | RUNNING, ZEPPELIN-FLINK-3_0, Glue 카탈로그 연결 확인 |
| `managed-flink/notebook-*.sql` | ✅ live | Zeppelin REST(presigned 쿠키)로 실행 — TUMBLE/HOP/CUMULATE/TopN/SESSION + Kinesis 소스 결과 확인. ★커넥터 JAR 추가 필요 |
| `msk/` Serverless 클러스터 | ✓ | **~15분 내 ACTIVE**(provisioned보다 빠름), IAM SASL 부트스트랩 9098 확인 |
| `msk/producer.py·consumer.py` | 문서 | IAM 인증 코드. produce/consume 은 VPC 내 EC2 필요(미실행) |

**검증된 파이프라인**: Kinesis→Firehose→S3→Athena 전 구간(click 5건) + Glue crawler 스키마 자동발견.
모든 analytics lab 삭제 완료(IAM 잔여 0, MSK DELETING).

### 발견한 함정 (카드 반영)
- Firehose `DynamicPartitioning` → `DynamicPartitioningConfiguration` (CLI 검증 에러).
- Firehose 는 즉시 배달 안 함 — 동적 파티셔닝 시 버퍼 최소 60초.
- MSK/Flink VPC 내부 전용, MSK SG self-inbound 9098 필수.

## analytics 보강분 추가 실검증 (2차)

| 대상 | 결과 | 비고 |
|---|---|---|
| `kinesis/transform-lambda.py` | ✓ | Firehose 이벤트로 invoke: CLICK→click 정규화·dt보강·Ok / value없음 Dropped |
| `kinesis/firehose-parquet-conf.json` | ✓ | Direct PUT + Lambda transform + Parquet 변환 → S3 .parquet → Athena 재쿼리(click 3/sum 60) |
| `glue/etl_aggregate_join.py` | ✓ | Glue job SUCCEEDED, events+users 조인·집계 → Parquet (premium/click 2/30, basic/view 1/5) |
| `msk/admin.py` | ✓ | 토픽 orders 6파티션 생성·list (VPC EC2 + IAM SASL) |
| `msk/producer.py` · `consumer.py` | ✓ | 10건 발행 → 10건 소비 왕복 (IAM SASL 9098) |
| athena `queries/*.sql` | ✓ | (1차) DDL·집계·윈도우·CTAS·UNLOAD |
| `kinesis/producer.py` | ✓ | (1차) 실 스트림 15건 발행 |

### MSK IAM 인증 — 실검증 중 발견한 버그 2개 (코드·카드 수정 완료)
1. `kafka.sasl.oauth.AbstractTokenProvider` import 실패 → kafka-python-ng 2.2+ 는
   `sasl_mechanism="AWS_MSK_IAM"` 내장(`kafka/sasl/msk.py`). `aws-msk-iam-sasl-signer`
   불필요, botocore 만 필요. producer/consumer/admin 3개 전면 수정.
2. botocore `region: None` → `NoBrokersAvailable`. `AWS_DEFAULT_REGION` 명시 필요.
- Glue Parquet 타입 함정: SUM(int)→INT64 라 Athena 테이블 스키마를 double 로 잡으면 HIVE_BAD_DATA.

## recipes/aws/tier1 — 실계정 검증

| 대상 | 결과 | 비고 |
|---|---|---|
| `route53.md` split-view | ✓ | public zone q1→54.0.0.10(권위서버 dig), private zone q1→172.16.0.10(API). 2024 DNS 재현 |
| `route53.md` 라우팅정책 | ✓ | weighted·failover(+health check)·latency·geolocation 4종 생성 |
| `cloudfront.md` OAC | ✓ | 배포 Deployed(실측 ~2분), CF 200 "Cloud Skills 2026", **S3 직접 403**. 2024 CDN 재현 |
| `cloudfront/functions/viewer-request` | ✓ | test-function: /old→/index.html 리라이트 |
| `cloudfront/functions/viewer-response-headers` | ✓ | test-function: x-custom-marker 헤더 추가 |
| `acm.md` DNS 검증 발급 | ✓ | us-east-1 request-certificate, PENDING_VALIDATION 확인 |

tier1 lab 정리: Route53 zone/HC 삭제 완료. CloudFront 는 disable→반영 대기 후 삭제 예정(S3 포함).

## recipes/aws/tier2 — 실계정 검증

| 대상 | 결과 | 비고 |
|---|---|---|
| dynamodb GSI+LSI+Stream+TTL | ✓ | 한 테이블에 다 구성 |
| dynamodb PITR·트랜잭션·조건부·GSI/LSI 쿼리 | ✓ | PITR ENABLED(재시도), transact-write, ConditionalCheckFailed 차단, GSI/LSI query |
| s3 버전관리·SSE-KMS·라이프사이클 | ✓ | 2버전, aws:kms, expire 룰 |
| s3 Access Point·정적호스팅 | ✓ | AP 객체접근(v2), 웹호스팅 "Cloud Skills 2026" |
| ecr 스캔·태그불변·라이프사이클 | ✓ | IMMUTABLE·scanOnPush·2룰 (push 제외) |
| ecs Fargate+CloudMap | ✓ | task RUNNING, CloudMap task IP 자동등록(10.0.139.110), awslogs 스트림 |
| waf managed+rate+custom403 | ✓ | WebACL REGIONAL + 3룰 생성 |

tier2 lab 전량 정리(DDB·S3 버전버킷·ECS·CloudMap·WAF·역할). 
S3 버전관리 버킷은 버전+삭제마커 제거 후 rb (카드 정리 절차 반영).

## recipes/aws/tier3 — 실계정 검증

| 대상 | 결과 | 비고 |
|---|---|---|
| code-series CodeBuild | ✓ | S3소스→docker build→ECR push v1. 로컬 Docker 없이. DOWNLOAD_SOURCE 403·privilegedMode 함정 발견 |
| efs 파일시스템+AP+정책 | ✓ | available, access point(/app POSIX1000), fs policy |
| config-ssm Parameter Store | ✓ | String/SecureString(복호화)/StringList/경로조회 |
| cloudwatch 대시보드·알람·metric filter | ✓ | dashboard, alarm(INSUFFICIENT_DATA), metric filter |
| secretsmanager 시크릿·정책 | ✓ | 시크릿 조회, resource policy |
| backup vault·plan | ✓ | vault, plan(cron 0 5) |
| cloudmap | ✓ | (tier2 ECS 연동에서 task IP 자동등록 검증) |
| mq RabbitMQ 브로커 | ✓ | RUNNING(m7g.large, t3.micro 미지원), amqps 5671 |
| iam-federation Assume+ExternalID | ✓ | 올바른 ID assume 성공, 없거나틀리면 AccessDenied |

tier3 lab 전량 정리.
- ⚠️ Flink Studio(analytics 검증 때 생성)가 삭제 실패로 READY 로 수 시간 잔존 → 최종 스캔에서 발견·재삭제. **삭제 요청 후 상태 재확인 필요**(delete-application 이 조용히 실패할 수 있음).

## 예제 컬렉션 보강 (tier1/2/3, Athena.md 식 다양한 use-case)

검증 강도 표기: **실행**=리소스에 실제 명령 성공 / **수락**=API가 문서 수락(실동작 아님) / **린트**=validate-policy 등 정적 검증.

| 컬렉션 | 검증 강도 | 검증 방식 / 발견 |
|---|---|---|
| tier2/dynamodb/partiql.sql (15종) | 실행 15/15 | `execute-statement` 15개 실행. 카운터 1000→900→400, 조건부 amount<500 정확히 ConditionalCheckFailed |
| tier2/s3/bucket-policies.md (13종) | 린트 13/13 + 실행 2 | 13종 `accessanalyzer validate-policy`(RESOURCE_POLICY) ERROR 0. 수정한 VPCe/IP Deny 2종은 실제 put→self-delete 로 **자기잠금 아님** 확인 |
| tier2/waf/rule-statements.json (12종) | 실행 12/12 | 12종 전부 한 WebACL 에 넣어 `create-web-acl` 통과. **CLI ByteMatch SearchString 은 base64 필수**(평문이면 "Invalid base64") |
| tier1/route53/record-sets.md | 실행 12/14 | 기본 6종(A/AAAA/CNAME/MX/TXT/NS) + 정책 6종(weighted/failover/latency/geo/multivalue/geoproximity) 실제 UPSERT 통과. Alias 2종은 실 타깃 필요라 문법만(스킵 표기) |
| tier3/cloudwatch/logs-insights.md (17종) | 실행 16/17 | `start-query` 16개 실행. error_pct=40, distinct=3, pct/avg 정확. 콜드스타트(avg_init=320.1)·Lambda REPORT parse(max=120.5)도 시드 로그로 실행 확인. VPC Flow 1종만 실제 flow-log 그룹 자동필드 필요라 문법만 |
| tier3/iam/policy-documents.md (22종) | 실행 9 + 린트 13 | trust 9종 실제 `create-role` 통과, identity 13종 `validate-policy` ERROR 0 |
| tier1/cloudfront/functions/ (7종) | 실행 7/7 | 전부 `test-function` 실행 검증. **querystring 재할당은 키 순서 못 바꿈**(정렬 no-op) → utm 삭제로 수정 |
| tier2/ecs/taskdefs/ (6종) | 수락 6/6 | 6종 전부 `register-task-definition` 수락(fargate/healthcheck+dependsOn/firelens/EFS/secrets/EC2 bridge). task 실기동은 미검증 |

전량 정리 확인(S3·Route53·DDB·로그그룹·WebACL·IPSet·test role·CFF 함수·health check 0개 잔존).

### ★ 실검증 중 밟은 사고 (문서 반영)
- **S3 버킷 자기잠금**: `Action:"s3:*"` + 조건 Deny(VPCe/IP)를 apply 하면 `s3:PutBucketPolicy`/`DeleteBucketPolicy` 까지 Deny → VPCe 밖 IAM user 본인이 정책 해제 불가 → **버킷 영구 잠김(root 만 해제)**. 실제로 테스트 버킷 잠가서 root 로 삭제함. **현장엔 root 없음** → 데이터 액션만 나열하도록 컬렉션 수정 + 함정 명시.
- Route53 하위위임 NS 레코드는 존 삭제 시 apex NS/SOA 와 구분해 따로 삭제해야 함(안 그러면 HostedZoneNotEmpty).

## 2과제 토픽 플레이북 (recipes/topics/)

### Wave A — 신규·고가 (context7 최신문법 확인 + live)

| 토픽 | 케이스 | 검증 강도 | 발견 |
|---|---|---|---|
| VPC Lattice | 01 Lambda service | 실행(E2E) | service network+service+listener+LAMBDA TG+2 association 전부 ACTIVE. VPC 전용 생성. |
| VPC Lattice | 02 EC2 instance target | 스크립트(EC2 과금) | INSTANCE TG+health check 문법. 실행은 01 로 대체 |
| VPC Lattice | 03 path/header routing | 실행 | pathMatch/headerMatches/fixedResponse rule 실제 create |
| VPC Lattice | 04 weighted | 실행 | 90:10 가중 forward rule 실제 create |
| VPC Lattice | 05 auth policy | 실행 | service AWS_IAM 전환 + put-auth-policy Active |

| Network Firewall | 01 stateless 5tuple | 실행 | rule group create (aws:drop 22 / forward_to_sfe) |
| Network Firewall | 02 stateful suricata | 실행 | Suricata rules_string rule group create |
| Network Firewall | 03 domain filtering | 실행 | ALLOWLIST/DENYLIST(HTTP_HOST+TLS_SNI) rule group create |
| Network Firewall | 04 policy+logging | 실행 | firewall policy(stateless+stateful ref) create |
| Network Firewall | 05 firewall deploy | 실행(E2E) | 전용 VPC+firewall endpoint READY+inspection 라우팅. 즉시 삭제 |
| Client VPN | 01 mutual TLS | 실행 | easy-rsa 인증서→ACM import→endpoint 생성 성공 |
| Client VPN | 02 endpoint deploy | 실행 | endpoint 생성(cert-auth/split/DNS)+.ovpn export. association 생략(과금), 즉시 삭제 |
| Client VPN | 03 SAML auth | 스크립트 | SAML provider+federated-auth endpoint (IdP metadata 필요) |
| Client VPN | 04 split-tunnel/DNS | 문서 | PHZ 해석(VPC .2 리졸버)+2024 반칙검사 흐름 |
| RDS Connection | 01~04 | 스크립트(미생성) | Aurora 생성 ~10분이라 실생성 안 함. 문법은 context7(TF v6) 확인. Data API/Proxy/IAM auth/rotation 스크립트+boto3 |

**Network Firewall 발견 함정(실측)**:
- firewall 생성/삭제 각 5~10분(PROVISIONING/DELETING). 채점 3분과 안 맞음 → 미리 배포 전제.
- **삭제 순서**: firewall endpoint 참조 라우트 삭제 → firewall(수 분) → policy → rule group. 역순 실패.
- **★ `create-route --vpc-endpoint-id` 라우트는 describe 시 endpoint 가 `GatewayId` 필드에 뜬다**(VpcEndpointId 아님). 삭제는 dst cidr 로. 이걸 모르면 firewall 삭제 무한실패.

**Client VPN 발견 함정(실측)**:
- **서버 인증서 CN 은 FQDN 필수** — CN=server 면 ACM DomainName=null → endpoint "does not have a domain" 거부. vpn.lab.internal 로 해결.
- endpoint 삭제 후 ACM 인증서 삭제 ~1분 지연(in use).
- association 전이면 과금 없음(pending-associate). 검증은 association 없이 endpoint 설정+.ovpn export 로 충분.

### Wave B/C — 2025·공통 토픽 (기존 검증카드 조합 + 신규 케이스 live)

| 토픽 | live 검증 | 비고 |
|---|---|---|
| RDS Connection | Data API(CREATE/INSERT/SELECT 왕복+query.py boto3) + RDS Proxy(available,TLS,SECRETS,cluster target) | Aurora Serverless v2 실생성→검증→삭제 |
| message-queue | FIFO(순서+콘텐츠 중복제거) + EventBridge Pipes(RUNNING) + 부분배치 handler(unit) | DLQ/fanout 은 sqs-sns.md 기반 |
| storage-protect | S3 Access Point(Internet, prefix 정책) | Macie 는 계정과금이라 미실행(현재 미활성 확인) |
| nosql | crud.py(put/get/query/delete 왕복) | DDB. DAX/DocDB 는 스크립트 |
| ecs-logging/monitoring/efs-security/waf/cicd | 기존 tier2/tier3 검증카드 조합 | taskdef 6종·rule 12종·cloudwatch 등 기검증 |
| workflow/cdn/cloud-governance/flink/msk/eks-scaling/container-logging/keycloak/rest-api | 기존 serverless/analytics/cncf/k8s 카드 조합 | 각 토픽 신규 케이스는 핸들러/스크립트 |

**RDS 발견 함정(실측)**:
- `--skip-final-snapshot` 은 create-db-cluster 옵션 아님(delete 전용). create 에 넣으면 Unknown options.
- Data API 는 cluster-available 만으론 부족 — 인스턴스도 available 이어야(creating 중 DatabaseNotFoundException).
- managed master secret(`--manage-master-user-password`)을 Proxy 가 그대로 참조 → Secrets 수동생성 불필요.

**message-queue 발견(실측)**: FIFO ContentBasedDeduplication 로 동일본문 3건→2건 수신(순서 보장). Pipes RUNNING 확인.

**VPC Lattice 발견 함정(실측)**:
- Lambda 타깃은 항상 `UNAVAILABLE`(reasonCode HealthCheckNotSupported) = **정상**. Lattice 는 Lambda 헬스체크 안 함. TG 가 ACTIVE 면 OK.
- **rule priority 1~2000**(초과 ValidationException), **fixedResponse 는 404·500 만**(403/401/503 unsupported).
- **API throttle 빡셈** — 연속 create 시 ThrottlingException. sleep+재시도 필수.
- **VPC association 삭제는 ENI 회수 ~60-90s** — 안 기다리면 delete-service-network ConflictException, delete-vpc DependencyViolation. teardown 폴링+재시도로 처리.
- 전량 정리 확인(svc/TG/net/VPC 0).

## 발견 함정 총정리 (전 카드 반영)
- **zsh ARN modifier**: `"$VAR:영문자"` → `:r`/`:s`/`:l` 로 잘림. `${VAR}:...` 중괄호 또는 조회. heredoc 안에서도 발생.
- Firehose `DynamicPartitioningConfiguration`(not `DynamicPartitioning`).
- MSK: kafka-python-ng 2.2+ AWS_MSK_IAM 내장, botocore `AWS_DEFAULT_REGION` 필요, SG self-inbound 9098.
- Lambda Function URL SCP 403(org 계정).
- CodeBuild: S3 소스 권한, privilegedMode:true.
- RabbitMQ t3.micro 미지원. Glue Parquet SUM(int)=INT64.
- 삭제 요청 후 재확인(Flink delete 조용히 실패).

## 미검증 / 확인 필요

- `bin/bootstrap.sh` 를 CloudShell(bash 5, Amazon Linux 2023)에서 실제 실행
- `lambda/image-resize` (Pillow 네이티브 의존성 — 실배포 시 아키텍처 wheel 확인 필요)
- `apigateway/vtl/sns-publish-req`, `validate-transform-req` (문법만, 실 API 미검증)
- ~~`managed-flink` SQL 노트북 (CLI 자동화 불가)~~ → **정정: 가능**. presigned URL 쿠키로 Zeppelin REST 사용. 윈도우 SQL 5종 + Kinesis 소스 실행 결과 확인(아래 2026-08-21 절)
- k8s/cncf 매니페스트 (오프라인 문법만)

---

# 2026-08-21 추가 라이브 검증 (계정 전환 후 이어서)

이 세션에서 **파일만/문서형이던 케이스를 실계정으로 밀어붙인** 결과. 전부 생성→검증→삭제 완료, 계정 잔재 0
(Lambda@Edge 복제본 회수 후 `lab-edge-*` 까지 삭제 완료 — 최종 잔재 0).

| 케이스 | 리전 | 결과 | 무엇을 실제로 확인했나 |
|---|---|---|---|
| **ecs-logging 03** FireLens→OpenSearch | ap-northeast-2 | ✅ live | OpenSearch 도메인 실생성 → Fargate(app+fluent-bit) → `ecs-logs` 인덱스 **33건**, 문서에 `ecs_cluster`/`ecs_task_arn`/`ecs_task_definition` 부착 |
| **message-queue 03** 부분배치 실패 | eu-west-1 | ✅ live | 3건 중 1건만 실패 → DLQ 에 `{"id":"fail-me"}` **1건만**, 성공 2건 **재처리 0회**(로그 카운트) |
| **workflow 06** Express vs Standard | us-west-2 | ✅ live | 동일 ASL 두 타입 실행. Express `list-executions` = **`StateMachineTypeNotSupported`**, 이력은 CW Logs 에만 |
| **client-vpn 04** split-tunnel+DNS | ap-southeast-1 | ✅ live | endpoint `available`, `SplitTunnel=true`, `DnsServers=[10.40.0.2]`, PHZ `db.day2.local`→**10.40.1.99** 해석. `.ovpn` 에 DNS 없음(서버 push) |
| **client-vpn 03** SAML federated | ap-southeast-1 | ✅ live | IAM SAML provider + `federated-authentication` endpoint + **`SelfServicePortalUrl` 자동 생성** + 그룹 인가 `GroupId=developers, AccessAll=False` |
| **cdn 03** Lambda@Edge 이미지 리사이징 | us-east-1 + CF | ✅ **live E2E** | Node20+sharp. `?w=100`→**100×75 PNG**, `?w=64`→**64×48 PNG**, S3 직접접근 403 |
| **nosql 01** DDB 코어 | ap-northeast-1 | ✅ live | LSI 정렬 쿼리 / GSI ACTIVE 쿼리 / Stream `INSERT` 레코드(NEW_AND_OLD_IMAGES) / TTL·PITR ENABLED / GSI 사후추가 |
| **msk 04** Serverless vs Provisioned | us-east-1 | ✅ live 비교 | 두 타입 동시 생성. `ClusterType` 구분, serverless 는 ZK·브로커 필드 없음 + `list-nodes` 거부, provisioned 는 `b-1/b-2:9098`+ZK 2181 |
| **realtime-analytics 01/03/05** Flink SQL | eu-west-2 | ✅ live | Studio 노트북에서 **TUMBLE/HOP/CUMULATE/윈도우TopN/SESSION 전부 실행→결과**, Kinesis 소스 SELECT + 1분창 집계까지 |

## 이 세션에서 새로 뚫은 함정 (전부 실측)

**Lambda@Edge 502 3종** — 셋 다 겪고 해결했다.
1. `X-Edge-*` 접두사 헤더 추가 → `The function tried to add a blacklisted header.`
2. 응답 객체를 **새로 만들어 반환** → `The function tried to add, delete, or change a read-only header.`
   → 받은 `response` 를 **수정**해서 반환할 것(`content-length` 는 delete).
3. OAC 오리진 + `AllViewer` 오리진요청정책 → **S3 403**(Host 헤더 전달로 SigV4 깨짐)
   → `AllViewerExceptHostHeader`(b689b0a8-53d0-40ab-baf2-68738e2966ac).
   추가로 Lambda@Edge 는 **환경변수 불가**(버킷/리전을 `request.origin.s3.domainName` 에서 파싱), 함수 삭제는 복제본 회수까지 수 시간.

**Managed Flink Studio** — 문서 정정 2건.
- ❗ **CLI/TF 로 만든 Studio 앱엔 커넥터가 `blackhole/datagen/filesystem/print` 뿐이다.**
  `'connector'='kinesis'` 테이블은 DDL 은 통과하고 **SELECT 에서** `Could not find any factory for identifier 'kinesis'` 로 죽는다.
  → `update-application` 의 `CustomArtifactsConfigurationUpdate` 로 Maven 아티팩트 추가(앱이 **READY** 일 때만).
  Kafka 는 **`flink-connector-kafka`** — `flink-sql-connector-kafka:1.15.4` 는 `unsupported Maven References` 로 거부.
- ❗ **Zeppelin 은 CLI 로 구동 가능하다**(기존 "브라우저 전용" 서술이 틀렸다).
  presigned URL 을 한 번 치면 나오는 `VerifiedAuthToken` 쿠키로 `/zeppelin/api/...` REST 를 그대로 쓴다.
  GET 은 쿠키 없이도 되지만 **POST 는 403**. 실행은 `POST /api/notebook/run/{note}/{para}`, 취소는 `DELETE /api/notebook/job/{note}/{para}`.
- `CREATE TABLE` 은 **Glue 카탈로그에 영구 저장** — 앱 재시작해도 남아 재실행 시 `already exists`.
- **윈도우 TVF 인자는 테이블 이름만** — `TABLE (SELECT … FROM (VALUES …))` 인라인 서브쿼리는 ParseException.
- 무한 스트림 문단은 **취소해야** 결과 스냅샷이 남는다(`status=ABORT` + 결과 보존).

**그 외**
- OpenSearch 도메인 생성 **실측 ~50분**(t3.small.search 1노드). `Processing=True` 동안 `Endpoint`=`None`.
- OpenSearch 출력에 `Type` 옵션 금지(2.x 는 매핑 타입 없음), `Suppress_Type_Name: On` 만. 조회는 SigV4 서명 필요.
- **taskdef JSON 을 셸 heredoc 으로 조립 금지** — 앱 command 의 `$i`/`$((i+1))` 가 셸에 치환돼 JSON 이 깨진다.
- `sqs send-message-batch --entries Id=..,MessageBody={..}` **shorthand 는 JSON body 파싱 실패** → `file://`.
- SQS 큐는 **삭제 후 60초** 재사용 불가(`QueueDeletedRecently`).
- Step Functions **Express 로깅 role 에 `logs:CreateLogDelivery` 등 8종** 필요, 로그그룹 ARN 끝에 `:*`.
- `describe-table --query` 에 **`Table.` 접두사** 빠지면 에러 없이 `null`(설정 누락으로 오진).
- DDB **GSI backfill 중 `delete-table` 거부**(`ResourceInUseException`).
- Client VPN `.ovpn` 에 **`dhcp-option DNS` 없음**(연결 시 서버 push). 대신 `verify-x509-name <서버CN>` 이 있어 **CN=FQDN** 이 필수인 이유가 드러난다.
- MSK **provisioned 생성 실측 ~60분**(t3.small×2), serverless ~10분.

## 추가분 (같은 날, 2차)

| 케이스 | 리전 | 결과 | 확인 내용 |
|---|---|---|---|
| **realtime-analytics 04** 이상탐지→S3 | eu-west-2 | ✅ live | `flink-json/dt=2026-08-21/{_SUCCESS, part-…(399줄 JSON)}` S3 적재 확인 |
| **realtime-analytics 02** MSK 소스 | eu-west-2 | ⚠️ 커넥터까지 live | kafka 테이블 생성 성공, SELECT 는 `No resolvable bootstrap urls`(=팩토리 통과, 가짜 엔드포인트만 실패) |
| **keycloak-sso 01** SAML→IAM role×2 | 글로벌 | ✅ AWS 쪽 live | SAML provider + role×2 + `SAML:aud` trust 조건 실측 |
| **keycloak-sso 02** OIDC→IAM role | 글로벌 | ⚠️ 제약 발견 | **사설 issuer 로는 OIDC provider 생성 불가**(AWS 가 `/.well-known` 조회) |

### 레시피 SQL 자체가 안 돌던 것 3건 — 실행으로 찾아 고침 (realtime-analytics)

1. `'format' = 'parquet'` → `Could not find any format factory for identifier 'parquet' in the classpath.`
   Studio 기본엔 parquet 포맷이 없다. **json/csv 는 내장.**
2. `GROUP BY window_end, event_type` → `Table sink … doesn't support consuming update changes`.
   `window_start` 를 빼면 윈도우 집계가 아니라 일반 GroupAggregate → retraction 발생 → 파일 싱크(append-only) 거부.
   **`GROUP BY window_start, window_end, …`** 로 수정.
3. `LAG(cnt,1) OVER (ORDER BY window_start)` → `OVER windows' ordering … must be defined on a time attribute`,
   `window_time` 으로 바꾸면 **NullPointerException**. Flink 1.15 스트리밍 OVER 는 LAG/LEAD 미지원.
   → **윈도우 집계 뷰 self-join**(`p.window_start = c.window_start - INTERVAL '1' MINUTE`)으로 대체(실행 성공).
+ 파일 싱크는 **체크포인트마다 커밋** → `SET 'execution.checkpointing.interval' = '10s';` 선행 필수.

### IAM 페더레이션 (실측)
- **SAML provider 는 IdP 접근성을 검사하지 않는다** — 존재하지 않는 도메인 메타데이터로도 생성된다.
  `ValidUntil` 은 자동으로 +100년.
- **OIDC provider 는 issuer 를 실제 조회한다** — 사설 Keycloak(`*.local`)이면 `InvalidInput` 으로 실패.
  → **VPC 내부 Keycloak 이면 SAML 경로가 정답.**
- MSK Maven 아티팩트: `software.amazon.msk:aws-msk-iam-auth:1.1.6` 수락, `flink-sql-connector-kafka:1.15.4` 는 거부(→ `flink-connector-kafka`).

## 계정 최종 상태 (전 리전 스윕)

- 검증용 리소스 **잔재 0**. Macie 는 원래대로 **미활성** 복원.
- **잔여 0** — Lambda@Edge 복제본도 회수되어 `lab-edge-resize2/3` + `lab-edge-role` 까지 전부 삭제 완료.
  (Lambda@Edge 는 배포에서 association 을 떼고 배포를 지운 뒤 **복제본 회수까지 기다려야** 삭제된다 — 그 전엔 `InvalidParameterValueException: … because it is a replicated function`.)
- `apdev-*`(task3 연습 인프라)는 손대지 않았다.

## 3차 — GHA 실계정 E2E + IdC 한계 확인

| 케이스 | 결과 | 확인 내용 |
|---|---|---|
| **cicd 01** GHA→ECR→ECS | ✅ **live E2E** | 실제 repo `ninejuan/lab-gha`(검증 후 정리) + `ap-northeast-1`. OIDC assume → ECR push(git SHA) → taskdef `lab-gha:1`→**`:2`** → 롤링 `COMPLETED` → `curl http://<task-ip>:8080/` → **`lab-gha v1`** |
| **cicd 03** GHA OIDC | ✅ live E2E | `assumed-role/lab-gha-deploy/GitHubActions` 실제 발급 |
| **keycloak-sso 03** IdC + 외부 IdP | ⛔ 불가 확인 | org 멤버 계정은 IdC 인스턴스 생성 불가 + 조직 인스턴스 접근 거부 |

### ★★ GitHub OIDC `sub` 클레임에 불변 ID 가 들어간다 (이번 세션 최대 발견)

워크플로 안에서 JWT 를 디코드해 실제 클레임을 확인한 결과:
```
sub        = repo:ninejuan@79080468/lab-gha@1341682700:ref:refs/heads/main
repository = ninejuan/lab-gha
aud        = sts.amazonaws.com
```
문서·예제가 쓰는 `repo:OWNER/REPO:ref:refs/heads/main` 형식이 **아니다**. `OWNER@<id>/REPO@<id>` 로 숫자 ID 가 끼어든다.
`StringEquals` 로 옛 형식을 고정한 trust policy 는 **절대 매칭되지 않고**, 증상은
`configure-aws-credentials` 가 **~2분간 12회 재시도 후** `Not authorized to perform sts:AssumeRoleWithWebIdentity` 한 줄뿐이라 원인 파악이 어렵다.

**해결**(양쪽 형식 커버 + `repository` 로 조임) → 바꾸자마자 assume 성공:
```json
"StringEquals": {"…:aud":"sts.amazonaws.com", "…:repository":"OWNER/REPO"},
"StringLike":   {"…:sub":"repo:OWNER*/REPO*:ref:refs/heads/main"}
```
진단 스텝(워크플로에서 JWT 디코드)은 `recipes/topics/cicd/cases/03-oidc/README.md` 에 넣어뒀다.

### 그 밖에 실행으로 잡은 것
- **`--force-new-deployment` 로는 새 이미지가 안 나간다** — 같은 taskdef 로 재시작일 뿐.
  `describe-task-definition` → image 교체 → `register-task-definition` → `update-service --task-definition` 이 정답.
  (기존 `deploy.yml` 이 `--force-new-deployment` 였다 → 수정)
- `register-task-definition` 은 describe 응답의 읽기전용 필드(`taskDefinitionArn`, `revision`, `status`,
  `requiresAttributes`, `compatibilities`, `registeredAt/By`, `deregisteredAt`)를 제거해야 받는다(`render_td.py`).
- 배포 role 에 **`iam:PassRole`**(execution/task role 대상) 없으면 `register-task-definition` 이 거부된다.
- **AWS 는 GitHub OIDC trust 에 `sub`/`job_workflow_ref` 조건이 없으면 정책 자체를 거부**한다
  (`MalformedPolicyDocument … which is not scoped to all`). `aud` 만으로는 못 만든다.
- `token.actions.githubusercontent.com:repository` 도 조건 키로 **수락**된다.
- 정책 JSON heredoc 에서 `$ACCT:role/...` → zsh `:r` modifier 로 ARN 이 깨져 `The policy failed legacy parsing`. **`${ACCT}`** 필수(또 발생).

## 최종 계정 상태 (3차 검증 후 전 리전 스윕)

- **검증 리소스 잔재 0.** ECS/ECR/VPC/IAM role/GitHub OIDC provider 전부 삭제 확인.
- 남아 있는 건 `apdev-*`(task3 연습 인프라)와 계정에 원래 있던 것들뿐. Macie 미활성, SAML provider 0개.
- GitHub `ninejuan/lab-gha`(private) 도 **삭제 완료**(`gh repo delete`). 검증 산출물은
  `recipes/topics/cicd/cases/01-gha-ecs/`(deploy.yml·render_td.py·Dockerfile·app.py·teardown.sh)에 남겼다.
  → **AWS·GitHub 양쪽 모두 잔재 0.**

---

# 2026-08-21 4차 — recipes/aws 공백 케이스 라이브 검증 (진행 중 기록)

## 확인 완료

| 카드/케이스 | 리전 | 결과 |
|---|---|---|
| `iam/policy-documents.md` trust 4종 | 글로벌 | ✅ EC2/ExternalId/MFA/ECS trust 전부 `create-role` 통과 |
| 〃 permission 3종 | 〃 | ✅ Access Analyzer `validate-policy` — `p-s3`/`p-boundary` 클린, `p-cond` 는 `SECURITY_WARNING PASS_ROLE_WITH_STAR_IN_RESOURCE` |
| 〃 permission boundary | 〃 | ✅ `put-role-permissions-boundary` → `PermissionsBoundaryType: Policy` 확인 |
| `dynamodb.md` F resource policy | us-east-2 | ✅ `put-resource-policy` RevisionId 반환 |
| `lambda.md` F layer/VPC/동시성 | us-east-2 | ✅ layer 코드 실제 실행(`"hello skills from layer"`), VPC 부착, 예약동시성 5, 프로비저닝 동시성 v1 |
| `eventbridge.md` D custom bus | us-east-2 | ✅ 전용 버스 + rule → CW Logs 3건 도착(전체 envelope 확인) |
| 〃 archive/replay | 〃 | ✅ archive EventCount 0→**3**(90초 뒤), replay `COMPLETED` + `EventLastReplayedTime` 기록 |
| `cloudwatch.md` E EMF | us-east-2 | ✅ 로그 3줄 → `LabEMF` 네임스페이스에 `OrderCount`/`Latency` 생성, **Sum=21, Max=7** |
| `s3.md` E 이벤트 알림 | us-west-1 | ✅ prefix `inbox/` + suffix `.json` 필터 정확 동작(`inbox/x.json` 만 수신, `other/y.txt` 무시) |
| 〃 E 교차리전 복제 | us-west-1→us-west-2 | ✅ `ReplicationStatus PENDING→COMPLETED`, 대상에 `REPLICA` 도착 |
| 〃 E Object Lock | us-west-1 | ✅ GOVERNANCE 1일, 삭제 시 `AccessDenied because object protected by object lock`, `--bypass-governance-retention` 로는 삭제 |
| `ecr.md` D pull-through cache | us-west-1 | ✅ 룰 생성 → `docker pull` 로 `labpub/docker/library/busybox` **repo 자동 생성 + 캐시** |
| `acm.md` A DNS 검증 | us-east-1 | ✅ `PENDING_VALIDATION` + 검증 CNAME(`_xxx.lab-skills.dev` → `_yyy.acm-validations.aws`) |
| 〃 B 와일드카드/SAN | us-west-1 | ✅ `*.lab-skills.dev` + SAN 2개, 도메인별 검증상태 조회 |
| `route53/record-sets.md` | ca-central-1 | ✅ A/AAAA/CNAME/MX/TXT/SRV/CAA + weighted·latency·failover(헬스체크)·geo·multivalue 전종 UPSERT |
| `route53.md` B NS 하위 위임 | 〃 | ✅ 부모 존에 `dig +norecurse` → AUTHORITY 에 자식 NS 4개(referral), 자식 NS 직접 조회 → `203.0.113.7` |
| 〃 F PHZ 없이 split-view | 〃 | ✅ 퍼블릭 존이 사설 IP `10.92.1.99` 반환 |
| 〃 E Resolver | 〃 | ✅ inbound(IP 2개 ATTACHED) + outbound `OPERATIONAL`, FORWARD 룰 `onprem.local` + VPC 연결 `COMPLETE` |
| `kinesis.md` A Data Streams | 〃 | ✅ put-records 10건 → get-records 10건 그대로 소비, 보존 24→48h |
| `ecs.md` E ECS Exec | eu-central-1 | ✅ `execute-command` 로 컨테이너 내부 실행 — hostname/`uid=0(root)`/`42` |
| `glue/` B ETL Job | ap-southeast-2 | ✅ Glue 4.0 job SUCCEEDED → `parquet/event_type=click|view/` 스노피 파케이 산출 |
| `backup.md` B 온디맨드 백업 | eu-central-1 | ✅ backup job `COMPLETED`, 복구지점 생성 |

## 이번에 새로 잡은 함정

- **EventBridge 아카이브는 이벤트 반영이 늦다(실측 ~90초)** — 발행 직후 replay 하면 아카이브가 비어 있어
  replay 가 `COMPLETED` 로 끝나도 **아무것도 재생되지 않는다**(`EventLastReplayedTime: None`). EventCount 를 먼저 확인할 것.
- **S3 알림을 걸면 `s3:TestEvent` 가 먼저 한 건 들어온다** — 첫 `receive-message` 가 이걸 가져가므로
  실제 객체 이벤트가 없다고 오해하기 쉽다. 큐를 끝까지 비우면서 확인할 것.
- **`sqs set-queue-attributes --attributes Policy={json}` shorthand 는 또 실패한다** → `--attributes file://attrs.json`
  (`{"Policy": "<정책 JSON 문자열>"}` 형태). 이번 세션에서 두 번째로 밟은 함정.
- **`example.com` 으로는 ACM 인증서를 못 받는다**(IANA 예약) — `Status: FAILED`, 검증 레코드도 안 나온다. 실도메인/다른 도메인으로.
- **예약 동시성은 `get-function-configuration` 에 안 나온다** — `ReservedConcurrentExecutions` 가 `null` 로 보인다. `get-function-concurrency` 를 써야 한다.
- **Kinesis 스트림 변경 작업은 직렬화해야 한다** — `increase-stream-retention-period` 직후 `update-shard-count` 하면
  `ResourceInUseException: … not ACTIVE, instead in state UPDATING`. ACTIVE 대기 후 다음 작업.
- **DDB `put-resource-policy` 직후 `get-resource-policy` 는 `PolicyNotFoundException`** — 최종적 일관성. 재시도 필요.
- ECS Exec 은 **task role** 에 `ssmmessages:*` 4종이 필요하고, `enableExecuteCommand` 는 run-task/서비스 쪽 플래그다.
