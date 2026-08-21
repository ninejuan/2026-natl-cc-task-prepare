#!/bin/bash
# cdn 03 — Lambda@Edge(Node.js + sharp) 이미지 리사이징 라이브 검증 (us-east-1 + CloudFront)
set -x
R=us-east-1
A=$(aws sts get-caller-identity --query Account --output text)
B=lab-edge-$A
D="$(cd "$(dirname "$0")" && pwd)"; cd "$D"

########## 1) S3 오리진 ##########
aws s3api create-bucket --region $R --bucket $B 2>&1 | tail -1
aws s3api put-object --bucket $B --key sample.png --body sample.png --content-type image/png --query ETag --output text

########## 2) Lambda@Edge 함수 (Node.js 20 + sharp) ##########
cat > edge-trust.json <<'EOF'
{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":["lambda.amazonaws.com","edgelambda.amazonaws.com"]},"Action":"sts:AssumeRole"}]}
EOF
aws iam create-role --role-name lab-edge-role --assume-role-policy-document file://edge-trust.json --query Role.Arn --output text
aws iam put-role-policy --role-name lab-edge-role --policy-name perm --policy-document \
  "{\"Version\":\"2012-10-17\",\"Statement\":[{\"Effect\":\"Allow\",\"Action\":[\"s3:GetObject\"],\"Resource\":\"arn:aws:s3:::$B/*\"},{\"Effect\":\"Allow\",\"Action\":[\"logs:CreateLogGroup\",\"logs:CreateLogStream\",\"logs:PutLogEvents\"],\"Resource\":\"*\"}]}"
sleep 12

rm -f fn.zip && zip -qr fn.zip index.js node_modules && ls -lh fn.zip
aws lambda create-function --region $R --function-name lab-edge-resize3 --runtime nodejs20.x \
  --role arn:aws:iam::$A:role/lab-edge-role --handler index.handler --zip-file fileb://fn.zip \
  --timeout 15 --memory-size 1024 --query '[FunctionName,Runtime]' --output text
aws lambda wait function-active-v2 --region $R --function-name lab-edge-resize3
VER=$(aws lambda publish-version --region $R --function-name lab-edge-resize3 --query FunctionArn --output text)
echo "VER=$VER"   # ★ Lambda@Edge 는 버전 ARN(별칭/$LATEST 불가)

########## 3) OAC + 배포 ##########
OAC=$(aws cloudfront create-origin-access-control --origin-access-control-config \
  '{"Name":"lab-edge-oac","SigningProtocol":"sigv4","SigningBehavior":"always","OriginAccessControlOriginType":"s3"}' \
  --query OriginAccessControl.Id --output text)
cat > dist.json <<EOF
{
  "CallerReference": "lab-edge-$(date +%s)",
  "Comment": "lab-edge-resize3",
  "Enabled": true,
  "DefaultRootObject": "",
  "Origins": {"Quantity": 1, "Items": [{
    "Id": "s3origin",
    "DomainName": "$B.s3.$R.amazonaws.com",
    "OriginAccessControlId": "$OAC",
    "S3OriginConfig": {"OriginAccessIdentity": ""}
  }]},
  "DefaultCacheBehavior": {
    "TargetOriginId": "s3origin",
    "ViewerProtocolPolicy": "redirect-to-https",
    "CachePolicyId": "4135ea2d-6df8-44a3-9df3-4b5a84be39ad",
    "OriginRequestPolicyId": "b689b0a8-53d0-40ab-baf2-68738e2966ac",
    "LambdaFunctionAssociations": {"Quantity": 1, "Items": [
      {"LambdaFunctionARN": "$VER", "EventType": "origin-response", "IncludeBody": false}
    ]}
  }
}
EOF
DIST=$(aws cloudfront create-distribution --distribution-config file://dist.json --query 'Distribution.Id' --output text)
DOM=$(aws cloudfront get-distribution --id $DIST --query 'Distribution.DomainName' --output text)
echo "DIST=$DIST DOM=$DOM"
aws s3api put-bucket-policy --bucket $B --policy \
  "{\"Version\":\"2012-10-17\",\"Statement\":[{\"Effect\":\"Allow\",\"Principal\":{\"Service\":\"cloudfront.amazonaws.com\"},\"Action\":\"s3:GetObject\",\"Resource\":\"arn:aws:s3:::$B/*\",\"Condition\":{\"StringEquals\":{\"AWS:SourceArn\":\"arn:aws:cloudfront::$A:distribution/$DIST\"}}}]}"

aws cloudfront wait distribution-deployed --id $DIST
echo "===== Deployed ====="

########## 4) 검증 ##########
echo "--- 원본(쿼리 없음) ---"
curl -s -o orig.png -D - "https://$DOM/sample.png" | grep -iE '^HTTP|x-resized-by|content-type'
file orig.png; wc -c < orig.png
echo "--- 리사이즈(?w=100) ---"
curl -s -o small.png -D - "https://$DOM/sample.png?w=100" | grep -iE '^HTTP|x-resized-by|content-type'
file small.png; wc -c < small.png
echo "--- 다른 폭(?w=64) ---"
curl -s -o tiny.png -D - "https://$DOM/sample.png?w=64" | grep -iE '^HTTP|x-resized-by'
file tiny.png
echo "--- S3 직접 접근은 차단되어야(OAC) ---"
curl -s -o /dev/null -w '%{http_code}\n' "https://$B.s3.$R.amazonaws.com/sample.png"

########## 5) teardown ##########
echo "===== teardown ====="
aws cloudfront get-distribution-config --id $DIST --query DistributionConfig > dc.json
ET=$(aws cloudfront get-distribution-config --id $DIST --query ETag --output text)
python3 - <<'PY'
import json; d=json.load(open("dc.json")); d["Enabled"]=False
d["DefaultCacheBehavior"]["LambdaFunctionAssociations"]={"Quantity":0,"Items":[]}
json.dump(d,open("dc2.json","w"))
PY
aws cloudfront update-distribution --id $DIST --distribution-config file://dc2.json --if-match $ET >/dev/null
aws cloudfront wait distribution-deployed --id $DIST
ET=$(aws cloudfront get-distribution-config --id $DIST --query ETag --output text)
aws cloudfront delete-distribution --id $DIST --if-match $ET
aws cloudfront delete-origin-access-control --id $OAC --if-match "$(aws cloudfront get-origin-access-control --id $OAC --query ETag --output text)"
aws s3 rm s3://$B --recursive >/dev/null; aws s3api delete-bucket --bucket $B
echo "--- Lambda@Edge 함수 삭제 시도(복제본 때문에 즉시 삭제 안 될 수 있음) ---"
aws lambda delete-function --region $R --function-name lab-edge-resize3 2>&1 | tail -2
echo DONE
