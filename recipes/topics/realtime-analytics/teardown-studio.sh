#!/bin/bash
set -x
R=eu-west-2
A=$(aws sts get-caller-identity --query Account --output text)
aws kinesisanalyticsv2 stop-application --region $R --application-name lab-flink --force 2>&1 | tail -1
until [ "$(aws kinesisanalyticsv2 describe-application --region $R --application-name lab-flink --query ApplicationDetail.ApplicationStatus --output text)" = "READY" ]; do sleep 20; done
V=$(aws kinesisanalyticsv2 describe-application --region $R --application-name lab-flink --query ApplicationDetail.CreateTimestamp --output text)
aws kinesisanalyticsv2 delete-application --region $R --application-name lab-flink --create-timestamp $V 2>&1 | tail -1
sleep 20
aws kinesisanalyticsv2 list-applications --region $R --query 'ApplicationSummaries[].[ApplicationName,ApplicationStatus]' --output text   # ★ delete 가 조용히 실패할 수 있어 재확인
aws kinesis delete-stream --region $R --stream-name lab-stream --enforce-consumer-deletion
aws glue delete-database --region $R --name lab_flink_db
aws s3 rm s3://lab-flink-$A-$R --recursive >/dev/null 2>&1; aws s3api delete-bucket --bucket lab-flink-$A-$R --region $R
aws iam delete-role-policy --role-name lab-flink-role --policy-name perm
aws iam delete-role --role-name lab-flink-role
aws kinesisanalyticsv2 list-applications --region $R --query 'ApplicationSummaries[].[ApplicationName,ApplicationStatus]' --output text
echo FLINKDOWN
