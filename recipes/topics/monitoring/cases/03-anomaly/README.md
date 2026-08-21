# 이상탐지 알람 (ANOMALY_DETECTION_BAND) — 실검증됨(ThresholdMetricId=ad1)
```bash
aws cloudwatch put-anomaly-detector --namespace AWS/Lambda --metric-name Duration --stat Average
aws cloudwatch put-metric-alarm --alarm-name anom \
  --metrics '[{"Id":"m1","MetricStat":{"Metric":{"Namespace":"AWS/Lambda","MetricName":"Duration"},"Period":300,"Stat":"Average"}},{"Id":"ad1","Expression":"ANOMALY_DETECTION_BAND(m1,2)"}]' \
  --threshold-metric-id ad1 --comparison-operator GreaterThanUpperThreshold --evaluation-periods 1
```
★ 이상탐지는 학습 데이터(수 시간) 필요 — 밴드 형성 전엔 판정 부정확. 즉석 시연엔 부적합.
