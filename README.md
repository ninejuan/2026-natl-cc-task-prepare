# 2026 전국기능경기대회 클라우드컴퓨팅 — 추가과제 스피드런

추가과제는 경기 시작 10분 전에 공개된다. 미리 코드를 못 짜오고, 현장에서 AI 툴이 차단된다.
그래서 이 레포는 **문제 문구 → 카드 → 복붙**으로 끝나게 만든 레시피 카탈로그다.

**급하면 여기부터:** [`FIELD-RUNBOOK.md`](FIELD-RUNBOOK.md) (현장 절차·자가채점·체크리스트) · [`WAIT-TIMES.md`](WAIT-TIMES.md) (착수 순서) · [`ALL.md`](ALL.md) (전체 병합본, Ctrl+F용)

## 규약

모든 카드는 파라미터 2개만 쓴다. 현장에서 한 번 export하고 그대로 복붙한다.

```bash
export P=<비번호>          # 리소스 이름에 들어가는 비번호
export R=ap-northeast-2    # 해당 항목/모듈이 지정한 리전
```

카드 포맷: `언제 쓰나` → `소요시간` → `전제` → `5분 컷(CLI)` → `Terraform` → `검증` → `함정`
`검증` 블록은 실제 채점 스크립트와 같은 문체(`aws --query` + `jq` + `kubectl jsonpath` + `curl`)로 써서 자가채점에 그대로 쓴다. 근거는 [`_analysis/MARK-PATTERNS.md`](_analysis/MARK-PATTERNS.md).

상태 표시: `✓` 실검증 완료 · `✍` 작성됨(미검증) · `—` 미작성

---

## 결정 트리 — 문제에 이 단어가 보이면

### 네트워크 / 기반

| 문구 키워드 | 카드 | 상태 |
|---|---|---|
| VPC, 서브넷, NAT, 라우팅 테이블, Flow Log | `recipes/base/vpc-fast.md` | — |
| VPC Endpoint, 인터넷 경유 없이, PrivateLink | `recipes/base/vpc-fast.md` | — |
| Security Group, 인바운드/아웃바운드 | `recipes/base/security-group.md` | — |
| EC2, user data, systemd 서비스, 앱 배포 | `recipes/base/ec2-userdata.md` | — |
| Bastion, CloudShell VPC 환경, 채점용 쉘 | `recipes/base/bastion-cloudshell-vpc.md` | — |
| IAM Role, Assume, External ID, 최소권한 | `recipes/base/iam-basics.md` | — |
| KMS, CMK, 암호화, 키 회전, 멀티리전 키 | `recipes/base/kms.md` | — |
| Network Firewall, Egress 필터링, DNS 필터링 | `recipes/topics/secure-networking.md` | — |
| Client VPN, 로컬에서 VPC 내부 접근 | `recipes/topics/vpn.md` | — |
| VPC Lattice, Peering 없이 서비스 연결 | `recipes/topics/vpc-lattice.md` | — |
| Transit Gateway, Peering | `recipes/aws/tgw-peering.md` | — |

### DNS / CDN / 엣지

| 문구 키워드 | 카드 | 상태 |
|---|---|---|
| Route53, Hosted Zone, NS 위임, 라우팅 정책, 헬스체크 | `recipes/aws/route53.md` | — |
| ACM, 인증서, HTTPS, 커스텀 도메인 | `recipes/aws/acm.md` | — |
| CloudFront, 캐싱, OAC, behavior, VPC Origin | `recipes/aws/cloudfront.md` | — |
| CloudFront Functions, Lambda@Edge, 헤더 변경, 이미지 리사이징 | `recipes/topics/cdn.md` | — |
| WAF, 공격 차단, rate limit, managed rule | `recipes/topics/waf.md` | — |
| S3 정적 호스팅, index.html, 버킷 정책 | `recipes/aws/s3.md` | — |

### 컨테이너 / 쿠버네티스

| 문구 키워드 | 카드 | 상태 |
|---|---|---|
| Deployment, Service, probe, graceful shutdown, topologySpread | `recipes/k8s/workload-basics.md` | — |
| Ingress, ALB 연결, TargetGroupBinding | `recipes/k8s/ingress-alb.md` | — |
| Gateway API, GatewayClass, HTTPRoute | `recipes/k8s/gateway-api-alb.md` | — |
| Service type LoadBalancer, NLB | `recipes/k8s/nlb-service.md` | — |
| HPA, Karpenter, KEDA, 스케일 아웃 | `recipes/k8s/scaling-hpa-keda-karpenter.md` | — |
| EBS/EFS CSI, PVC, StatefulSet | `recipes/k8s/storage-csi.md` | — |
| IRSA, Pod Identity, ServiceAccount, Access Entry | `recipes/k8s/identity-irsa-podidentity.md` | — |
| 이미지 태그 제한, 필수 라벨 강제, 파드 생성 차단 | `recipes/k8s/admission-policy.md` | — |
| NetworkPolicy, 파드 간 통신 제한 | `recipes/k8s/networkpolicy.md` | — |
| RBAC, Role, ClusterRoleBinding | `recipes/k8s/rbac.md` | — |
| ConfigMap, Secret, Secrets Manager 연동 | `recipes/k8s/config-secrets.md` | — |
| Job, CronJob, PDB | `recipes/k8s/jobs-cron-pdb.md` | — |
| 클러스터를 하나 더, 추가 EKS | `recipes/k8s/cluster-quickstart.md` | — |
| 파드가 안 뜬다 / 진단 | `recipes/k8s/kubectl-triage.md` | — |
| ECS, Task Definition, Fargate, FireLens | `recipes/k8s/ecs-equivalents.md` | — |
| ECR, 이미지 스캔, 태그 불변, 라이프사이클 | `recipes/aws/ecr.md` | — |

