#!/bin/bash
set -x
R=ap-northeast-2
D="$(cd "$(dirname "$0")" && pwd)"; cd "$D"; . ./oslog.env
for T in $(aws ecs list-tasks --region $R --cluster lab-oslog-cluster --query 'taskArns[]' --output text); do
  aws ecs stop-task --region $R --cluster lab-oslog-cluster --task $T --query 'task.lastStatus' --output text
done
aws ecs deregister-task-definition --region $R --task-definition lab-oslog:1 --query 'taskDefinition.status' --output text
until [ "$(aws ecs list-tasks --region $R --cluster lab-oslog-cluster --desired-status RUNNING --query 'length(taskArns)' --output text)" = "0" ]; do sleep 10; done
aws ecs delete-cluster --region $R --cluster lab-oslog-cluster --query 'cluster.status' --output text
aws opensearch delete-domain --region $R --domain-name lab-oslog --query 'DomainStatus.Deleted' --output text
aws logs delete-log-group --region $R --log-group-name /ecs/lab-firelens-router
aws iam delete-role-policy --role-name lab-oslog-exec --policy-name cw-creategroup
aws iam detach-role-policy --role-name lab-oslog-exec --policy-arn arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy
aws iam delete-role --role-name lab-oslog-exec
aws iam delete-role-policy --role-name lab-oslog-task --policy-name es-http
aws iam delete-role --role-name lab-oslog-task
# ENI 정리 대기 후 VPC
until [ "$(aws ec2 describe-network-interfaces --region $R --filters Name=vpc-id,Values=$VPC --query 'length(NetworkInterfaces)' --output text)" = "0" ]; do sleep 15; done
aws ec2 delete-subnet --region $R --subnet-id $SUB
aws ec2 delete-route-table --region $R --route-table-id $RT
aws ec2 detach-internet-gateway --region $R --vpc-id $VPC --internet-gateway-id $IGW
aws ec2 delete-internet-gateway --region $R --internet-gateway-id $IGW
aws ec2 delete-vpc --region $R --vpc-id $VPC
echo DOWNDONE
