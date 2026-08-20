#!/usr/bin/env bash
# Live verify: CloudFront + private S3 (PAB on) via OAC, default root object,
# viewer-response CloudFront Function (security headers).
# Deterministic names; teardown finds by Comment/name. Usage: ./verify.sh {deploy|test|teardown}
set -uo pipefail
export AWS_PAGER=""
R=ap-northeast-1
ACCT=$(aws sts get-caller-identity --query Account --output text)
HERE="$(cd "$(dirname "$0")" && pwd)"
FUNC_SRC="$HERE/../../../../aws/tier1/cloudfront/functions/viewer-response-headers.js"

BUCKET=lab-apne1-cf-origin-${ACCT}
OAC=lab-apne1-cf-oac
COMMENT=lab-apne1-cf
CFFN=lab-apne1-viewer-response-headers
# CloudFront managed cache policy "CachingDisabled" (so cache never hides header/content in grading)
CACHE_DISABLED=4135ea2d-6df8-44a3-9df3-4b5a84be39ad

dist_id() { aws cloudfront list-distributions --query "DistributionList.Items[?Comment=='$COMMENT'].Id" --output text 2>/dev/null; }
oac_id()  { aws cloudfront list-origin-access-controls --query "OriginAccessControlList.Items[?Name=='$OAC'].Id" --output text 2>/dev/null; }
cffn_arn(){ aws cloudfront describe-function --name $CFFN --query 'FunctionSummary.FunctionMetadata.FunctionARN' --output text 2>/dev/null; }

deploy() {
  echo "== deploy =="
  # 1. private bucket, PAB on
  if ! aws s3api head-bucket --bucket $BUCKET 2>/dev/null; then
    aws s3api create-bucket --region $R --bucket $BUCKET --create-bucket-configuration LocationConstraint=$R >/dev/null
  fi
  aws s3api put-public-access-block --bucket $BUCKET --public-access-block-configuration \
    BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true
  aws s3 cp "$HERE/index.html" s3://$BUCKET/index.html --content-type text/html >/dev/null
  echo "bucket $BUCKET (PAB on), index.html uploaded"

  # 2. OAC
  local OAC_ID; OAC_ID=$(oac_id)
  if [ -z "$OAC_ID" ] || [ "$OAC_ID" = "None" ]; then
    OAC_ID=$(aws cloudfront create-origin-access-control --origin-access-control-config \
      "Name=$OAC,Description=lab apne1,SigningProtocol=sigv4,SigningBehavior=always,OriginAccessControlOriginType=s3" \
      --query 'OriginAccessControl.Id' --output text)
  fi
  echo "OAC $OAC_ID"

  # 3. CloudFront Function (create + publish)
  if ! aws cloudfront describe-function --name $CFFN >/dev/null 2>&1; then
    aws cloudfront create-function --name $CFFN \
      --function-config "Comment=lab apne1 sec headers,Runtime=cloudfront-js-2.0" \
      --function-code "fileb://$FUNC_SRC" >/dev/null
  fi
  local ETAG; ETAG=$(aws cloudfront describe-function --name $CFFN --query 'ETag' --output text)
  aws cloudfront publish-function --name $CFFN --if-match "$ETAG" >/dev/null 2>&1 || true
  local FN_ARN; FN_ARN=$(cffn_arn)
  echo "function $FN_ARN"

  # 4. distribution (OAC origin + viewer-response function assoc)
  local DIST; DIST=$(dist_id)
  if [ -z "$DIST" ] || [ "$DIST" = "None" ]; then
    local ODOMAIN="${BUCKET}.s3.${R}.amazonaws.com"
    local CFG; CFG=$(mktemp)
    cat > "$CFG" <<JSON
{
  "CallerReference": "lab-apne1-cf-$(date +%s)",
  "Comment": "$COMMENT",
  "Enabled": true,
  "DefaultRootObject": "index.html",
  "Origins": {"Quantity": 1, "Items": [{
    "Id": "s3origin",
    "DomainName": "$ODOMAIN",
    "OriginAccessControlId": "$OAC_ID",
    "S3OriginConfig": {"OriginAccessIdentity": ""}
  }]},
  "DefaultCacheBehavior": {
    "TargetOriginId": "s3origin",
    "ViewerProtocolPolicy": "redirect-to-https",
    "CachePolicyId": "$CACHE_DISABLED",
    "AllowedMethods": {"Quantity": 2, "Items": ["GET","HEAD"],
      "CachedMethods": {"Quantity": 2, "Items": ["GET","HEAD"]}},
    "Compress": true,
    "FunctionAssociations": {"Quantity": 1, "Items": [
      {"EventType": "viewer-response", "FunctionARN": "$FN_ARN"}]}
  }
}
JSON
    DIST=$(aws cloudfront create-distribution --distribution-config "file://$CFG" --query 'Distribution.Id' --output text)
  fi
  echo "distribution $DIST"

  # 5. bucket policy: only this distribution (OAC SourceArn)
  aws s3api put-bucket-policy --bucket $BUCKET --policy "{\"Version\":\"2012-10-17\",\"Statement\":[{\"Sid\":\"AllowCloudFrontOAC\",\"Effect\":\"Allow\",\"Principal\":{\"Service\":\"cloudfront.amazonaws.com\"},\"Action\":\"s3:GetObject\",\"Resource\":\"arn:aws:s3:::${BUCKET}/*\",\"Condition\":{\"StringEquals\":{\"AWS:SourceArn\":\"arn:aws:cloudfront::${ACCT}:distribution/${DIST}\"}}}]}"
  echo "bucket policy bound to distribution $DIST"
  echo "domain: $(aws cloudfront get-distribution --id $DIST --query 'Distribution.DomainName' --output text)"
  echo "== deploy done (wait for Deployed, then ./verify.sh test) =="
}

