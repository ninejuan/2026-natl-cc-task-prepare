# CloudWatch (Observability)

**트리거 문구** — "대시보드", "알람", "이상치 알림", "Log Insights", "메트릭 수집", "EMF", Monitoring 모듈.

**전제**
```bash
export R=ap-northeast-2
```

---

## 케이스 A — 대시보드 [검증됨]

```bash
aws cloudwatch put-dashboard --region $R --dashboard-name lab-dash --dashboard-body '{
  "widgets":[
    {"type":"metric","x":0,"y":0,"width":12,"height":6,"properties":{
      "metrics":[["AWS/Lambda","Invocations"],["AWS/Lambda","Errors"]],
      "period":300,"stat":"Sum","region":"ap-northeast-2","title":"Lambda"}},
    {"type":"log","x":0,"y":6,"width":12,"height":6,"properties":{
      "query":"SOURCE \"/lab/app\" | fields @timestamp,@message | limit 20",
      "region":"ap-northeast-2","title":"Logs"}}
  ]}'
```
위젯 타입: `metric`(그래프)·`log`(Log Insights)·`text`·`alarm`·`number`(단일값). 과제가 특정 패널 구성을 요구하면 widgets 배열로.

## 케이스 B — 알람 [검증됨]

```bash
# 메트릭 알람
aws cloudwatch put-metric-alarm --region $R --alarm-name lab-alarm \
  --metric-name Errors --namespace AWS/Lambda --statistic Sum --period 60 \
  --evaluation-periods 1 --threshold 5 --comparison-operator GreaterThanThreshold \
  --alarm-actions <sns-arn> --treat-missing-data notBreaching

# 이상 탐지 알람 (동적 임계)
aws cloudwatch put-anomaly-detector --region $R --namespace AWS/Lambda --metric-name Duration --stat Average
aws cloudwatch put-metric-alarm --region $R --alarm-name lab-anomaly \
  --metrics '[{"Id":"m1","MetricStat":{"Metric":{"Namespace":"AWS/Lambda","MetricName":"Duration"},"Period":300,"Stat":"Average"}},
              {"Id":"ad1","Expression":"ANOMALY_DETECTION_BAND(m1,2)"}]' \
  --threshold-metric-id ad1 --comparison-operator GreaterThanUpperThreshold --evaluation-periods 1
```
- **`treat-missing-data`**: 데이터 없을 때 처리(notBreaching/breaching/ignore/missing). 대회에선 트래픽 없으면 INSUFFICIENT_DATA — notBreaching 로.
- **composite alarm**: 여러 알람 AND/OR (`put-composite-alarm`).

## 케이스 C — metric filter (로그 → 커스텀 메트릭) [검증됨]

```bash
aws logs put-metric-filter --region $R --log-group-name /lab/app \
  --filter-name errors --filter-pattern '{$.level="ERROR"}' \
  --metric-transformations metricName=AppErrors,metricNamespace=Lab,metricValue=1
```
JSON 로그의 `level=ERROR` 를 세어 `Lab/AppErrors` 메트릭으로. 이 메트릭에 알람 → 앱 에러 알림.

> 📎 **Logs Insights 쿼리 15종 모음**: `cloudwatch/logs-insights.md` — 필터/집계/시계열(bin)/백분위(pct)/정규식 parse/IP Top/5xx 상세/에러율/distinct/Lambda REPORT·콜드스타트/VPC Flow REJECT 까지 전부 실검증. Athena.md 식 복붙 컬렉션.

## 케이스 D — Log Insights 쿼리

```bash
QID=$(aws logs start-query --region $R --log-group-name /lab/app \
  --start-time $(($(date +%s)-3600)) --end-time $(date +%s) \
  --query-string 'fields @timestamp,@message | filter level="ERROR" | stats count() by bin(5m)' \
  --query queryId --output text)
sleep 5
aws logs get-query-results --region $R --query-id $QID --query 'results' --output json
```
자주 쓰는 구문: `fields`·`filter`·`stats count() by`·`sort`·`limit`·`parse`.

## 케이스 E — EMF (Embedded Metric Format)

앱이 로그에 특정 JSON 을 쓰면 CloudWatch 가 자동으로 메트릭 추출. Lambda 에서 커스텀 메트릭을 PutMetricData API 없이.
```json
{"_aws":{"CloudWatchMetrics":[{"Namespace":"Lab","Dimensions":[["service"]],"Metrics":[{"Name":"latency","Unit":"Milliseconds"}]}],"Timestamp":1234567890},"service":"api","latency":42}
```

## 검증

```bash
aws cloudwatch list-dashboards --region $R --query 'DashboardEntries[].DashboardName' --output text
aws cloudwatch describe-alarms --region $R --query 'MetricAlarms[].[AlarmName,StateValue]' --output text
aws logs describe-metric-filters --region $R --log-group-name /lab/app --query 'metricFilters[].filterName' --output text
```

## Terraform

```hcl
resource "aws_cloudwatch_dashboard" "d" {
  dashboard_name = "lab-dash"
  dashboard_body = jsonencode({ widgets = [ { type = "metric", ... } ] })
}
resource "aws_cloudwatch_metric_alarm" "a" {
  alarm_name          = "lab-alarm"
  namespace           = "AWS/Lambda"
  metric_name         = "Errors"
  statistic           = "Sum"
  period              = 60
  evaluation_periods  = 1
  threshold           = 5
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.alerts.arn]
}
resource "aws_cloudwatch_log_metric_filter" "f" {
  name           = "errors"
  log_group_name = "/lab/app"
  pattern        = "{$.level=\"ERROR\"}"
  metric_transformation {
    name      = "AppErrors"
    namespace = "Lab"
    value     = "1"
  }
}
```

## Console 팁

- **대시보드 편집기**: 위젯을 드래그·리사이즈, 메트릭을 검색으로 추가. JSON 을 손으로 안 짜도 된다. 완성 후 "View/edit source" 로 JSON 추출.
- **알람 생성 마법사**: 메트릭 선택 → 임계·기간 → SNS 액션 → 그래프 미리보기.
- **Log Insights**: 쿼리 편집기 + 저장·공유. 샘플 쿼리 제공.
- **Metrics explorer**: 태그·리소스별 메트릭 자동 대시보드.

## 참고 문서

- CloudWatch 사용 설명서: https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/
- Log Insights 쿼리: https://docs.aws.amazon.com/AmazonCloudWatch/latest/logs/CWL_QuerySyntax.html
- EMF: https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/CloudWatch_Embedded_Metric_Format.html
- Terraform `aws_cloudwatch_metric_alarm`: https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_metric_alarm

## 함정

- **알람 데이터 없으면 INSUFFICIENT_DATA** — 대회 트래픽 부족 시. `treat-missing-data notBreaching` + 부하 생성으로 OK/ALARM 유도.
- **대시보드 body 는 JSON 문자열** — 위젯 좌표(x,y,width,height) 필수.
- **metric filter 는 로그가 쌓여야** 메트릭 생성 — 첫 매칭 로그 전엔 메트릭 없음.
- **Log Insights 비동기** — start-query → 폴링 → get-query-results.
- 알람 액션은 SNS ARN — 알림 요구면 SNS 토픽 먼저.

## 정리
```bash
aws cloudwatch delete-dashboards --region $R --dashboard-names lab-dash
aws cloudwatch delete-alarms --region $R --alarm-names lab-alarm
aws logs delete-log-group --region $R --log-group-name /lab/app
```
