# Monitoring 플레이북 (2025 #11)

**가이드 원문(2025 #11)** — "웹 서비스 환경 모니터링. 웹 서버는 Python 앱/HTML(nginx), 호스팅은 **ECS**, 엔드포인트는 **ELB**. 서비스 수준 **Dashboard** + 이상치 트래픽 **Alerting**."
- 필수: VPC, ECS, ELB / 선택: CloudWatch

**트리거 문구** — "대시보드 구성", "이상치 알림", "서비스 모니터링", "ALB/ECS 메트릭", "알람".

**리전 격리** — 전용. 예시 `ap-northeast-2`.

**기반 카드**: CloudWatch(대시보드·알람·이상탐지·metric filter) `../../aws/tier3/cloudwatch.md`, Logs Insights 15종 `../../aws/tier3/cloudwatch/logs-insights.md`, ECS `../../aws/tier2/ecs.md`.

---

## 케이스 인덱스

| # | 케이스 | 핵심 | 기반 |
|---|---|---|---|
| 01 | 대시보드(ECS/ALB 메트릭) | put-dashboard, ALB RequestCount·TargetResponseTime·5xx | tier3 ✓ |
| 02 | 알람 + SNS | put-metric-alarm, treat-missing-data | tier3 ✓ |
| 03 | 이상 탐지 알람 | ANOMALY_DETECTION_BAND | tier3 ✓ |
| 04 | Container Insights | ECS 클러스터 CPU/메모리 자동 메트릭 | `cases/04-container-insights/` |
| 05 | composite alarm | 여러 알람 AND/OR | tier3 |

## 자주 쓰는 ALB/ECS 메트릭 (대시보드·알람 대상)

| 메트릭 | 네임스페이스 | 의미 |
|---|---|---|
| RequestCount | AWS/ApplicationELB | 요청 수(트래픽) |
| TargetResponseTime | AWS/ApplicationELB | 응답 지연 |
| HTTPCode_Target_5XX_Count | AWS/ApplicationELB | 백엔드 5xx |
| HTTPCode_ELB_5XX_Count | AWS/ApplicationELB | ALB 자체 5xx |
| UnHealthyHostCount | AWS/ApplicationELB | 비정상 타깃 |
| CPUUtilization / MemoryUtilization | AWS/ECS or ECS/ContainerInsights | 컨테이너 부하 |

## 검증 (채점자 문체)

```bash
aws cloudwatch list-dashboards --region $R --query 'DashboardEntries[].DashboardName' --output text
aws cloudwatch describe-alarms --region $R --query 'MetricAlarms[].[AlarmName,StateValue]' --output text
# 채점이 부하 생성 → 알람 ALARM 전이 확인. treat-missing-data notBreaching 필수(트래픽 없을 때 INSUFFICIENT_DATA 회피)
```

## 함정

- **트래픽 없으면 INSUFFICIENT_DATA** — `treat-missing-data notBreaching` + 채점이 부하 유도.
- **Container Insights 는 클러스터 설정** — `--settings name=containerInsights,value=enabled`. 켜야 ECS/ContainerInsights 네임스페이스 메트릭.
- **이상탐지는 학습 데이터 필요** — 최소 몇 시간 메트릭 있어야 밴드 형성. 즉석 시연 어려움.
- 대시보드 body 는 JSON, 위젯 좌표 필수.
- 알람 액션은 SNS ARN.

## context7 참고

- `aws_cloudwatch_dashboard`·`_metric_alarm`·`_composite_alarm` (TF AWS v6)
- Container Insights: https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/ContainerInsights.html
