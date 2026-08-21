#!/bin/bash
# Studio 앱에 커넥터 JAR(Maven) 추가 — 기본 상태엔 kinesis/kafka 커넥터가 없다(실측).
set -x
R=eu-west-2
aws kinesisanalyticsv2 stop-application --region $R --application-name lab-flink --force 2>&1 | tail -1
until [ "$(aws kinesisanalyticsv2 describe-application --region $R --application-name lab-flink --query ApplicationDetail.ApplicationStatus --output text)" = "READY" ]; do sleep 20; done
V=$(aws kinesisanalyticsv2 describe-application --region $R --application-name lab-flink --query ApplicationDetail.ApplicationVersionId --output text)
aws kinesisanalyticsv2 update-application --region $R --application-name lab-flink \
  --current-application-version-id $V \
  --application-configuration-update '{"ZeppelinApplicationConfigurationUpdate":{"CustomArtifactsConfigurationUpdate":[
    {"ArtifactType":"DEPENDENCY_JAR","MavenReference":{"GroupId":"org.apache.flink","ArtifactId":"flink-sql-connector-kinesis","Version":"1.15.4"}},
    {"ArtifactType":"DEPENDENCY_JAR","MavenReference":{"GroupId":"org.apache.flink","ArtifactId":"flink-connector-kafka","Version":"1.15.4"}}
  ]}}' \
  --query 'ApplicationDetail.ApplicationConfigurationDescription.ZeppelinApplicationConfigurationDescription.CustomArtifactsConfigurationDescription[].MavenReferenceDescription' --output json
aws kinesisanalyticsv2 start-application --region $R --application-name lab-flink 2>&1 | tail -1
until [ "$(aws kinesisanalyticsv2 describe-application --region $R --application-name lab-flink --query ApplicationDetail.ApplicationStatus --output text)" = "RUNNING" ]; do
  echo "wait $(aws kinesisanalyticsv2 describe-application --region $R --application-name lab-flink --query ApplicationDetail.ApplicationStatus --output text)"; sleep 20; done
echo CONNDONE
