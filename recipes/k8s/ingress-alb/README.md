# Ingress → ALB

AWS Load Balancer Controller 가 Ingress 를 보고 ALB 를 만든다. 설치는 [`../README.md`](../README.md) 참조.

## 적용

```bash
kubectl apply -f ingressclass.yaml     # 한 번만. LBC 차트가 이미 만들었을 수도 있다
kubectl apply -f ingress.yaml
kubectl get ingress -n app -w          # ADDRESS 에 ALB DNS 가 뜰 때까지 2~4분
```

## 파일

| 파일 | 케이스 |
|---|---|
| `ingressclass.yaml` | IngressClass (controller: `ingress.k8s.aws/alb`) |
| `ingress.yaml` | Ingress. 어노테이션 주석으로 HTTPS·그룹·서브넷 지정까지 포함 |
| `targetgroupbinding.yaml` | ALB 를 terraform 으로 만들고 파드만 붙일 때 |

## 두 갈래

**① Ingress 로 ALB 를 만든다** — 컨트롤러가 ALB·타깃그룹·리스너를 다 만든다. 빠르다.

**② terraform 으로 ALB 를 만들고 TargetGroupBinding 으로 파드를 붙인다** — 과제지가 ALB 이름·리스너 규칙을 세밀하게 지정하거나, CloudFront VPC Origin 처럼 ALB 를 다른 리소스와 엮어야 할 때. 1과제가 보통 이쪽이다.

②를 택하는 신호: 과제지에 "ALB/TG Name" 이 명시돼 있고 리스너 규칙(GET 은 Lambda, POST 는 앱)이 지정된 경우.

## 어노테이션 핵심

| 어노테이션 | 의미 |
|---|---|
| `scheme` | `internet-facing` / `internal`. CloudFront VPC Origin 을 쓰면 `internal` |
| `target-type` | `ip` = 파드 직접(권장). `instance` = NodePort 경유 |
| `load-balancer-name` | 과제지가 지정한 ALB 이름. **없으면 자동 생성 이름이라 채점이 못 찾는다** |
| `listen-ports` | `'[{"HTTP":80}]'` / `'[{"HTTP":80},{"HTTPS":443}]'` |
| `certificate-arn` | HTTPS 리스너용 ACM 인증서 |
| `ssl-redirect` | `'443'` 이면 HTTP → HTTPS 리다이렉트 |
| `group.name` | 여러 Ingress 를 한 ALB 로 합친다 |
| `group.order` | 그룹 내 규칙 평가 순서 |
| `healthcheck-path` | 기본 `/`. 앱이 `/health` 면 반드시 지정 |
| `target-group-attributes` | `deregistration_delay.timeout_seconds=15` 등 |
| `subnets` | 자동 탐색 실패 시 직접 지정 |
| `tags` | `Name=...` — 채점이 태그로 찾는 경우 |

## 확인

```bash
kubectl get ingress app-ing -n app -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'; echo
ALB=$(kubectl get ingress app-ing -n app -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
curl -s -o /dev/null -w '%{http_code}\n' "http://$ALB/health"

aws elbv2 describe-load-balancers --names skills-alb \
  --query 'LoadBalancers[0].[Scheme,Type,State.Code]' --output text
aws elbv2 describe-target-health \
  --target-group-arn $(aws elbv2 describe-target-groups --query 'TargetGroups[?contains(TargetGroupName,`skills`)].TargetGroupArn|[0]' --output text) \
  --query 'TargetHealthDescriptions[].TargetHealth.State' --output text
```

## ALB 가 안 생길 때

이 순서로 본다. 대부분 1번이나 2번이다.

```bash
kubectl describe ingress app-ing -n app | sed -n '/Events:/,$p'
kubectl -n kube-system logs deploy/aws-load-balancer-controller --tail=50 | grep -i error
```

1. **서브넷 태그 없음** — `kubernetes.io/role/elb`(public) / `internal-elb`(private). 가장 흔하다.
2. **IRSA 권한 없음** — 컨트롤러 SA 에 정책이 안 붙었다.
3. **`ingressClassName` 누락** — `alb` 를 명시해야 한다.
4. **서브넷이 2개 AZ 미만** — ALB 는 최소 2 AZ 가 필요하다.

## 함정

- **`target-type: ip` 면 파드 SG 가 ALB SG 로부터 인바운드를 허용해야 한다.** 컨트롤러가 자동으로 노드/파드 SG 규칙을 넣지만, 직접 만든 SG 를 쓰면 수동으로 열어야 한다.
- **`load-balancer-name` 을 안 주면** `k8s-app-appalb-xxxx` 같은 이름이 된다. 과제지가 이름을 지정하면 반드시 넣어라.
- **healthcheck 경로 기본값이 `/`** 다. 앱이 `/` 에서 404 를 내면 타깃이 unhealthy 로 남고 502 가 온다.
- **Ingress 를 지워도 ALB 가 남는 경우**가 있다 (finalizer 실패). `aws elbv2 describe-load-balancers` 로 잔재를 확인하라 — 미사용 리소스는 감점이다.
- **`group.name` 을 쓰면 Ingress 를 지워도 ALB 가 유지**된다. 그룹의 마지막 Ingress 를 지워야 ALB 가 사라진다.
- HTTPS 를 쓰면 인증서는 **ALB 와 같은 리전**의 ACM 이어야 한다. CloudFront 용(us-east-1)과 다르다.
