#!/usr/bin/env bash
# CloudShell / Amazon Linux EC2에 현장 도구 설치. 이미 있는 건 건너뛴다.
set -euo pipefail

BIN="$HOME/.local/bin"
mkdir -p "$BIN"
case "$(uname -m)" in
  aarch64|arm64) ARCH=arm64; TFARCH=arm64 ;;
  *)             ARCH=amd64; TFARCH=amd64 ;;
esac
OS=linux

have() { command -v "$1" >/dev/null 2>&1; }
say()  { printf '\n== %s\n' "$*"; }

# CloudShell 홈은 1GB 제한. 다운로드 잔재를 남기지 않는다.
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT

if ! have kubectl; then
  say "kubectl"
  V=$(curl -sL https://dl.k8s.io/release/stable.txt)
  curl -sLo "$BIN/kubectl" "https://dl.k8s.io/release/$V/bin/$OS/$ARCH/kubectl"
  chmod +x "$BIN/kubectl"
fi

if ! have helm; then
  say "helm"
  curl -sL "https://get.helm.sh/helm-v3.19.0-$OS-$ARCH.tar.gz" | tar xz -C "$TMP"
  install -m755 "$TMP/$OS-$ARCH/helm" "$BIN/helm"
fi

if ! have eksctl; then
  say "eksctl"
  curl -sL "https://github.com/eksctl-io/eksctl/releases/latest/download/eksctl_${OS}_${ARCH}.tar.gz" | tar xz -C "$TMP"
  install -m755 "$TMP/eksctl" "$BIN/eksctl"
fi

if ! have terraform; then
  say "terraform"
  V=$(curl -s https://api.github.com/repos/hashicorp/terraform/releases/latest | grep -oP '"tag_name": "v\K[^"]+')
  curl -sLo "$TMP/tf.zip" "https://releases.hashicorp.com/terraform/$V/terraform_${V}_${OS}_${TFARCH}.zip"
  unzip -qo "$TMP/tf.zip" -d "$TMP"
  install -m755 "$TMP/terraform" "$BIN/terraform"
fi

if ! have yq; then
  say "yq"
  curl -sLo "$BIN/yq" "https://github.com/mikefarah/yq/releases/latest/download/yq_${OS}_${ARCH}"
  chmod +x "$BIN/yq"
fi

# kustomize 는 kubectl -k 로 대체한다 (kubectl 내장).

# dnf 계열이면 시스템 패키지로 해결되는 것들
if have dnf; then
  for pkg in jq easy-rsa postgresql16 openssl bind-utils; do
    have "${pkg%%1*}" || sudo dnf install -y "$pkg" >/dev/null 2>&1 || echo "  skip $pkg"
  done
fi

if ! have mongosh; then
  say "mongosh (DocumentDB 문제용)"
  curl -sL "https://downloads.mongodb.com/compass/mongosh-2.3.8-${OS}-x64.tgz" | tar xz -C "$TMP" 2>/dev/null \
    && install -m755 "$TMP"/mongosh-*/bin/mongosh "$BIN/mongosh" || echo "  skip"
fi

case ":$PATH:" in
  *":$BIN:"*) ;;
  *) echo "export PATH=\"$BIN:\$PATH\"" >> "$HOME/.bashrc"; export PATH="$BIN:$PATH" ;;
esac

say "설치 결과"
for c in aws kubectl helm eksctl terraform jq yq psql mongosh openssl dig; do
  printf '%-10s %s\n' "$c" "$(command -v $c || echo '(없음)')"
done
echo
echo "PATH 적용: source ~/.bashrc"
