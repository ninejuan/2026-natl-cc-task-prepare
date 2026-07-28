# VPC 최단 구축

**언제 쓰나** — "VPC를 생성하고 Public/Private 서브넷을 구성합니다", "인터넷을 경유하지 않아야 합니다", "Flow Log를 활성화합니다"

**소요** 서브넷·IGW·RT까지 1분 / NAT까지 3분 (NAT가 유일한 대기 요소)

**전제** `export P=<비번호> R=<리전>`

---

## 5분 컷 — 2AZ Public/Private (NAT 포함)

이름 규칙만 과제지에 맞게 바꿔 쓴다. `NAME`이 접두어다.

```bash
export R=${R:-ap-northeast-2} NAME=skills VPC_CIDR=10.0.0.0/16
AZS=($(aws ec2 describe-availability-zones --region $R --query 'AvailabilityZones[0:2].ZoneName' --output text))
t() { echo "ResourceType=$1,Tags=[{Key=Name,Value=$2}]"; }   # 태그 없으면 채점이 못 찾는다

VPC=$(aws ec2 create-vpc --region $R --cidr-block $VPC_CIDR \
  --tag-specifications "$(t vpc $NAME-vpc)" --query Vpc.VpcId --output text)
aws ec2 modify-vpc-attribute --region $R --vpc-id $VPC --enable-dns-hostnames
aws ec2 modify-vpc-attribute --region $R --vpc-id $VPC --enable-dns-support

IGW=$(aws ec2 create-internet-gateway --region $R \
  --tag-specifications "$(t internet-gateway $NAME-igw)" --query InternetGateway.InternetGatewayId --output text)
aws ec2 attach-internet-gateway --region $R --internet-gateway-id $IGW --vpc-id $VPC

RT_PUB=$(aws ec2 create-route-table --region $R --vpc-id $VPC \
  --tag-specifications "$(t route-table $NAME-rt-pub)" --query RouteTable.RouteTableId --output text)
aws ec2 create-route --region $R --route-table-id $RT_PUB --destination-cidr-block 0.0.0.0/0 --gateway-id $IGW

i=0
for AZ in "${AZS[@]}"; do
  s=${AZ: -1}   # a, b
  PUB=$(aws ec2 create-subnet --region $R --vpc-id $VPC --availability-zone $AZ \
    --cidr-block 10.0.$i.0/24 --tag-specifications "$(t subnet $NAME-subnet-pub-$s)" --query Subnet.SubnetId --output text)
  PRIV=$(aws ec2 create-subnet --region $R --vpc-id $VPC --availability-zone $AZ \
    --cidr-block 10.0.$((i+10)).0/24 --tag-specifications "$(t subnet $NAME-subnet-priv-$s)" --query Subnet.SubnetId --output text)
  aws ec2 modify-subnet-attribute --region $R --subnet-id $PUB --map-public-ip-on-launch
  aws ec2 associate-route-table --region $R --route-table-id $RT_PUB --subnet-id $PUB
  eval "PUB_$s=$PUB; PRIV_$s=$PRIV"
  i=$((i+1))
done

# NAT (3분 대기) — 여기서 던져놓고 다른 항목 하러 간다
EIP=$(aws ec2 allocate-address --region $R --domain vpc --query AllocationId --output text)
NAT=$(aws ec2 create-nat-gateway --region $R --subnet-id $PUB_a --allocation-id $EIP \
  --tag-specifications "$(t natgateway $NAME-nat-a)" --query NatGateway.NatGatewayId --output text)

for AZ in "${AZS[@]}"; do
  s=${AZ: -1}
  RT=$(aws ec2 create-route-table --region $R --vpc-id $VPC \
    --tag-specifications "$(t route-table $NAME-rt-priv-$s)" --query RouteTable.RouteTableId --output text)
  eval "aws ec2 associate-route-table --region $R --route-table-id $RT --subnet-id \$PRIV_$s"
  eval "RT_PRIV_$s=$RT"
done

aws ec2 wait nat-gateway-available --region $R --nat-gateway-ids $NAT
for AZ in "${AZS[@]}"; do
  s=${AZ: -1}
  eval "aws ec2 create-route --region $R --route-table-id \$RT_PRIV_$s --destination-cidr-block 0.0.0.0/0 --nat-gateway-id $NAT"
done
echo "VPC=$VPC PUB=$PUB_a,$PUB_b PRIV=$PRIV_a,$PRIV_b NAT=$NAT"
```

과제지가 3AZ를 요구하면 `[0:2]` → `[0:3]`, NAT를 AZ별로 요구하면 NAT 블록을 루프 안으로 옮긴다.