### 관측 / 로깅

| 문구 키워드 | 카드 | 상태 |
|---|---|---|
| Prometheus, Grafana, 대시보드 패널 | `recipes/k8s/prom-grafana.md` | — |
| Loki, LogQL, 로그 쿼리 | `recipes/k8s/loki.md` | — |
| Fluent Bit, CloudWatch Logs 전송, 로그 제외 | `recipes/k8s/fluentbit-cw.md` | — |
| OpenTelemetry, ADOT | `recipes/k8s/otel.md` | — |
| CloudWatch 대시보드, 알람, Log Insights, EMF | `recipes/aws/cloudwatch-o11y.md` | — |
| OpenSearch, Kibana | `recipes/aws/opensearch.md` | — |
| ECS 로그 중앙집중, awslogs, FireLens | `recipes/topics/ecs-logging.md` | — |
| X-Ray, 트레이싱 | `recipes/aws/xray.md` | — |

### 데이터

| 문구 키워드 | 카드 | 상태 |
|---|---|---|
| DynamoDB, GSI/LSI, TTL, Streams, PITR, DAX | `recipes/aws/dynamodb.md` | — |
| DocumentDB, MongoDB 호환 | `recipes/aws/documentdb.md` | — |
| RDS, Aurora, RDS Proxy, Data API, IAM 인증 | `recipes/topics/rds-connection.md` | — |
| EFS, 파일시스템 접근 제어 | `recipes/topics/efs-security.md` | — |
| S3 Access Point, Macie, PII 탐지 | `recipes/topics/storage-protect.md` | — |
| Managed Flink, 실시간 분석, Notebook SQL | `recipes/topics/realtime-analytics.md` | — |
| MSK, Kafka, Producer/Consumer | `recipes/topics/msk.md` | — |
| Athena, Glue, 쿼리 | `recipes/aws/athena-glue.md` | — |
| AWS Backup, 백업/복원 | `recipes/aws/backup.md` | — |

### 서버리스 / 이벤트

| 문구 키워드 | 카드 | 상태 |
|---|---|---|
| Lambda, 함수 작성, layer, Function URL | `recipes/aws/lambda.md` | — |
| API Gateway, REST API, Service Proxy 통합, mapping template | `recipes/aws/apigateway.md` | — |
| POST/GET API를 직접 구현 | `recipes/topics/rest-api.md` | — |
| Step Functions, State Machine, 워크플로우 | `recipes/topics/workflow.md` | — |
| SQS, SNS, EventBridge, 메시지 큐 | `recipes/topics/message-queue.md` | — |
| Config, SSM, 자동 복구, 정책 위반 감지 | `recipes/topics/cloud-event-handling.md` | — |
| Secrets Manager, 시크릿 회전 | `recipes/aws/secrets-manager.md` | — |

### 인증 / CI·CD

| 문구 키워드 | 카드 | 상태 |
|---|---|---|
| Keycloak, SAML, SSO, AWS 콘솔 로그인 | `recipes/topics/keycloak-sso.md` | — |
| Cognito, 사용자 풀 | `recipes/aws/cognito.md` | — |
| GitHub Actions, ArgoCD, 파이프라인, 자동 배포 | `recipes/topics/cicd.md` | — |

---

## "~하면 안 된다"가 붙어 있으면

금지 조항은 해당 카드의 `대안 경로` 절을 본다. 제출 전 `bin/mark-self.sh --foul`로 위반 여부를 확인한다.
자주 나오는 것: Lambda 금지 → `recipes/aws/apigateway.md`의 Service Proxy 통합 · Peering 금지 → `recipes/topics/vpc-lattice.md` · 프로그래밍 금지 → `recipes/topics/realtime-analytics.md`의 SQL 전용 경로.

## 헬퍼

```bash
bin/bootstrap.sh          # CloudShell/EC2에 툴 설치 (tf, kubectl, helm, eksctl, jq, yq, easy-rsa, psql, mongosh)
bin/discover.sh           # 기존 스택 리소스 ID 전수 스캔 → addon.env (1과제 추가 항목용)
bin/mark-self.sh [--foul] # 자가채점 / 금지조항 위반 검사
bin/build-all.sh          # ALL.md 재생성
```

## 배경 자료

`_task_sub_guide/` 출제가이드 (2025·2026) · `_additional_task_case/` 과거 추가과제 (재현 대상이 아니라 난이도·채점방식 캘리브레이션용) · `verify/RESULTS.md` 실검증 기록
