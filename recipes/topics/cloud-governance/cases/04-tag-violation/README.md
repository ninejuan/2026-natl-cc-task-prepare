# 태그 위반 탐지 → SNS
실검증됨(tag-change EventBridge rule → SNS target, FailedEntryCount=0).
```bash
aws events put-rule --name tagrule --event-pattern file://rule-pattern.json
aws sns set-topic-attributes --topic-arn <t> --attribute-name Policy --attribute-value '{...events.amazonaws.com sns:Publish...}'
aws events put-targets --rule tagrule --targets Id=1,Arn=<sns-arn>
```
태그 변경 이벤트(aws.tag)는 CloudTrail 없이도 EventBridge 로 옴. 필수 태그 누락/변경 감지 → SNS 알림 또는 Lambda 로 태그 복원. 기반: ../../../../aws/serverless/eventbridge.md.
