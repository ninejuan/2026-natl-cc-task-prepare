# 현장 운용 절차

추가과제는 **경기 시작 10분 전**(입실완료 후 대기 + 과제지 오류제기 시간)에 공개된다. 현장에서 AI 툴은 Amazon Q 외 전면 차단. 이 레포를 브라우저로 열어 복붙한다.

## 공개 직후 10분

이 시간에 코드를 쓰지 마라. **읽고, 분류하고, 오래 걸리는 걸 찾는 것**만 한다.

1. **(2분) 전체 훑기.** 항목/모듈 개수, 각 항목의 **리전**과 **고정 리소스 이름**을 여백에 옮겨 적는다. 2과제는 모듈마다 리전이 다르다.
2. **(2분) 착수 순서 결정.** 생성이 오래 걸리는 리소스(EKS 10~15분, MSK·OpenSearch 15~30분, RDS·DocumentDB 10~20분, CloudFront·Client VPN 수 분)를 찾아 표시한다. 경기 시작하면 이것부터 던지고, 대기 중에 즉시 생성되는 것(S3·DynamoDB·Lambda·IAM·SQS·Step Functions)을 처리한다.
3. **(3분) 카드 매칭.** `README.md` 결정 트리로 각 항목 → 카드를 찾아 적는다. 매칭 안 되는 항목이 있으면 표시해 두고 그 항목에 시간을 더 배정한다.
4. **(2분) 오류제기 판단.** 과제지와 채점지가 상이한가, 물리적으로 불가능한 요구(리전에 없는 서비스 등)가 있는가. **이 시간이 지나면 이의제기 못 한다.**
5. **(1분) 금지 조항 표시.** "~할 수 없습니다 / ~는 금지합니다"에 전부 동그라미. 밟으면 관련 항목이 통째로 0점이다.

## 경기 시작 후

```
0분     가장 오래 걸리는 리소스 생성 시작 (설정 미완성이어도 던진다)
0~n분   대기 중 즉시 생성되는 것 전부 처리 (S3/DDB/Lambda/IAM/SQS/SFn/APIGW)
n분     돌아와서 느린 리소스 설정 마무리
종료 30분 전  자가채점 시작
종료 10분 전  제출 정보 정리 + 부하/테스트 중지
```

과제지가 시작 시각을 강제하지 않는다면 **항목 순서대로 풀지 마라.** 대기시간 순서로 푼다.

## 과거 사례에서 확인된 규칙

3년치 추가과제·후보과제·채점스크립트에서 일관되게 관찰된 것들.

- **채점은 관찰 가능한 상태만 본다.** CLI describe, kubectl jsonpath, curl 응답. terraform 코드나 구성 방식은 안 본다 → 콘솔로 만들어도 점수는 같다. 급하면 콘솔로 만들어라.
- **채점 스크립트는 여러 번 실행해도 같은 결과여야 한다**(출제 지침). 채점이 넣은 테스트 데이터가 쌓여도 응답이 깨지면 안 된다.
- **채점 항목당 대기 최대 3분.** 스케일링·로그 수집·자동복구는 3분 내 관측 가능하게 간격을 짧게 잡아라.
- **"편법 금지" 조항이 반드시 붙는다.** hosts 변조, 로컬 서버 설치, 우회 DNS 등을 명시적으로 막고 채점에서 검사한다. 정공법만.
- **이름·태그·리전·대소문자가 곧 점수다.** 식별 실패는 그 항목만 0점이 아니라 뒤따르는 항목까지 연쇄로 0점이 된다.
- **비번호가 리소스 이름에 들어간다.** S3 버킷처럼 글로벌 유니크가 필요한 곳, IAM External ID, Grafana 계정 등. 현장 배정이므로 `export P=<비번호>` 한 번 하고 전부 `$P`로 조립.
- **1과제 추가는 기존 스택 위에 얹는 것과 독립 신설이 섞인다.** 기존 스택 위라면 `bin/discover.sh`로 기존 리소스 ID를 먼저 확보한다. 메인 terraform을 재-apply하지 말고 `tf-addon/`이나 CLI로 얹는다.
- **미사용 리소스는 감점.** 만들다 실패한 잔재, 다른 리전에 남은 것을 지운다.

## 자가채점

```bash
export P=<비번호>
bin/mark-self.sh            # 카드 검증 블록 일괄 실행
bin/mark-self.sh --foul     # 금지 조항 위반 여부만 검사
```

`--foul`이 검사하는 것:

| 금지 조항 | 검사 | 기대값 |
|---|---|---|
| Lambda/컴퓨팅 금지 | `aws lambda list-functions --query Functions` | `[]` |
| Private Hosted Zone 금지 | `aws route53 list-hosted-zones --hosted-zone-type PrivateHostedZone` | 없음 |
| VPC Peering / TGW 금지 | `describe-vpc-peering-connections`, `describe-transit-gateways` | 없음 |
| 광범위 IAM 권한 금지 | 정책 문서에 `"Action": "*"` / `"Principal": "*"` | 없음 |
| hosts 변조 | `cat /etc/hosts` | 해당 도메인 없음 |

