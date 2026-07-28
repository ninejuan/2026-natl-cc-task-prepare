#!/bin/bash
######### Paramters ##############################
STATIC_BUCKET_NAME="wsc2024-s3-static-<random 4words>"
HOSTZONE=""  # p1xx.cloudhrdkx.com
PNUMBER="" # 101
OLDCDN_ID=""  # not additional test project
OLDCDN_DNS=""

echo "========== 2024년 경상북도 전국기능경기대회 =========="
echo "-"
echo "-"
echo "-"

echo "===== 사전준비 : 0 ====="
cat << EOF > ~/.aws/config
[default]
region = us-east-1
EOF
echo "사전준비 완료! 채점 시작!"

echo "===== DNS Sec : 12-1 (Public zone) ====="
aws route53 list-hosted-zones --region us-east-1 | grep Name

echo ""
echo ""

echo "===== DNS Sec : 12-2 (Access from extenal) ====="
nslookup q1.${HOSTZONE} 8.8.8.8

echo ""
echo ""

echo "===== DNS Sec : 12-3 (Access from intenal) ====="
cat /etc/hosts
echo "---"
aws route53 list-hosted-zones --region us-east-1 --hosted-zone-type PrivateHostedZone
echo "---"
nslookup q1.${HOSTZONE}

echo ""
echo ""

echo "===== CDN Sec : 13-1 (DNS Lookup) ====="
nslookup cf.${HOSTZONE}

echo ""
echo ""

echo "===== CDN Sec : 13-2 (Certificate) ====="
echo -n "Q" | openssl s_client -connect cf.${HOSTZONE}:443 2> /dev/null | grep i:

echo ""
echo ""

echo "===== CDN Sec : 13-3 (HTTPS) ====="
curl https://cf.${HOSTZONE}/index.html


echo ""
echo ""

echo "===== K8s Sec : Cluster setup ====="
aws eks update-kubeconfig --region us-east-1 --name prod-${PNUMBER}
kubectl apply -f beta.yaml
kubectl apply -f prod.yaml
kubectl apply -f prod-pos.yaml
kubectl apply -f prod-neg.yaml
kubectl apply -f beta-pos.yaml
kubectl apply -f beta-neg.yaml
sleep 10

echo "===== K8s Sec : 14-1 (latest) ====="
echo "!!! NOT pos and neg !!!"
kubectl get pods -n beta | grep day1-beta
echo "---"
kubectl get pods -n prod | grep day1-prod

echo ""
echo ""

echo "===== K8s Sec : 14-2 (prod label) ====="
kubectl get pods -n prod | grep day1-prod-pos
echo "---"
kubectl get pods -n prod | grep day1-prod-neg

echo ""
echo ""


echo "===== K8s Sec : 14-3 (beta label) ====="
kubectl get pods -n beta | grep day1-beta-pos
echo "---"
kubectl get pods -n beta | grep day1-beta-neg
