#!/usr/bin/env bash
# 기존 스택의 리소스 ID를 전수 스캔해 addon.env 로 떨군다.
# 1과제 추가 항목이 "과제지에서 만든 VPC 안에 ~" 를 요구할 때, 후보 스택이 뭐든 상관없이 ID를 확보하는 용도.
#
#   ./discover.sh [리전]        기본값 ap-northeast-2
#   source addon.env
set -uo pipefail
export AWS_PAGER=""

R="${1:-${R:-ap-northeast-2}}"
OUT="${OUT:-addon.env}"
a() { aws --region "$R" "$@" 2>/dev/null; }
# 리소스 이름 → 셸 변수명
key() { echo "$1" | tr '[:lower:]' '[:upper:]' | sed 's/[^A-Z0-9]/_/g'; }

{
echo "# discover.sh $(date -u +%FT%TZ) region=$R account=$(aws sts get-caller-identity --query Account --output text 2>/dev/null)"
echo "export R=$R"

emit() { # emit <PREFIX> <name> <id>
  [ -n "${3:-}" ] && [ "$3" != "None" ] && echo "export $1_$(key "$2")=$3"
}

# --- VPC / 서브넷 / SG / 라우팅 ---
a ec2 describe-vpcs --filters Name=is-default,Values=false \
  --query 'Vpcs[].[Tags[?Key==`Name`].Value|[0],VpcId,CidrBlock]' --output text |
while read -r name id cidr; do
  emit VPC "${name:-noname}" "$id"; emit VPCCIDR "${name:-noname}" "$cidr"
done

a ec2 describe-subnets --query 'Subnets[].[Tags[?Key==`Name`].Value|[0],SubnetId]' --output text |
while read -r name id; do emit SUBNET "${name:-$id}" "$id"; done

a ec2 describe-security-groups --query 'SecurityGroups[].[GroupName,GroupId]' --output text |
while read -r name id; do emit SG "$name" "$id"; done

a ec2 describe-route-tables --query 'RouteTables[].[Tags[?Key==`Name`].Value|[0],RouteTableId]' --output text |
while read -r name id; do emit RT "${name:-$id}" "$id"; done

# 서브넷 묶음 — 새 리소스를 기존 VPC에 넣을 때 그대로 쓴다
for tier in pub priv private public; do
  ids=$(a ec2 describe-subnets --filters "Name=tag:Name,Values=*${tier}*" --query 'Subnets[].SubnetId' --output text | tr '\t' ',')
  [ -n "$ids" ] && echo "export SUBNETS_$(key "$tier")=$ids"
done

# --- EKS ---
for c in $(a eks list-clusters --query 'clusters[]' --output text); do
  echo "export EKS_$(key "$c")=$c"
  a eks describe-cluster --name "$c" --query 'cluster.[endpoint,version,resourcesVpcConfig.vpcId,identity.oidc.issuer]' --output text |
  while read -r ep ver vpc oidc; do
    emit EKS_ENDPOINT "$c" "$ep"; emit EKS_VERSION "$c" "$ver"
    emit EKS_VPC "$c" "$vpc";     emit EKS_OIDC "$c" "$oidc"
  done
  ng=$(a eks list-nodegroups --cluster-name "$c" --query 'nodegroups[]' --output text | tr '\t' ',')
  [ -n "$ng" ] && echo "export EKS_NODEGROUPS_$(key "$c")=$ng"
done

# --- 로드밸런서 ---
a elbv2 describe-load-balancers --query 'LoadBalancers[].[LoadBalancerName,LoadBalancerArn,DNSName,Scheme]' --output text |
while read -r name arn dns scheme; do
  emit ALB_ARN "$name" "$arn"; emit ALB_DNS "$name" "$dns"; emit ALB_SCHEME "$name" "$scheme"
done
a elbv2 describe-target-groups --query 'TargetGroups[].[TargetGroupName,TargetGroupArn]' --output text |
while read -r name arn; do emit TG "$name" "$arn"; done

# --- CloudFront (글로벌) : 채점이 Comment 로 찾으므로 Comment 를 키로 쓴다 ---
aws cloudfront list-distributions --query 'DistributionList.Items[].[Comment,Id,DomainName]' --output text 2>/dev/null |
while read -r comment id domain; do
  emit CF_ID "${comment:-$id}" "$id"; emit CF_DOMAIN "${comment:-$id}" "$domain"
done

# --- 데이터 / 스토리지 / 컴퓨팅 ---
for t in $(a dynamodb list-tables --query 'TableNames[]' --output text); do echo "export DDB_$(key "$t")=$t"; done
for b in $(aws s3api list-buckets --query 'Buckets[].Name' --output text 2>/dev/null); do echo "export S3_$(key "$b")=$b"; done
for f in $(a lambda list-functions --query 'Functions[].FunctionName' --output text); do echo "export LAMBDA_$(key "$f")=$f"; done
for r in $(a ecr describe-repositories --query 'repositories[].repositoryName' --output text); do
  emit ECR "$r" "$(a ecr describe-repositories --repository-names "$r" --query 'repositories[0].repositoryUri' --output text)"
done
a kms list-aliases --query 'Aliases[?starts_with(AliasName,`alias/`) && !starts_with(AliasName,`alias/aws/`)].[AliasName,TargetKeyId]' --output text |
while read -r alias id; do emit KMS "${alias#alias/}" "$id"; done

a ec2 describe-instances --filters Name=instance-state-name,Values=running \
  --query 'Reservations[].Instances[].[Tags[?Key==`Name`].Value|[0],InstanceId,PrivateIpAddress,PublicIpAddress]' --output text |
while read -r name id priv pub; do
  emit EC2 "${name:-$id}" "$id"; emit EC2_PRIVIP "${name:-$id}" "$priv"; emit EC2_PUBIP "${name:-$id}" "$pub"
done
} > "$OUT"

echo "wrote $OUT ($(grep -c '^export' "$OUT") vars, region=$R)"
grep '^export' "$OUT" | sed 's/^export /  /' | sort
echo
echo "적용: source $OUT"
