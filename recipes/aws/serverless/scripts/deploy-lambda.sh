#!/usr/bin/env bash
# Lambda 를 zip 으로 싸서 만들거나(없으면) 갱신(있으면)하는 멱등 스크립트.
# 제공된 handler.py 하나 + 선택적 requirements.txt 를 그대로 배포한다.
#
#   ./deploy-lambda.sh <함수이름> <소스디렉토리> [핸들러] [리전]
#
# 예)
#   ./deploy-lambda.sh lab-fn ./src                       # 핸들러 기본 handler.handler
#   ./deploy-lambda.sh lab-fn ./src app.lambda_handler
#
# 역할이 없으면 최소권한(로그만) 역할을 만든다. 추가 권한은 만든 뒤 put-role-policy 로 붙여라.
# requirements.txt 가 있으면 pip 로 함께 패키징한다(순수 파이썬 의존성 기준).
set -euo pipefail

FN=${1:?함수 이름}
SRC=${2:?소스 디렉토리 (handler.py 가 있는 곳)}
HANDLER=${3:-handler.handler}
R=${4:-${AWS_REGION:-ap-northeast-2}}
RUNTIME=${RUNTIME:-python3.13}
ROLE_NAME=${ROLE_NAME:-${FN}-role}

command -v aws >/dev/null || { echo "aws CLI 없음" >&2; exit 1; }

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
cp -r "$SRC"/. "$WORK"/

# 의존성이 있으면 함께 설치 (없으면 순수 zip)
if [ -f "$WORK/requirements.txt" ]; then
  echo "== pip install -r requirements.txt"
  pip install -q -r "$WORK/requirements.txt" -t "$WORK" --only-binary=:all: 2>/dev/null \
    || pip install -q -r "$WORK/requirements.txt" -t "$WORK"
fi

ZIP="$WORK/../${FN}.zip"
( cd "$WORK" && zip -qr "$ZIP" . -x '*.pyc' -x '__pycache__/*' )
echo "== packaged $(du -h "$ZIP" | cut -f1)"

# 역할 확보 (없으면 생성)
if ! ROLE=$(aws iam get-role --role-name "$ROLE_NAME" --query Role.Arn --output text 2>/dev/null); then
  echo "== create role $ROLE_NAME"
  TRUST=$(mktemp)
  cat > "$TRUST" <<'JSON'
{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":"lambda.amazonaws.com"},"Action":"sts:AssumeRole"}]}
JSON
  ROLE=$(aws iam create-role --role-name "$ROLE_NAME" \
    --assume-role-policy-document "file://$TRUST" --query Role.Arn --output text)
  aws iam attach-role-policy --role-name "$ROLE_NAME" \
    --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole
  rm -f "$TRUST"
  echo "== IAM 전파 대기 10s"; sleep 10
fi
echo "ROLE=$ROLE"

# 생성 or 갱신 (멱등)
if aws lambda get-function --region "$R" --function-name "$FN" >/dev/null 2>&1; then
  echo "== update code"
  aws lambda update-function-code --region "$R" --function-name "$FN" \
    --zip-file "fileb://$ZIP" >/dev/null
  aws lambda wait function-updated-v2 --region "$R" --function-name "$FN"
  aws lambda update-function-configuration --region "$R" --function-name "$FN" \
    --handler "$HANDLER" --runtime "$RUNTIME" >/dev/null
  aws lambda wait function-updated-v2 --region "$R" --function-name "$FN"
else
  echo "== create function"
  aws lambda create-function --region "$R" --function-name "$FN" \
    --runtime "$RUNTIME" --handler "$HANDLER" --role "$ROLE" \
    --zip-file "fileb://$ZIP" --timeout 10 --memory-size 128 >/dev/null
  aws lambda wait function-active-v2 --region "$R" --function-name "$FN"
fi

echo "== done: $FN ($RUNTIME, $HANDLER)"
aws lambda get-function-configuration --region "$R" --function-name "$FN" \
  --query '[FunctionName,State,LastUpdateStatus]' --output text
