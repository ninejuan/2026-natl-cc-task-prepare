# 알람 + SNS (01-dashboard-alarm 에 포함, 실검증됨)
`../01-dashboard-alarm/verify.sh` 가 대시보드+알람+SNS 를 함께 생성/검증. 알람 단독:
```bash
aws cloudwatch put-metric-alarm --alarm-name a --metric-name HTTPCode_Target_5XX_Count \
  --namespace AWS/ApplicationELB --statistic Sum --period 60 --evaluation-periods 1 --threshold 5 \
  --comparison-operator GreaterThanThreshold --treat-missing-data notBreaching --alarm-actions <sns-arn>
```
★ treat-missing-data notBreaching (트래픽 없을 때 INSUFFICIENT_DATA 회피). set-alarm-state 로 OK↔ALARM 배선 확인.