test_it() {
  local DIST; DIST=$(dist_id)
  local DOMAIN; DOMAIN=$(aws cloudfront get-distribution --id $DIST --query 'Distribution.DomainName' --output text)
  echo "dist=$DIST domain=$DOMAIN"
  echo "-- wait for Deployed --"
  aws cloudfront wait distribution-deployed --id $DIST
  echo "Status=$(aws cloudfront get-distribution --id $DIST --query 'Distribution.Status' --output text)"
  echo "-- curl distribution (expect 200 + content + security headers) --"
  curl -s -D - "https://$DOMAIN/" -o /tmp/cf-body.html -w '\nHTTP=%{http_code}\n' | \
    grep -iE '^HTTP|strict-transport-security|x-content-type-options|x-frame-options|x-custom-marker|HTTP='
  echo "-- body --"; cat /tmp/cf-body.html
  echo "-- direct S3 access (expect 403; PAB+OAC block it) --"
  curl -s -o /dev/null -w 'S3 direct HTTP=%{http_code}\n' "https://${BUCKET}.s3.${R}.amazonaws.com/index.html"
}

teardown() {
  echo "== teardown =="
  local DIST; DIST=$(dist_id)
  if [ -n "$DIST" ] && [ "$DIST" != "None" ]; then
    local ETAG; ETAG=$(aws cloudfront get-distribution-config --id $DIST --query 'ETag' --output text)
    aws cloudfront get-distribution-config --id $DIST --query 'DistributionConfig' > /tmp/dc.json
    # disable
    python3 -c "import json;d=json.load(open('/tmp/dc.json'));d['Enabled']=False;json.dump(d,open('/tmp/dc.json','w'))"
    aws cloudfront update-distribution --id $DIST --distribution-config file:///tmp/dc.json --if-match "$ETAG" >/dev/null
    echo "disabled $DIST; waiting Deployed (slow ~15min)"
    aws cloudfront wait distribution-deployed --id $DIST
    ETAG=$(aws cloudfront get-distribution --id $DIST --query 'ETag' --output text)
    aws cloudfront delete-distribution --id $DIST --if-match "$ETAG"
    echo "deleted distribution $DIST"
  fi
  local FA; FA=$(cffn_arn)
  if [ -n "$FA" ] && [ "$FA" != "None" ]; then
    local ET; ET=$(aws cloudfront describe-function --name $CFFN --query 'ETag' --output text)
    aws cloudfront delete-function --name $CFFN --if-match "$ET" 2>/dev/null || true
    echo "deleted function $CFFN"
  fi
  local OAC_ID; OAC_ID=$(oac_id)
  if [ -n "$OAC_ID" ] && [ "$OAC_ID" != "None" ]; then
    local ET; ET=$(aws cloudfront get-origin-access-control --id $OAC_ID --query 'ETag' --output text)
    aws cloudfront delete-origin-access-control --id $OAC_ID --if-match "$ET" 2>/dev/null || true
    echo "deleted OAC $OAC_ID"
  fi
  aws s3 rb s3://$BUCKET --force 2>/dev/null || true
  echo "removed bucket $BUCKET"
  echo "== teardown done =="
}

case "${1:-}" in
  deploy) deploy ;;
  test) test_it ;;
  teardown) teardown ;;
  *) echo "usage: $0 {deploy|test|teardown}"; exit 1 ;;
esac
