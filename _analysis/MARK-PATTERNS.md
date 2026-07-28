# 채점 스크립트가 실제로 검사하는 방식

출처: `task1/*/taskfiles/mark.sh` 4개 + `task2/*/taskfiles/mark[1-4].sh` 12개 전수 분석.
용도: 카드 `검증` 블록을 이 문체로 쓴다. 채점자가 보는 것만 만들면 만점, 그 외는 낭비.

## 채점 환경

CloudShell에서 실행. 필수 커맨드는 `aws` `jq` `curl` `kubectl`뿐 — 채점자는 terraform도 helm도 안 쓴다.
스크립트 공통 헤더: `set -u`, `export AWS_PAGER=""`, `exec > >(tee result.txt) 2>&1`.
EKS는 `aws eks update-kubeconfig` 후 kubectl. **CloudShell에서 클러스터 엔드포인트가 닿아야 한다** (Private-only 클러스터면 VPC 환경 CloudShell 필요 — 후보 00007 유의사항 14번이 이걸 명시).

## 핵심 패턴 1 — 이름/태그로 찾고, ID로 파고든다

거의 모든 항목이 이 3단 구조다.

```bash
VPC_ID=$(aws ec2 describe-vpcs --filters Name=tag:Name,Values=skills-ceh-vpc --query 'Vpcs[0].VpcId' --output text)
aws ec2 describe-subnets --filters Name=vpc-id,Values="$VPC_ID" --query 'Subnets[].{...}' --output table
```

**이름 하나 틀리면 그 뒤 전부 연쇄 실패한다.** `""`나 `None`이 나오면 이후 항목이 "식별 실패"로 줄줄이 0점. 이름·태그가 최우선 검증 대상.

식별 키는 리소스마다 다르다:

| 리소스 | 식별 방법 |
|---|---|
| VPC/Subnet/EC2/SG/RT/IGW/NAT | `--filters Name=tag:Name,Values=<이름>` |
| EC2 (추가) | + `Name=instance-state-name,Values=running` — **running이어야 잡힌다** |
| EKS/DynamoDB/Lambda/ECR/DocDB/Secrets | `--name` / `--table-name` / 식별자 직접 |
| ALB/TG | `aws elbv2 describe-load-balancers --names <이름>` |
| **CloudFront** | `DistributionList.Items[?Comment=='<이름>']` ← **Comment 필드** 또는 `resourcegroupstaggingapi get-resources --tag-filters Key=Name,Values=<이름>` |
| SNS | `Topics[?contains(TopicArn, ':<이름>')]` |
| VPC Lattice | `items[?name=='<이름>'].id` |
| WAF | `list-web-acls --scope CLOUDFRONT --region us-east-1` |

CloudFront에 `Comment`를 안 넣으면 채점이 배포를 아예 못 찾는다. 태그 `Name`도 같이 넣어라.

## 핵심 패턴 2 — 설정값은 `--query`로 한 방에

```bash
aws dynamodb describe-table --table-name unicorn-concert-db --query 'Table.{Billing:BillingModeSummary.BillingMode,PK:KeySchema[?KeyType==`HASH`].AttributeName|[0],GSIProj:GlobalSecondaryIndexes[0].Projection.ProjectionType,SSEKms:SSEDescription.KMSMasterKeyArn,Delete:DeletionProtectionEnabled}' --output json
```

즉 **속성 하나하나가 채점 항목**이다. 암호화 키 ARN, PITR 상태, 삭제 방지, 태그 변경 불가 여부까지 개별로 본다. 과제지가 언급한 옵션은 전부 켜라.

## 핵심 패턴 3 — kubectl은 `-o jsonpath`로 필드 지목

```bash
kubectl get deploy <name> -n <ns> -o jsonpath='liveness={.spec.template.spec.containers[0].livenessProbe.httpGet.path} graceful={.spec.template.spec.terminationGracePeriodSeconds} preStop={.spec.template.spec.containers[0].lifecycle.preStop}{"\n"}'
kubectl get serviceaccount <sa> -n <ns> -o jsonpath='{.metadata.annotations.eks\.amazonaws\.com/role-arn}'
kubectl get nodes -l karpenter.sh/nodepool=<pool>,<custom-label> -o wide
kubectl get nodepool <name> -o yaml     # CRD는 통째로 덤프해서 눈으로 본다
```

노드 **라벨**로 필터하는 케이스가 많다(`-l unicorn=app`, `-l wsc2026/node=addon`). 라벨은 노드그룹/NodePool에 반드시 박아라. Karpenter/KEDA CRD는 `-o yaml` 통째 덤프 → 필드 존재 여부로 채점.