## 제출 전 체크리스트

- [ ] 과제지가 지정한 **이름**이 정확히 일치하는가 (대소문자 포함)
- [ ] 각 항목이 지정된 **리전**에 있는가
- [ ] `Name` 태그를 붙였는가 — 특히 **CloudFront는 `Comment` 필드까지** (채점이 `Comment`로 배포를 찾는다)
- [ ] EC2가 **running** 상태인가 (`instance-state-name=running` 필터에 걸려야 한다)
- [ ] 노드에 과제지가 요구한 **라벨**이 박혀 있는가 (`kubectl get nodes -l ...`이 0개면 0점)
- [ ] CloudShell에서 **클러스터 엔드포인트에 닿는가** (private-only면 VPC CloudShell 필요)
- [ ] 앱이 systemd로 **enable** 돼 있는가 (`systemctl is-active && is-enabled`로 검사하는 항목이 있다)
- [ ] 실행 중인 **부하 테스트를 중지**했는가
- [ ] **미사용 리소스**를 지웠는가 (타 리전 포함)
- [ ] `bin/mark-self.sh --foul` 통과
- [ ] 제출 양식에 적을 값(엔드포인트 URL, Keycloak 주소 등)을 적어뒀는가

## ★ 조용히 점수를 깎는 함정 (전부 실계정에서 당해본 것)

에러가 안 나거나, 엉뚱한 에러가 나서 원인을 못 찾는 것들만 모았다. 막히면 여기부터 본다.

**배포했는데 채점이 옛날 걸 본다**
- **CloudFront**: 오리진만 바꾸고 `create-invalidation` 안 하면 캐시가 계속 옛 내용을 준다(실측: 무효화 전 v1 / 후 v2).
- **ECS**: `update-service --force-new-deployment` 는 **같은 taskdef 로 재시작**일 뿐이다. 새 이미지를 배포하려면
  `describe-task-definition` → image 교체 → `register-task-definition` → `update-service --task-definition FAMILY:REV`.

**설정했는데 "설정 안 된 것처럼" 보인다 (조회 API 를 잘못 고른 것)**
- `aws dynamodb describe-table --query 'GlobalSecondaryIndexes[]'` → 조용히 `null`. **`Table.` 접두사** 필요.
- Lambda 예약 동시성은 `get-function-configuration` 에 **안 나온다**. `get-function-concurrency` 를 써라.
- DDB `put-resource-policy` 직후 `get-resource-policy` 는 `PolicyNotFound` (최종적 일관성) → 재시도.
- EventBridge 아카이브는 이벤트 반영이 **~90초 늦다**. 바로 replay 하면 `COMPLETED` 인데 아무것도 안 나온다.

**CLI 문법 함정 (에러 메시지가 원인을 안 알려준다)**
- **zsh 에서 `"$ACCT:role/..."` 는 ARN 이 깨진다**(`:r` modifier). `${ACCT}` 중괄호 필수.
  증상: `MalformedPolicyDocument: The policy failed legacy parsing`.
- `sqs set-queue-attributes --attributes Policy={json}` / `send-message-batch --entries Id=..,MessageBody={json}`
  → shorthand 는 JSON 을 못 받는다. **`file://`** 로.
- `configservice put-configuration-recorder` shorthand 는 bool 을 문자열로 보낸다 → **JSON 파일 필수**.
- 카드의 `_comment`/`_usage` 키가 든 JSON 을 `file://` 로 바로 넣으면 `Unknown parameter`. **jq 로 `_` 키 제거** 후 사용.
- `aws deploy get-deployment --query '[status,deploymentOverview]' --output text` → `'str' object has no attribute 'items'`.

**인증/네트워크가 조용히 막힌다**
- **GHA OIDC**: 토큰의 `sub` 가 `repo:OWNER@<id>/REPO@<id>:ref:...` 형태(불변 ID 포함)라
  문서 예제의 `StringEquals "repo:OWNER/REPO:ref:..."` 는 **절대 안 맞는다**. `StringLike "repo:OWNER*/REPO*:..."` 로.
  증상은 2분 재시도 후 `Not authorized to perform sts:AssumeRoleWithWebIdentity` 한 줄뿐.
- **Client VPN**: 서버 인증서 CN 이 FQDN 이 아니면 endpoint 생성부터 거부(ACM DomainName=null).
  `.ovpn` 에 `dhcp-option DNS` 는 **없다**(연결 시 서버가 push) — 파일만 보고 오해하지 말 것.
- **IAM Identity Center** 는 org 멤버 계정에서 **생성 불가**(인스턴스 quota) + 조직 인스턴스 접근 거부.
  → Keycloak 연동은 **IAM SAML 페더레이션**으로. SAML 은 IdP 접근성을 검사 안 해서 **사설 Keycloak 도 된다**
  (OIDC 는 issuer 를 실제로 조회해서 사설이면 실패).
- **Amazon MQ**: RabbitMQ 는 `mq.t3.micro` **미지원**(최소 `mq.m7g.medium`). ActiveMQ 는 퍼블릭이어도
  **VPC 보안그룹을 타므로** 61617/5671/61614/8883/8162 를 열어야 붙는다(RabbitMQ 는 SG 안 탄다).
