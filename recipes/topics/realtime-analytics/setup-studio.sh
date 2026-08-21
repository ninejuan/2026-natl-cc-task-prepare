#!/bin/bash
# realtime-analytics — Managed Flink Studio(Zeppelin) 앱 생성/기동 (eu-west-2)
set -x
R=eu-west-2
A=$(aws sts get-caller-identity --query Account --output text)
D="$(cd "$(dirname "$0")" && pwd)"; cd "$D"

aws kinesis create-stream --region $R --stream-name lab-stream --shard-count 1 2>&1 | tail -1
aws glue create-database --region $R --database-input Name=lab_flink_db 2>&1 | tail -1
aws s3api create-bucket --region $R --bucket lab-flink-$A-$R --create-bucket-configuration LocationConstraint=$R 2>&1 | tail -1

cat > flink-trust.json <<'EOF'
{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":"kinesisanalytics.amazonaws.com"},"Action":"sts:AssumeRole"}]}
EOF
cat > flink-perm.json <<EOF
{"Version":"2012-10-17","Statement":[
 {"Effect":"Allow","Action":["kinesis:*"],"Resource":"arn:aws:kinesis:$R:$A:stream/lab-*"},
 {"Effect":"Allow","Action":["glue:*"],"Resource":"*"},
 {"Effect":"Allow","Action":["s3:*"],"Resource":["arn:aws:s3:::lab-flink-$A-$R","arn:aws:s3:::lab-flink-$A-$R/*"]},
 {"Effect":"Allow","Action":["logs:*","cloudwatch:PutMetricData"],"Resource":"*"}]}
EOF
aws iam create-role --role-name lab-flink-role --assume-role-policy-document file://flink-trust.json --query Role.Arn --output text
aws iam put-role-policy --role-name lab-flink-role --policy-name perm --policy-document file://flink-perm.json
sleep 12
aws kinesis wait stream-exists --region $R --stream-name lab-stream

aws kinesisanalyticsv2 create-application --region $R \
  --application-name lab-flink --runtime-environment ZEPPELIN-FLINK-3_0 \
  --application-mode INTERACTIVE \
  --service-execution-role arn:aws:iam::$A:role/lab-flink-role \
  --application-configuration "{\"ApplicationSnapshotConfiguration\":{\"SnapshotsEnabled\":false},\"FlinkApplicationConfiguration\":{\"ParallelismConfiguration\":{\"ConfigurationType\":\"CUSTOM\",\"Parallelism\":1,\"ParallelismPerKPU\":1}},\"ZeppelinApplicationConfiguration\":{\"CatalogConfiguration\":{\"GlueDataCatalogConfiguration\":{\"DatabaseARN\":\"arn:aws:glue:$R:$A:database/lab_flink_db\"}}}}" \
  --query 'ApplicationDetail.[ApplicationName,ApplicationStatus,RuntimeEnvironment,ApplicationMode]' --output text

aws kinesisanalyticsv2 start-application --region $R --application-name lab-flink 2>&1 | tail -2
until [ "$(aws kinesisanalyticsv2 describe-application --region $R --application-name lab-flink --query ApplicationDetail.ApplicationStatus --output text)" = "RUNNING" ]; do
  echo "wait $(aws kinesisanalyticsv2 describe-application --region $R --application-name lab-flink --query ApplicationDetail.ApplicationStatus --output text)"; sleep 30
done
echo "===== RUNNING ====="
aws kinesisanalyticsv2 describe-application --region $R --application-name lab-flink \
  --query 'ApplicationDetail.{status:ApplicationStatus,rt:RuntimeEnvironment,mode:ApplicationMode,catalog:ApplicationConfigurationDescription.ZeppelinApplicationConfigurationDescription.CatalogConfigurationDescription}' --output json
echo UP