## 핵심 패턴 4 — 기능 검증은 curl 왕복

```bash
curl -s -m 10 -w "\nhttp_code=%{http_code}\n" "http://${CLIENT_IP}:8080/health"
BID=$(curl -s -X POST "https://$CF/v1/book" -d '{...}' | jq -r .booking_id)   # POST로 넣고
curl -s "https://$CF/v1/book?booking_id=$BID" | jq .                          # GET으로 확인
curl -s -o /dev/null -w "%{http_code} %header{x-cache}\n" "https://$CF/index.html"   # 캐시 히트도 본다
```

주의할 점 둘:
- **채점이 EC2의 `PublicIpAddress`로 직접 curl한다.** 앱 EC2에 퍼블릭 IP + SG 인바운드(8080/80)가 필요한 문제도 있다. 과제지가 그렇게 쓰여 있으면 private에 숨기지 마라.
- 차단을 확인하는 항목도 있다. ALB 직접 호출이 `000`(타임아웃)이어야 통과하는 식.

## 핵심 패턴 5 — 채점이 내 리소스를 건드린다

멱등하고 파괴적이지 않은 범위에서 조작한다. 내 구성이 이걸 견뎌야 한다.

| 조작 | 어디서 |
|---|---|
| SG에 `TCP/22 from 0.0.0.0/0` 임시 추가 → 자동복구 관찰 → 다시 제거 | Cloud event handling |
| `lambda invoke`로 가짜 이벤트 주입 | 같음 |
| SQS 메시지 12개 발행 → 스케일아웃 관찰 | EKS Scaling |
| `kubectl run`으로 테스트 파드 생성 (crash-test, stress-cpu, not-ready) | Observability |
| CloudFront `create-invalidation`, `test-function` | CDN |
| ECR `docker pull` + `kubectl run`으로 이미지 검증 | Container |
| `ec2 stop-instances` 후 복구 확인 | Cloud governance |
| `ssm send-command`로 EC2 내부 상태 확인 (`systemctl is-active app`) | EC2 앱 |

→ 앱은 **systemd 서비스로 enable**해 둬야 하고(`is-active && is-enabled`), 파드는 tolerations 무시하고 뜬 테스트 파드가 있어도 정상 동작해야 한다.

## 핵심 패턴 6 — 대기

`sleep 30` / `sleep 60` / `sleep 180`, 또는 5초 간격 폴링 루프(`for I in $(seq 1 36)`).
규칙: **채점 항목당 최대 3분.** 스케일링·로그 파이프라인·자동복구는 3분 내에 관측 가능해야 한다. HPA/KEDA polling interval, Fluent Bit flush interval을 짧게 잡아라.

## 반칙 탐지 명령 (제출 전 내가 먼저 돌려본다)

| 금지 조항 | 채점이 잡는 방법 | 기대값 |
|---|---|---|
| Lambda/컴퓨팅 금지 | `aws lambda list-functions --query Functions` | `[]` |
| Private Hosted Zone 금지 | `aws route53 list-hosted-zones --hosted-zone-type PrivateHostedZone` | 없음 |
| hosts 변조 금지 | `cat /etc/hosts` | 해당 도메인 없음 |
| 로컬 서버 우회 금지 | `netstat -an \| findstr <port>` | listen 없음 |
| VPC Peering/TGW 금지 | `describe-vpc-peering-connections`, `describe-transit-gateways` | 없음 |
| IAM 광범위 권한 금지 | 정책 문서에 `"Action": "*"` / `"Principal": "*"` | 없음 |
| 미사용 리소스 | 타 리전 포함 리소스 스캔 | 없음 |

## 자주 밟는 함정

- **리전.** 2과제는 모듈마다 리전이 다르다. `--region`을 명시하지 않은 스크립트는 채점자 기본 리전을 쓴다.
- **대소문자.** 이름·태그·환경변수 전부 구분한다.
- **`Comment` 없는 CloudFront**, **`Name` 태그 없는 리소스** → 식별 실패 = 0점.
- **노드 라벨 누락** → `kubectl get nodes -l ...`이 0개 → 0점.
- **EC2 stopped** → `Values=running` 필터에 안 걸림 → 0점.
- **채점 스크립트가 여러 번 실행돼도 같은 결과여야 한다** (출제 지침). 즉 채점이 넣은 테스트 데이터가 쌓여도 응답이 깨지지 않아야 한다.
