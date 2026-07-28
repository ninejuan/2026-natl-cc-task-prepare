5-0
1) 웹브라우저로 선수의 AWS 계정에 로그인 후 us-west-1 Region으로 접속합니다.

5-1
1) 웹브라우저로 선수의 AWS 계정에 로그인 후 CloudShell을 실행합니다.
2) 아래 명령어를 입력하여 inventory, inventory-state-machine, inventory-rest-api가 차례대로 출력되는지 확인합니다.
aws dynamodb list-tables --query TableNames --output text
aws stepfunctions list-state-machines --query stateMachines[].name --output text
aws apigateway get-rest-apis --query items[].name --output text

5-2
1) 웹브라우저로 선수의 AWS 계정에 로그인 후 CloudShell을 실행합니다.
2) 아래 명령어를 입력하여 []가 출력되는지 확인합니다.
aws lambda list-functions --query Functions

5-3
1) 웹브라우저로 선수의 AWS 계정에 로그인 후 CloudShell을 실행합니다.
2) 아래 명령어를 입력하여 1200, 30이 출력되는지 확인합니다.
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
aws dynamodb put-item --table-name inventory --item '{"name": {"S": "balance"}, "value": {"N": "1000"}}'
aws dynamodb put-item --table-name inventory --item '{"name": {"S": "stock"}, "value": {"N": "50"}}'

aws stepfunctions start-execution --state-machine-arn arn:aws:states:us-west-1:$ACCOUNT_ID:stateMachine:inventory-state-machine --input '{"sales": 20}'
sleep 5
aws dynamodb get-item --table-name inventory --key '{"name": {"S": "balance"}}' --query Item.value.N --output text
aws dynamodb get-item --table-name inventory --key '{"name": {"S": "stock"}}' --query Item.value.N --output text

5-4
1) 웹브라우저로 선수의 AWS 계정에 로그인 후 CloudShell을 실행합니다.
2) 아래 명령어를 입력하여 1200, 100이 출력되는지 확인합니다.
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
aws dynamodb put-item --table-name inventory --item '{"name": {"S": "balance"}, "value": {"N": "1200"}}'
aws dynamodb put-item --table-name inventory --item '{"name": {"S": "stock"}, "value": {"N": "30"}}'

aws stepfunctions start-execution --state-machine-arn arn:aws:states:us-west-1:$ACCOUNT_ID:stateMachine:inventory-state-machine --input '{"sales": 30}'
sleep 5
aws dynamodb get-item --table-name inventory --key '{"name": {"S": "balance"}}' --query Item.value.N --output text
aws dynamodb get-item --table-name inventory --key '{"name": {"S": "stock"}}' --query Item.value.N --output text

5-5
1) 웹브라우저로 선수의 AWS 계정에 로그인 후 CloudShell을 실행합니다.
2) 아래 명령어를 입력하여 DynamoDB의 값을 재설정 합니다.
aws dynamodb put-item --table-name inventory --item '{"name": {"S": "balance"}, "value": {"N": "1200"}}'
aws dynamodb put-item --table-name inventory --item '{"name": {"S": "stock"}, "value": {"N": "100"}}'
3) API Gateway 콘솔에 접속하여 inventory-rest-api의 도메인 주소를 기록합니다.
4) https://<선수 도메인>/v1/inventory?item=balance에 접속하여 1200 (큰 따옴표 없음)이 출력되는지 확인합니다.
5) https://<선수 도메인>/v1/inventory?item=stock에 접속하여 100 (큰 따옴표 없음)이 출력되는지 확인합니다.

5-6
1) API Gateway 콘솔에 접속하여 inventory-rest-api의 도메인 주소를 기록합니다.
2) https://<선수 도메인>/v1/inventory?item=mysecrets에 접속하여 403 Forbidden이 출력되는지 확인합니다. 코드와 바디 모두 403에 해당 하는지 확인합니다.