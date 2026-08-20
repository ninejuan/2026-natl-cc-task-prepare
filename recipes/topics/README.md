# 2과제 토픽 플레이북 (21토픽)

2과제 = 제공 모듈 중 **4개**를 골라 출제(각 7.5점, 총 30점). 모듈은 서로 독립(다른 리전, 리소스 이름 중복 금지). 한 모듈 60분 내 풀이. 채점 항목당 ≤3분.

**커버리지 근거**: 확보한 2과제 가이드 2종(2025 14모듈 + 2026 13모듈) 합집합 = **21토픽**. 가이드가 `"~ 등을 예로 들 수 있습니다"` 로 케이스 다양성을 명시 → 각 토픽에 여러 케이스.

## 트리거 문구 → 토픽 결정 트리

| 문제에 보이면 | 토픽 |
|---|---|
| service network, VPC 간 서비스 연결, Lattice | [vpc-lattice](vpc-lattice/) |
| Network Firewall, egress 필터, Suricata, 도메인 차단 | [network-firewall](network-firewall/) |
| RDS Proxy, Data API, IAM DB 인증, 커넥션 풀 | [rds-connection](rds-connection/) |
| Client VPN, 로컬→VPC 내부 접근, VPN 후 DB | [client-vpn](client-vpn/) |
| PII 탐지, Macie, Access Point, 버킷 보호 | [storage-protect](storage-protect/) |
| ECS 로그 중앙수집, FireLens, awslogs, OpenSearch | [ecs-logging](ecs-logging/) |
| SQS, 메시지 큐, FIFO, DLQ, spike 완충 | [message-queue](message-queue/) |
| 대시보드, 알람, 이상치, ECS/ALB 모니터링 | [monitoring](monitoring/) |
| EFS 접근제어, 파일시스템 보안, access point | [efs-security](efs-security/) |
| WAF, SQLi/XSS 차단, rate limit, 봇 | [waf](waf/) |
| GitHub Actions, CI/CD, ArgoCD, 자동 배포 | [cicd](cicd/) |
| DynamoDB, GSI/LSI, DAX, DocumentDB, NoSQL | [nosql](nosql/) |
| CloudFront, OAC, 엣지 함수, 이미지 리사이징, 캐싱 | [cdn](cdn/) |
| Step Functions, 수집→처리→저장, 워크플로, No-Lambda | [workflow](workflow/) |
| SG 위반 감지·복구, 자동화, governance | [cloud-governance](cloud-governance/) |
| Managed Flink, Zeppelin SQL, 실시간 분석, 윈도우 | [realtime-analytics](realtime-analytics/) |
| MSK, Kafka, 이벤트 스트리밍, 토픽 | [msk](msk/) |
| EKS HPA/KEDA/Karpenter, Pod 스케일링 | [eks-scaling](eks-scaling/) |
| Loki, Grafana, LogQL, 컨테이너 로그 대시보드 | [container-logging](container-logging/) |
| Keycloak, SAML SSO, 특정 IAM Role 로그인 | [keycloak-sso](keycloak-sso/) |
| POST/GET API 직접 구현, Lambda REST | [rest-api](rest-api/) |

## 출제 이력 (재현 금지 — 규칙성 근거)

- **2024 추가과제**: Client VPN(→ private RDS), Keycloak SAML SSO(2 role)
- **2025 추가과제**: Serverless Inventory(SFN+APIGW+DDB, 컴퓨팅 금지) → [workflow](workflow/) No-Lambda 케이스

## 검증 강도

각 토픽 README 하단 표에 케이스별 검증 강도(✅ live / 스크립트 / 문서). 신규·고가(Lattice/Firewall/RDS/VPN)는 실계정 생성→검증→즉시 삭제. 상세는 `../../verify/RESULTS.md`.

## 공통 규칙 (전 토픽)

- **리전 격리**: 모듈마다 다른 리전, 전용 VPC(리소스 재사용 금지).
- **이름/태그**: 채점이 이름·태그로 식별(CloudFront 는 Comment). 대소문자 정확히.
- **≤3분 채점**: 스케일링·로그·복구는 3분 내 관측되게(polling 짧게).
- **반칙 자가검사**: 각 토픽 README + `../../FIELD-RUNBOOK.md`. 금지 조항은 채점이 관찰로 잡는다.
- **채점자 문체 검증 블록**: `aws --query` + `jq` + `kubectl -o jsonpath` + `curl`(→ `../../_analysis/MARK-PATTERNS.md`).
