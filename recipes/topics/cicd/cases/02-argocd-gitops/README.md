# GHA → ArgoCD GitOps
GHA 가 매니페스트/이미지태그를 git repo 에 push → ArgoCD 가 감지해 EKS 에 sync. CI(빌드)와 CD(배포) 분리.
- ArgoCD 설치·Application·auto-sync 는 `../../../cncf/argocd/`(사용자 k8s 패스 검증).
- GHA 는 이미지 빌드→ECR push 후 kustomize/helm values 의 tag 를 커밋(그게 ArgoCD sync 트리거).
- 검증(브라우저/kubectl): `kubectl get application -n argocd -o jsonpath` synced/healthy.
기반: ../../../cncf/argocd/, 이미지빌드는 ../04-codebuild-ecr/ 또는 ../01-codepipeline-ecs/.
