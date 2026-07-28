# 실검증 기록

계정 `156041424727`. 카드/스크립트를 실제로 돌린 결과만 적는다. 추정치는 적지 않는다.

> 주의: 이 계정에는 task3 연습 인프라(`apdev-*`, EKS `apdev-eks` 1.35)가 살아 있다. 검증용 리소스는 이름을 겹치지 않게 만들고, 남의 것을 지우지 않는다.

| 대상 | 리전 | 결과 | 소요 | 비용 | 비고 |
|---|---|---|---|---|---|
| `bin/discover.sh` | ap-northeast-2 | ✓ | ~20s | $0 | 41개 변수 추출. VPC/서브넷/SG/RT/EKS(+OIDC·버전·NG)/ALB·TG/CF/DDB/S3/Lambda/ECR/KMS/EC2 확인 |
| `bin/mark-self.sh --foul` | ap-northeast-2 | ✓ | 5.5s | $0 | 최초 120s+ → IAM 정책 조회 `xargs -P8` 병렬화로 5.5s. `Resource:"*"` 오탐 제거(Action/Principal만 검사) |
| `bin/build-all.sh` | — | ✓ | 즉시 | $0 | 카드 0개 상태 정상 종료 확인. bash 3.2 호환(mapfile 제거) |
| `bin/bootstrap.sh` | — | 부분 | — | $0 | macOS에서 실행 불가(Linux 바이너리). 다운로드 URL 6종 HTTP 200 확인, kustomize는 404라 제거(kubectl -k 사용). **CloudShell 실행 검증 필요** |

## 미검증 / 확인 필요

- `bin/bootstrap.sh` 를 CloudShell(bash 5, Amazon Linux 2023)에서 실제 실행
- `bin/mark-self.sh` 의 카드 검증 블록 추출·실행 경로 (카드가 생긴 뒤)
