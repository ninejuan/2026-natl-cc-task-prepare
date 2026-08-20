# Cloud Map (Service Discovery)

**트리거 문구** — "서비스 디스커버리", "서비스 이름으로 접근", "마이크로서비스 간 통신", "동적 등록".

**전제**
```bash
export R=ap-northeast-2
```

ECS 서비스 자동 등록은 `../tier2/ecs.md` 케이스 B 에서 실검증. 여기선 네임스페이스 종류 + EC2/직접 등록.

---

## 네임스페이스 3종

```bash
# 1) private DNS (VPC 내부 DNS. 가장 흔함) — 비동기
OP=$(aws servicediscovery create-private-dns-namespace --region $R --name lab.local --vpc $VPC --query OperationId --output text)
NSID=$(aws servicediscovery get-operation --region $R --operation-id $OP --query 'Operation.Targets.NAMESPACE' --output text)

# 2) public DNS (인터넷 도메인)
aws servicediscovery create-public-dns-namespace --region $R --name lab.example.com

# 3) HTTP only (DNS 없이 API discovery — DiscoverInstances)
aws servicediscovery create-http-namespace --region $R --name lab-http
```

## ECS 자동 등록 [검증됨]

`../tier2/ecs.md` 케이스 B — ECS service 에 `--service-registries` 연결하면 task IP 가 A레코드로 자동 등록/해제. 검증: task IP(10.0.139.110) 자동 등록 확인.

## EC2 / 직접 등록

```bash
# CloudMap service (A레코드)
SD=$(aws servicediscovery create-service --region $R --name web \
  --namespace-id $NSID --dns-config "NamespaceId=$NSID,DnsRecords=[{Type=A,TTL=60}]" \
  --query 'Service.Id' --output text)

# 인스턴스 직접 등록 (EC2 등 non-ECS)
aws servicediscovery register-instance --region $R --service-id $SD \
  --instance-id web-1 --attributes AWS_INSTANCE_IPV4=10.0.1.50

# 조회: DNS (web.lab.local) 또는 API
aws servicediscovery discover-instances --region $R --namespace-name lab.local --service-name web \
  --query 'Instances[].Attributes.AWS_INSTANCE_IPV4' --output text
```

## 검증

```bash
aws servicediscovery list-namespaces --region $R --query 'Namespaces[].[Name,Type]' --output text
aws servicediscovery list-services --region $R --query 'Services[].[Name,Id]' --output text
aws servicediscovery list-instances --region $R --service-id $SD --query 'Instances[].Attributes.AWS_INSTANCE_IPV4' --output text
# VPC 내 EC2 에서: dig +short web.lab.local  또는  curl http://web.lab.local
```

## Terraform

```hcl
resource "aws_service_discovery_private_dns_namespace" "ns" {
  name = "lab.local"
  vpc  = var.vpc_id
}
resource "aws_service_discovery_service" "web" {
  name = "web"
  dns_config {
    namespace_id = aws_service_discovery_private_dns_namespace.ns.id
    dns_records {
      type = "A"
      ttl  = 60
    }
  }
  health_check_custom_config { failure_threshold = 1 }
}
# ECS 연동: aws_ecs_service.service_registries { registry_arn = aws_service_discovery_service.web.arn }
```
> TF 는 네임스페이스 비동기 생성을 자동으로 기다린다(CLI 는 operation 폴링 필요).

## Console 팁

- **네임스페이스/서비스 생성**: Cloud Map 콘솔에서 타입(DNS private/public/HTTP)·레코드를 폼으로.
- **ECS 연동**: ECS 서비스 생성 마법사의 "Service discovery" 섹션에서 네임스페이스·서비스를 선택하면 자동 등록.
- **등록된 인스턴스 조회**: 서비스 콘솔에서 현재 등록된 IP 목록.

## 참고 문서

- Cloud Map 개발자 가이드: https://docs.aws.amazon.com/cloud-map/latest/dg/
- Terraform `aws_service_discovery_service`: https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/service_discovery_service

## 함정

- **네임스페이스 생성은 비동기** — create → operation SUCCESS 대기 → NSID. (TF 는 자동 대기)
- **private DNS 는 VPC 연결** — 그 VPC 안에서만 해석.
- **삭제 순서**: instance dereg → service 삭제 → namespace 삭제. service 남으면 namespace 삭제 실패.
- **ECS 연결 시 health check custom** — `--health-check-custom-config FailureThreshold=1`. ECS 가 상태를 CloudMap 에 보고.
- HTTP 네임스페이스는 DNS 없음 — `discover-instances` API 로만.

## 정리
```bash
for iid in $(aws servicediscovery list-instances --region $R --service-id $SD --query 'Instances[].Id' --output text); do
  aws servicediscovery deregister-instance --region $R --service-id $SD --instance-id $iid; done
aws servicediscovery delete-service --region $R --id $SD
aws servicediscovery delete-namespace --region $R --id $NSID
```