## Flow Log — S3 대상이 제일 빠르다

CloudWatch Logs 대상은 IAM Role을 먼저 만들어야 한다. **S3 대상은 Role이 필요 없다.** 과제지가 대상을 지정하지 않으면 S3로 간다.

```bash
BUCKET=$NAME-flowlog-$(aws sts get-caller-identity --query Account --output text)
aws s3api create-bucket --bucket $BUCKET --region $R --create-bucket-configuration LocationConstraint=$R
aws ec2 create-flow-logs --region $R --resource-type VPC --resource-ids $VPC --traffic-type ALL \
  --log-destination-type s3 --log-destination arn:aws:s3:::$BUCKET
```

CloudWatch Logs를 강제하면:

```bash
aws logs create-log-group --region $R --log-group-name /$NAME/vpc/flowlogs
cat > /tmp/fl-trust.json <<'J'
{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":"vpc-flow-logs.amazonaws.com"},"Action":"sts:AssumeRole"}]}
J
cat > /tmp/fl-perm.json <<'J'
{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Action":["logs:CreateLogStream","logs:PutLogEvents","logs:DescribeLogStreams","logs:CreateLogGroup"],"Resource":"*"}]}
J
ROLE=$(aws iam create-role --role-name $NAME-flowlog-role \
  --assume-role-policy-document file:///tmp/fl-trust.json --query Role.Arn --output text)
aws iam put-role-policy --role-name $NAME-flowlog-role --policy-name inline --policy-document file:///tmp/fl-perm.json
aws ec2 create-flow-logs --region $R --resource-type VPC --resource-ids $VPC --traffic-type ALL \
  --log-destination-type cloud-watch-logs --log-group-name /$NAME/vpc/flowlogs --deliver-logs-permission-arn $ROLE
```

## "인터넷을 경유하지 않아야 합니다" → VPC Endpoint

Private 서브넷의 파드/EC2가 이미지 pull, 로그 전송, API 호출을 인터넷 없이 하게 만든다.

```bash
# Gateway 타입 (무료) — 라우팅 테이블에 붙는다
for svc in s3 dynamodb; do
  aws ec2 create-vpc-endpoint --region $R --vpc-id $VPC --vpc-endpoint-type Gateway \
    --service-name com.amazonaws.$R.$svc --route-table-ids $RT_PRIV_a $RT_PRIV_b \
    --tag-specifications "$(t vpc-endpoint $NAME-vpce-$svc)"
done

# Interface 타입 (시간당 과금) — 서브넷 + SG + Private DNS
SG_VPCE=$(aws ec2 create-security-group --region $R --group-name $NAME-vpce-sg \
  --description vpce --vpc-id $VPC --query GroupId --output text)
aws ec2 authorize-security-group-ingress --region $R --group-id $SG_VPCE \
  --protocol tcp --port 443 --cidr $VPC_CIDR
for svc in ecr.api ecr.dkr logs sts elasticloadbalancing ec2 secretsmanager ssm ssmmessages ec2messages; do
  aws ec2 create-vpc-endpoint --region $R --vpc-id $VPC --vpc-endpoint-type Interface \
    --service-name com.amazonaws.$R.$svc --subnet-ids $PRIV_a $PRIV_b \
    --security-group-ids $SG_VPCE --private-dns-enabled \
    --tag-specifications "$(t vpc-endpoint $NAME-vpce-${svc//./-})" >/dev/null
done
```

**ECR로 이미지를 당기려면 `ecr.api` + `ecr.dkr` + **S3 Gateway 엔드포인트**가 셋 다 필요하다.** 레이어가 S3에 있어서 S3 엔드포인트 없으면 pull이 실패한다. 가장 자주 밟는 함정.

## Terraform

