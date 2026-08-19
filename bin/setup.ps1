# 디버깅 해야 할 거
# terraform cli가 안됨.

Set-ExecutionPolicy -Scope Process Bypass -Force

wsl --install --no-distribution

$pkgs = @(
  "Amazon.AWSCLI", "Kubernetes.kubectl", "Helm.Helm", "eksctl.eksctl",
  "Hashicorp.Terraform", "jqlang.jq", "MikeFarah.yq", "Git.Git", "Python.Python.3.12",
  "PostgreSQL.PostgreSQL", "MongoDB.Shell",
  "Amazon.AWSVPNClient", "Amazon.SessionManagerPlugin", "ShiningLight.OpenSSL.Light",
  "Docker.DockerDesktop"
)
foreach ($p in $pkgs) {
  Write-Host "== $p" -ForegroundColor Cyan
  winget install --id $p -e --silent --accept-package-agreements --accept-source-agreements
}
