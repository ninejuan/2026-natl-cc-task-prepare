#!/usr/bin/env bash
# 케이스 04 — ECS Container Insights. 클러스터 CPU/메모리/네트워크 메트릭 자동수집. 실검증됨.
set -euo pipefail
export R=${R:-ap-northeast-2}

# 신규 클러스터에 켜기
aws ecs create-cluster --region $R --cluster-name lab-ci \
  --settings name=containerInsights,value=enabled >/dev/null

# 기존 클러스터에 켜기: update-cluster-settings
# aws ecs update-cluster-settings --region $R --cluster <name> --settings name=containerInsights,value=enabled

echo "설정 확인(enabled 여야):"
aws ecs describe-clusters --region $R --clusters lab-ci --include SETTINGS \
  --query 'clusters[0].settings[?name==`containerInsights`].value' --output text   # enabled (실측)
# → 태스크 실행 시 ECS/ContainerInsights 네임스페이스에 CpuUtilized/MemoryUtilized/NetworkRx 등 메트릭.
#   대시보드/알람 대상: 케이스 01(dashboard-alarm) 참조.

# 정리
aws ecs delete-cluster --region $R --cluster lab-ci >/dev/null