```hcl
locals {
  name = "skills"
  azs  = slice(data.aws_availability_zones.this.names, 0, 2)
}
data "aws_availability_zones" "this" { state = "available" }

resource "aws_vpc" "this" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true
  tags                 = { Name = "${local.name}-vpc" }
}

resource "aws_subnet" "pub" {
  for_each                = { for i, az in local.azs : substr(az, -1, 1) => { i = i, az = az } }
  vpc_id                  = aws_vpc.this.id
  availability_zone       = each.value.az
  cidr_block              = cidrsubnet(aws_vpc.this.cidr_block, 8, each.value.i)
  map_public_ip_on_launch = true
  tags                    = { Name = "${local.name}-subnet-pub-${each.key}" }
}

resource "aws_subnet" "priv" {
  for_each          = { for i, az in local.azs : substr(az, -1, 1) => { i = i, az = az } }
  vpc_id            = aws_vpc.this.id
  availability_zone = each.value.az
  cidr_block        = cidrsubnet(aws_vpc.this.cidr_block, 8, each.value.i + 10)
  tags              = { Name = "${local.name}-subnet-priv-${each.key}" }
}

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id
  tags   = { Name = "${local.name}-igw" }
}

resource "aws_eip" "nat" { domain = "vpc" }

resource "aws_nat_gateway" "this" {
  allocation_id = aws_eip.nat.id
  subnet_id     = values(aws_subnet.pub)[0].id
  tags          = { Name = "${local.name}-nat-a" }
  depends_on    = [aws_internet_gateway.this]
}

resource "aws_route_table" "pub" {
  vpc_id = aws_vpc.this.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.this.id
  }
  tags = { Name = "${local.name}-rt-pub" }
}

resource "aws_route_table" "priv" {
  for_each = aws_subnet.priv
  vpc_id   = aws_vpc.this.id
  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.this.id
  }
  tags = { Name = "${local.name}-rt-priv-${each.key}" }
}

resource "aws_route_table_association" "pub" {
  for_each       = aws_subnet.pub
  subnet_id      = each.value.id
  route_table_id = aws_route_table.pub.id
}

resource "aws_route_table_association" "priv" {
  for_each       = aws_subnet.priv
  subnet_id      = each.value.id
  route_table_id = aws_route_table.priv[each.key].id
}
```

EKS를 올릴 거면 서브넷에 태그를 추가한다. `kubernetes.io/role/elb = 1`(public), `kubernetes.io/role/internal-elb = 1`(private). **없으면 ALB Controller가 서브넷을 못 고른다.**

## 검증

```bash
aws ec2 describe-vpcs --region $R --filters Name=tag:Name,Values=$NAME-vpc \
  --query 'Vpcs[].[VpcId,CidrBlock,EnableDnsHostnames]' --output text
aws ec2 describe-subnets --region $R --filters Name=vpc-id,Values=$VPC \
  --query 'Subnets[].[Tags[?Key==`Name`].Value|[0],CidrBlock,AvailabilityZone,MapPublicIpOnLaunch]' --output table
aws ec2 describe-route-tables --region $R --filters Name=vpc-id,Values=$VPC \
  --query 'RouteTables[].{Name:Tags[?Key==`Name`].Value|[0],Main:Associations[?Main].Main|[0],Default:Routes[?DestinationCidrBlock==`0.0.0.0/0`].[GatewayId,NatGatewayId][],Subnets:length(Associations[?SubnetId!=null])}' --output json
aws ec2 describe-flow-logs --region $R --filter Name=resource-id,Values=$VPC \
  --query 'FlowLogs[].[FlowLogStatus,TrafficType,LogDestinationType]' --output text
aws ec2 describe-vpc-endpoints --region $R --filters Name=vpc-id,Values=$VPC \
  --query 'VpcEndpoints[].[ServiceName,VpcEndpointType,State]' --output text
```

Private 서브넷에서 실제로 인터넷이 안 나가는지:

```bash
# 라우팅 테이블에 IGW/NAT가 없어야 하는 문제라면 (DB 서브넷 등)
aws ec2 describe-route-tables --region $R --filters Name=association.subnet-id,Values=$PRIV_a \
  --query 'RouteTables[].Routes[]' --output json
```

## 함정

- **`Name` 태그 누락** → 채점이 `--filters Name=tag:Name`으로 찾으므로 그대로 0점. `create-*`에 `--tag-specifications`를 붙이는 습관을 들여라. 나중에 붙이려면 리소스마다 `create-tags`를 또 돌려야 한다.
- **Zero Subnet 허용 여부.** 과제지가 "0, 1, 2번째"라고 쓰면 `10.0.0.0/24`부터 시작한다. 무의식적으로 1부터 시작하지 마라.
- **`map-public-ip-on-launch`** 안 켜면 Public 서브넷의 EC2에 퍼블릭 IP가 안 붙고, 채점이 `PublicIpAddress`로 curl하는 항목이 전부 실패한다.
- **NAT를 Private 서브넷에 만들면** 인터넷이 안 나간다. 반드시 Public 서브넷에.
- **DNS hostnames/support** 안 켜면 RDS·DocumentDB·VPC 엔드포인트의 Private DNS가 안 먹는다.
- **ECR pull 실패**: Interface 엔드포인트만 만들고 S3 Gateway 엔드포인트를 빼먹은 경우.
- **삭제 순서**: NAT → EIP 해제 → IGW detach → 서브넷 → VPC. NAT가 살아 있으면 서브넷이 안 지워진다.
