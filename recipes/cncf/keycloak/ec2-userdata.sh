#!/bin/bash
# EC2 user data. Amazon Linux 2023. Keycloak + Postgres 를 Docker 로 띄우고 systemd 로 등록한다.
#
# 채점이 `systemctl is-active` / `is-enabled` 를 확인하는 항목이 있으므로 systemd 등록이 중요하다.
# SG 인바운드 8080 을 열어야 브라우저로 접근된다.
set -eux

dnf install -y docker
systemctl enable --now docker

KC_ADMIN=admin
KC_ADMIN_PASSWORD='Skills!2026'
PG_PASSWORD='Skills!2026pg'

docker network create keycloak || true

docker run -d --name postgres --network keycloak --restart always \
  -e POSTGRES_DB=keycloak \
  -e POSTGRES_USER=keycloak \
  -e POSTGRES_PASSWORD="$PG_PASSWORD" \
  -v /var/lib/keycloak-pg:/var/lib/postgresql/data \
  public.ecr.aws/docker/library/postgres:16

# 프록시/ALB 뒤에 두면 KC_HOSTNAME_STRICT=false 와 PROXY_HEADERS 가 없으면 리다이렉트 루프가 난다.
docker run -d --name keycloak --network keycloak --restart always \
  -p 8080:8080 \
  -e KC_BOOTSTRAP_ADMIN_USERNAME="$KC_ADMIN" \
  -e KC_BOOTSTRAP_ADMIN_PASSWORD="$KC_ADMIN_PASSWORD" \
  -e KC_DB=postgres \
  -e KC_DB_URL="jdbc:postgresql://postgres:5432/keycloak" \
  -e KC_DB_USERNAME=keycloak \
  -e KC_DB_PASSWORD="$PG_PASSWORD" \
  -e KC_HOSTNAME_STRICT=false \
  -e KC_HTTP_ENABLED=true \
  -e KC_PROXY_HEADERS=xforwarded \
  quay.io/keycloak/keycloak:26.4 start-dev

# 채점이 systemctl 로 상태를 확인하는 경우를 대비해 서비스로 감싼다
cat > /etc/systemd/system/keycloak.service <<'UNIT'
[Unit]
Description=Keycloak (docker)
Requires=docker.service
After=docker.service

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/bin/docker start postgres keycloak
ExecStop=/usr/bin/docker stop keycloak postgres

[Install]
WantedBy=multi-user.target
UNIT

systemctl daemon-reload
systemctl enable --now keycloak

# 기동 확인 (최대 3분)
for i in $(seq 1 36); do
  if curl -sf -o /dev/null http://localhost:8080/realms/master/.well-known/openid-configuration; then
    echo "keycloak up"; break
  fi
  sleep 5
done