- **Lambda@Edge**: `X-Edge-*` 접두사 헤더 추가 금지, 응답 객체를 **새로 만들지 말고** 받은 `response` 를 수정,
  **환경변수 사용 불가**, OAC 오리진엔 `AllViewerExceptHostHeader` 오리진요청정책(‘AllViewer’ 는 Host 전달로 S3 403).
- **Managed Flink Studio**: CLI/TF 로 만들면 커넥터가 `datagen/filesystem/blackhole/print` 4개뿐이다.
  Kinesis/Kafka 소스는 `update-application` 으로 Maven 아티팩트를 넣어야 한다(앱 정지 상태에서만).

**시간이 오래 걸려서 채점 전에 못 끝내는 것**
- OpenSearch 도메인 생성 **~50분**, MSK provisioned **~60분**(serverless ~10분), MQ 브로커 ~20분,
  Client VPN association 수 분, CloudFront 배포/삭제 각 수 분.
  → 이런 건 **먼저 만들어 놓고** 나머지를 한다.
- Config rule 은 리소스 discovery 에 수 분 걸린다. **3분 안에 탐지·조치를 보여야 하면 EventBridge→Lambda** 경로.

**EKS/CNCF 에서 조용히 죽는 것 (전부 실제 클러스터에서 당했다)**
- **EKS 에 기본 StorageClass 가 없다.** `gp2` 가 보이지만 default 표시가 없고 in-tree 프로비저너라
  동작하지 않는다 → `storageClassName` 생략 PVC 는 **영원히 Pending**. helm 차트 태반이 여기 걸린다.
  처치: `kubectl annotate sc ebs-gp3 storageclass.kubernetes.io/is-default-class=true`
- **t3.medium 은 파드 17개가 한계.** CPU/메모리가 텅 비어도 `Too many pods` 로 스케줄이 막힌다.
  DaemonSet 만으로 6~8개가 나간다. prefix delegation **만으로는 안 늘어난다** —
  노드그룹에 `maxPodsPerNode: 110` 을 같이 줘야 한다.
- **NetworkPolicy 잔재가 다른 모든 것을 죽인다.** `default-deny-ingress` 하나로
  Prometheus 스크레이프(`up=0`)·Istio 게이트웨이가 전멸한다. 검증 끝나면 `kubectl -n <ns> delete netpol --all`.
- **NetworkPolicy/Calico/Cilium 의 포트는 전부 컨테이너 포트.** Service 포트를 적으면
  허용하려던 트래픽까지 전부 막힌다.
- **NLB 는 cross-zone 이 기본 꺼짐.** 백엔드 파드가 1개면 요청의 2/3 이 타임아웃한다.
  DNS 라운드로빈이라 "가끔 되는데?" 로 시간을 버린다 →
  `service.beta.kubernetes.io/aws-load-balancer-attributes: load_balancing.cross_zone.enabled=true`
- **Kyverno Enforce 정책을 클러스터 전역에 걸면 애드온 설치가 전부 막힌다.**
  autogen 규칙이 Deployment 에도 적용돼 `helm install` 과 `rollout restart` 까지 거부된다.
  시스템/애드온 네임스페이스를 반드시 `exclude`. 그리고 **mutate 는 되돌아가지 않는다**(스펙에 기록됨).
- **helm 은 릴리스 이름을 ServiceAccount 이름에 붙인다.** IRSA 어노테이션을 엉뚱한 SA 에 달면
  컨트롤러가 조용히 노드 인스턴스 role 로 폴백한다. `kubectl get pod -o jsonpath='{.items[0].spec.serviceAccountName}'`
- **helm values 의 오타·없는 값은 오류가 안 난다.** 실제로 Loki `deploymentMode: Monolithic`(없는 값)로
  파드가 0개 뜨고도 "설치 성공" 이 나왔다. 설치 후 반드시 `kubectl get sts,deploy,pod` 로 실물을 확인한다.
- **ArgoCD 는 `SYNC` 를 봐라.** 브랜치 이름이 틀리면 `SYNC=Unknown` 인데 `HEALTH=Healthy` 로 보인다.
  확신이 없으면 `targetRevision: HEALTH` 가 아니라 **`HEAD`**.
- **CNI 정책 엔진(Calico/Cilium)을 바꾸면 노드를 교체하라.** `helm uninstall` 로는 노드가 안 깨끗해지고,
  다음 CNI 가 통째로 고장난다. Cilium 제거 후 `05-cilium.conflist` 가 남으면 **새 파드가 아예 안 뜬다**
  (복구는 hostNetwork 특권 DaemonSet 으로 파일 삭제 → 그래도 안 되면 노드 교체).
- **vpc-cni 를 `update-addon` 으로 고칠 때 `--service-account-role-arn` 을 빼지 마라.**
  aws-node 의 IRSA 어노테이션이 지워져 CrashLoopBackOff → 새 파드가 IP 를 못 받아 클러스터가 마비된다.

## 참고

- 채점 방식 상세: `_analysis/MARK-PATTERNS.md`
- 카드 찾기: `README.md`
