# Loki 멀티테넌트 (X-Scope-OrgID)

네임스페이스/팀별로 로그를 격리. Loki 의 멀티테넌시 = `X-Scope-OrgID` 헤더로 테넌트 분리.
★ 검증은 사용자 cncf/k8s 패스에서(EKS + `../../../cncf/loki/`, `../../../cncf/grafana/`).

## Loki (auth_enabled: true)

```yaml
# loki config
auth_enabled: true    # 이게 켜져야 X-Scope-OrgID 로 테넌트 분리(끄면 단일 'fake' 테넌트)
```

## Fluent Bit (테넌트별 헤더 주입)

```ini
[OUTPUT]
    Name         loki
    Match        kube.team-a.*
    Host         loki.loki.svc
    Port         3100
    tenant_id    team-a          # → X-Scope-OrgID: team-a
    labels       job=fluentbit, $kubernetes['namespace_name']
[OUTPUT]
    Name         loki
    Match        kube.team-b.*
    Host         loki.loki.svc
    tenant_id    team-b
```

## Grafana (테넌트별 datasource)

각 팀 datasource 에 커스텀 헤더 `X-Scope-OrgID: team-a` 설정 → 그 테넌트 로그만 조회.

```logql
{namespace="team-a"} |= "ERROR"     # team-a datasource 로만 보임
```

## 함정

- `auth_enabled: true` 안 켜면 전부 `fake` 테넌트로 섞임.
- Fluent Bit `tenant_id` = Loki push 시 `X-Scope-OrgID` 헤더.
- Grafana datasource 마다 `X-Scope-OrgID` 커스텀 헤더 필수(안 넣으면 조회 안 됨).
- 기반: `../../../cncf/loki/`, `../../../cncf/grafana/`, `../../../k8s/logging/`.
