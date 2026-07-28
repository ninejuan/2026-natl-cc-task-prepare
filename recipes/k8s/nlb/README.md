# Service → NLB

`type: LoadBalancer` 에 어노테이션을 붙이면 LBC 가 NLB 를 만든다. L4 그대로 넘겨야 할 때(TCP·gRPC·Istio Gateway) 쓴다.

ALB 가 필요하면 [`../ingress-alb/`](../ingress-alb/). HTTP 앱에 NLB 를 쓰면 경로 라우팅·WAF 연결을 못 한다.

## 적용

```bash
kubectl apply -f service.yaml
kubectl get svc app-nlb -n app -w      # EXTERNAL-IP 에 NLB DNS. 2~4분
```

## 확인

```bash
NLB=$(kubectl get svc app-nlb -n app -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
curl -s -o /dev/null -w '%{http_code}\n' "http://$NLB/health"

aws elbv2 describe-load-balancers --names skills-nlb \
  --query 'LoadBalancers[0].[Type,Scheme,State.Code]' --output text
aws elbv2 describe-target-health --target-group-arn \
  $(aws elbv2 describe-target-groups --query 'TargetGroups[?contains(TargetGroupName,`skills-nlb`)].TargetGroupArn|[0]' --output text) \
  --query 'TargetHealthDescriptions[].TargetHealth.State' --output text
```

## 어노테이션

| 어노테이션 | 의미 |
|---|---|
| `aws-load-balancer-type: external` | LBC 가 관리한다는 표시. **없으면 레거시 in-tree 컨트롤러가 CLB 를 만든다** |
| `nlb-target-type: ip` | 파드 직접(권장). `instance` 는 NodePort 경유 |
| `aws-load-balancer-scheme` | `internet-facing` / `internal` |
| `aws-load-balancer-name` | 과제지가 지정한 이름 |
| `aws-load-balancer-healthcheck-protocol` | `TCP`(기본) / `HTTP`. HTTP 면 경로도 지정 |
| `aws-load-balancer-healthcheck-path` | `/health` |
| `aws-load-balancer-attributes` | `load_balancing.cross_zone.enabled=true` 등 |
| `aws-load-balancer-eip-allocations` | 고정 IP 가 필요할 때 (AZ 수와 개수 일치) |

`spec.loadBalancerClass: service.k8s.aws/nlb` 를 함께 쓰면 어노테이션 없이도 LBC 가 처리한다. 둘 다 넣어두는 게 안전하다.

## 함정

- **`aws-load-balancer-type: external` 을 빼면 CLB 가 생긴다.** 과제지가 NLB 를 요구했는데 CLB 가 만들어지면 0점이다. `describe-load-balancers` 의 `Type` 을 확인하라.
- **cross-zone 은 NLB 기본이 꺼져 있다.** AZ 별로 타깃 수가 다르면 트래픽이 불균등해진다. 명시적으로 켜라.
- **헬스체크 기본이 TCP** 라 앱이 죽어도 포트가 열려 있으면 healthy 로 나온다. HTTP 로 바꿔라.
- **NLB 는 SG 를 최근에야 지원**한다. 구버전 동작을 기대하면 파드 SG 에 클라이언트 IP 를 직접 허용해야 할 수 있다.
- Service 를 지워도 NLB 가 남는 경우가 있다. 잔재를 확인하라.
