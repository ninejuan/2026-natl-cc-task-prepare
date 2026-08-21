#!/bin/bash
set -x
R=ap-northeast-1; A=156041424727
D="$(cd "$(dirname "$0")" && pwd)"; cd "$D"; . ./gha.env
aws ecs update-service --region $R --cluster lab-gha-cluster --service lab-gha-svc --desired-count 0 >/dev/null
until [ "$(aws ecs describe-services --region $R --cluster lab-gha-cluster --services lab-gha-svc --query 'services[0].runningCount' --output text)" = "0" ]; do sleep 10; done
aws ecs delete-service --region $R --cluster lab-gha-cluster --service lab-gha-svc --force --query 'service.status' --output text
for REV in 1 2; do aws ecs deregister-task-definition --region $R --task-definition lab-gha:$REV --query 'taskDefinition.status' --output text; done
aws ecs delete-cluster --region $R --cluster lab-gha-cluster --query 'cluster.status' --output text
aws ecr delete-repository --region $R --repository-name lab-gha --force --query 'repository.repositoryName' --output text
aws logs delete-log-group --region $R --log-group-name /ecs/lab-gha
aws iam delete-role-policy --role-name lab-gha-deploy --policy-name deploy
aws iam delete-role --role-name lab-gha-deploy
aws iam detach-role-policy --role-name lab-gha-exec --policy-arn arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy
aws iam delete-role --role-name lab-gha-exec
aws iam delete-role --role-name lab-gha-task
aws iam delete-open-id-connect-provider --open-id-connect-provider-arn arn:aws:iam::${A}:oidc-provider/token.actions.githubusercontent.com
until [ "$(aws ec2 describe-network-interfaces --region $R --filters Name=vpc-id,Values=$VPC --query 'length(NetworkInterfaces)' --output text)" = "0" ]; do sleep 15; done
aws ec2 revoke-security-group-ingress --region $R --group-id $SG --protocol tcp --port 8080 --cidr 0.0.0.0/0 >/dev/null
aws ec2 delete-subnet --region $R --subnet-id $S1
aws ec2 delete-subnet --region $R --subnet-id $S2
aws ec2 delete-route-table --region $R --route-table-id $RT
aws ec2 detach-internet-gateway --region $R --vpc-id $VPC --internet-gateway-id $IGW
aws ec2 delete-internet-gateway --region $R --internet-gateway-id $IGW
aws ec2 delete-vpc --region $R --vpc-id $VPC
echo GHADOWN
