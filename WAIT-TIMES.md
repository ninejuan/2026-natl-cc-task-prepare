# 생성 대기시간 → 착수 순서

**규칙: 문제를 읽은 직후, 오래 걸리는 것을 먼저 던져놓고 그 대기시간 동안 짧은 것을 처리한다.**
추가과제는 10분 전 공개다. 순서를 잘못 잡으면 대기만으로 30분이 날아간다.

`실측` 칸이 비어 있는 항목은 아직 검증 전이다 (`추정`은 공식 문서·경험 기반 추정치이므로 그대로 신뢰하지 말 것).

## 착수 순서 (긴 것부터)

| 순위 | 리소스 | 추정 | 실측 | 비고 |
|---|---|---|---|---|
| 1 | MSK (Provisioned) | 25~35분 | | Serverless는 훨씬 짧다 → 선택 가능하면 Serverless |
| 2 | OpenSearch 도메인 | 15~25분 | | |
| 3 | EKS 컨트롤플레인 | 10~15분 | | 노드그룹은 그 뒤 추가 3~5분 |
| 4 | RDS / Aurora 클러스터 | 10~20분 | | Aurora Serverless v2가 조금 빠름 |
| 5 | DocumentDB 클러스터 | 8~15분 | | 인스턴스 추가로 별도 대기 |
| 6 | Managed Flink Studio | 5~10분 | | 노트북 시작에 추가 대기 |
| 7 | Network Firewall | 5~10분 | | 엔드포인트가 서브넷마다 생성됨 |
| 8 | CloudFront 배포 반영 | 3~8분 | | 설정 변경도 매번 재배포 대기 |
| 9 | Client VPN 엔드포인트 | 3~8분 | | 연관(association)에서 추가 대기 |
| 10 | ACM DNS 검증 | 1~5분 | | Route53 자동 생성 시 빠름. CNAME 오타면 무한 대기 |
| 11 | NAT Gateway | 1~3분 | | |
| 12 | EKS 애드온 / LBC / Karpenter | 1~3분 | | ALB 프로비저닝 별도 2~4분 |
| 13 | ALB / NLB | 2~4분 | | active 되기까지 |
| 14 | 나머지 (S3, DDB, Lambda, SQS, SNS, IAM, SFn, APIGW, KMS, ECR) | 즉시~30초 | | 대기 없음. 마지막에 몰아서 |

## 실전 운용

1. **1분 안에** 문제 전체를 훑고 위 표에서 가장 긴 것을 찾는다.
2. 그것부터 **먼저 던진다.** 완성 안 돼도 좋다 — 생성만 시작시켜 놓는다.
3. 대기 중 14번 그룹(즉시 생성)을 전부 끝낸다.
4. 대기 끝나면 돌아와서 설정을 마무리한다.

**대기 중 절대 하지 말 것:** 터미널 하나 붙잡고 `aws ... wait`로 멍하니 기다리기. 탭을 나눠라.

## 대기 걸리는 것을 피하는 선택지

같은 요구사항을 더 빠른 리소스로 만족시킬 수 있으면 그쪽을 택한다 (과제지가 특정 리소스를 강제하지 않는 한).

| 느린 것 | 빠른 대안 | 조건 |
|---|---|---|
| MSK Provisioned | MSK Serverless | 과제지가 브로커 수/타입을 지정하지 않았을 때 |
| Aurora 클러스터 | RDS 단일 인스턴스 | "Aurora" 명시가 없을 때 |
| EKS 신규 클러스터 | 기존 클러스터에 네임스페이스/노드그룹 추가 | 1과제 추가에서 "클러스터 1개 더" 요구가 아닐 때 |
| OpenSearch | CloudWatch Logs Insights | "OpenSearch" 명시가 없을 때 |
| CloudFront 커스텀 도메인 | 기본 `*.cloudfront.net` 도메인 | 도메인 요구가 없을 때 (ACM 검증 대기 회피) |

## 진행 상태 확인 명령

```bash
aws eks describe-cluster --name $N --query cluster.status --output text
aws rds describe-db-clusters --db-cluster-identifier $N --query 'DBClusters[0].Status' --output text
aws docdb describe-db-clusters --db-cluster-identifier $N --query 'DBClusters[0].Status' --output text
aws kafka list-clusters --query 'ClusterInfoList[].State' --output text
aws cloudfront get-distribution --id $ID --query 'Distribution.Status' --output text
aws elbv2 describe-load-balancers --names $N --query 'LoadBalancers[0].State.Code' --output text
aws acm describe-certificate --certificate-arn $ARN --query 'Certificate.Status' --output text
aws ec2 describe-client-vpn-endpoints --query 'ClientVpnEndpoints[].Status.Code' --output text
```
