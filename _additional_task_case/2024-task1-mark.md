12-1
12-1-A
명령어 실행
aws route53 list-hosted-zones --region us-east-1 | grep Name
12-1-A
설명
<비번호>.cloudhrdk*.com으로 반환되는 이름이 있는지 확인합니다.

12-2
12-2-A
설명
선수의 Windows PC 등 외부 환경에서 아래 명령어 입력 시 54.0.0.10이 반환 되는지 확인합니다.
12-2-A
명령어 실행
nslookup q1.${HOSTZONE}

12-3
12-3-A
설명
1) Bastion에 접근합니다. 
2) 아래 명령어를 입력하여 cloudhrdk 관련 도메인이 없는 것을 확인합니다.
12-3-A
명령어 실행
cat /etc/hosts
12-3-B
설명
3) 아래 명령어를 입력하여 Private hosted zone이 없는 것을 확인합니다.
12-3-B
명령어 실행
aws route53 list-hosted-zones --region us-east-1 --hosted-zone-type PrivateHostedZone
12-3-C
설명
아래 명령어를 입력하여 172.16.0.10이 반환 되는지 확인합니다.
총 4번 반복하고 4번 전부 172.16.0.10이 반환되어야 합니다.
12-3-C
명령어 실행
nslookup q1.${hostzone}

13-1
13-1-A
설명
아래 명령어를 입력하여 cloudfront.net을 포함하는 주소가 반환 되는지 확인합니다.
13-1-A
명령어 실행
nslookup cf.${hostzone}

13-2
13-2-A
설명
아래 명령어를 입력하여 Amazon 혹은 AWS 포함 문자열이 반환 되는지 확인합니다.
13-2-A
명령어 실행
echo -n "Q" | openssl s_client -connect cf.${hostzone}:443 2> /dev/null | grep i:

13-3
13-3-A
설명
아래 명령어를 입력하여 “Cloud Skills <비번호>” 문자열이 반환 되는지 확인 합니다.
13-3-A
명령어 실행
curl https://cf.${hostzone}

14-1
14-1-A
설명
아래 명령어를 입력하여 beta 네임스페이스에 Pod를 생성합니다.
14-1-A
명령어 실행
aws eks update-kubeconfig --region us-east-1 --name prod-<등번호>
kubectl apply -f beta.yaml
14-1-B
설명
아래 명령어를 입력하여 beta 네임스페이스에 day1-beta 파드가 Running 상태로 잘 구성 되었는지 확인합니다.
14-1-B
명령어 실행
kubectl get pods -n beta
14-1-C
설명
아래 명령어를 입력하여 prod 네임스페이스에 Pod를 생성합니다.
14-1-C
명령어 실행
kubectl apply -f prod.yaml
14-1-D
설명
아래 명령어를 입력하여 prod 네임스페이스에 day1-prod 파드가 생성에 실패 하는지 확인합니다.
14-1-D
명령어 실행
kubectl get pods -n prod

14-2
14-2-A
설명
명령어를 입력하여 day1-prod-pos Pod를 생성합니다.
14-2-A
명령어 실행
kubectl apply -f prod-pos.yaml
14-2-B
설명
명령어를 입력하여 day1-prod-pos Pod가 생성되어 Running 상태 인지 확인 합니다.
14-2-B
명령어 실행
kubectl get pods -n prod
14-2-C
설명
명령어를 입력하여 day1-prod-neg Pod를 생성합니다.
14-2-C
명령어 실행
kubectl apply -f prod-neg.yaml
14-2-D
설명
명령어를 입력하여 day1-prod-neg Pod가 생성에 실패 하는지 확인합니다.
14-2-D
명령어 실행
kubectl get pods -n prod

14-3
14-3-A
설명
명령어를 입력하여 day1-beta-pos Pod를 생성합니다.
14-3-A
명령어 실행
kubectl apply -f beta-pos.yaml
14-3-B
설명
명령어를 입력하여 day1-beta-pos Pod가 생성되어 Running 상태 인지 확인 합니다.
14-3-B
명령어 실행
kubectl get pods -n beta
14-3-C
설명
명령어를 입력하여 day1-beta-neg Pod를 생성합니다.
14-3-C
명령어 실행
kubectl apply -f beta-neg.yaml
14-3-D
설명
명령어를 입력하여 day1-beta-neg Pod가 생성에 실패 하는지 확인합니다.
14-3-D
명령어 실행
kubectl get pods -n beta
