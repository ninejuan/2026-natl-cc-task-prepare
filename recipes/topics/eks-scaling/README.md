# EKS Scaling 플레이북 (2026 #3)

**가이드 원문(2026 #3)** — "EKS 에 Pod 스케일링. Pod CPU 부하 → **HPA**, **Karpenter** 로 노드 추가, 또는 SQS 큐 길이 → **KEDA** 로 Pod 증설. ★ 채점 시 스케일링 시간·조건을 명확히."
- 필수: EKS / 선택: EC2, Fargate, Karpenter, KEDA, SQS

**트리거 문구** — "Pod 스케일링", "HPA", "Karpenter 노드 오토스케일", "KEDA SQS 기반 스케일", "부하 따라 증설".

**리전 격리** — 전용 클러스터(또는 지정). 예시 `ap-northeast-2`, EKS **1.35**.

**기반 카드**: HPA·Karpenter 매니페스트 `../../k8s/scaling/`, KEDA `../../cncf/keda/`, 클러스터 생성 `../../k8s/_cluster/`, SQS `../../aws/serverless/sqs-sns.md`.

---

## 스케일링 3층 (구분)

| 층 | 도구 | 트리거 | 대상 |
|---|---|---|---|
| Pod (지표) | **HPA** | CPU/메모리/커스텀 | replica 수 |
| Pod (이벤트) | **KEDA** | SQS 길이/cron/Prometheus | replica 수(0까지) |
| Node | **Karpenter** | 스케줄 불가 Pod | 노드 프로비저닝 |

## 케이스 인덱스

| # | 케이스 | 트리거 | 기반 |
|---|---|---|---|
| 01 | HPA CPU | CPU 50% → scale | k8s/scaling/hpa.yaml |
| 02 | HPA 메모리/커스텀 | memory/외부지표 | `cases/02-hpa-custom/` |
| 03 | Karpenter 노드 오토스케일 | pending pod → 노드 | k8s/scaling/karpenter-* |
| 04 | KEDA SQS 길이 | 큐 depth → pod(0→N) | cncf/keda |
| 05 | KEDA cron/prometheus | 스케줄/지표 | `cases/05-keda-variants/` |

## 채점 대응 (스케일링 시간 ≤3분)

- **HPA polling 15초**(기본) — `--horizontal-pod-autoscaler-sync-period`. 부하 주면 15~30초 내 반응.
- **KEDA pollingInterval 짧게**(예 15초) — SQS 메시지 12개 발행 → 스케일아웃 관찰(2026 후보 채점 방식).
- **Karpenter 노드 프로비저닝 ~1분** — 3분 안에 노드 Ready. `kubectl get nodes -l karpenter.sh/nodepool=<pool>`.
- 노드 **라벨** 필수(채점이 `kubectl get nodes -l` 로 필터).

## 검증 (채점자 문체)

```bash
aws eks update-kubeconfig --region $R --name lab-eks
kubectl get hpa -o jsonpath='{.items[0].spec.metrics[0].resource.target.averageUtilization}{"\n"}'
# 부하 → replica 증가 관찰 (3분)
kubectl run load --image=busybox -- /bin/sh -c "while true; do wget -q -O- http://svc; done"
for i in $(seq 1 12); do kubectl get deploy app -o jsonpath='{.status.replicas}'; sleep 10; done
# KEDA: SQS 12건 → ScaledObject replica
kubectl get scaledobject -o jsonpath='{.items[0].status.currentReplicas}'
# Karpenter: pending pod → 노드
kubectl get nodepool -o yaml; kubectl get nodes -l karpenter.sh/nodepool=lab
```

## 함정

- **metrics-server 필수**(HPA) — 없으면 HPA `unknown`. EKS 에 설치.
- **KEDA 는 operator 설치** + ScaledObject. scale-to-0 은 KEDA 만(HPA 는 최소 1).
- **Karpenter 는 IRSA/Pod Identity + NodePool + EC2NodeClass** — 서브넷/SG discovery 태그.
- **스케일 다운 지연** — HPA stabilizationWindow 로 플래핑 방지. 채점은 주로 스케일**아웃**.
- 노드 라벨 누락 → `kubectl get nodes -l` 0개 → 0점.
- EKS 1.35 API 버전 확인(autoscaling/v2 HPA).

## context7 참고

- KEDA: https://keda.sh/docs/latest/
- Karpenter: https://karpenter.sh/docs/
- HPA: https://kubernetes.io/docs/tasks/run-application/horizontal-pod-autoscale/
