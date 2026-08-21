# MSK IAM SASL 인증 (9098)
MSK Serverless 는 IAM SASL 강제(포트 9098). 클라이언트는 aws-msk-iam-sasl-signer + OAUTHBEARER(../02-ec2-consumer/roundtrip.py 실검증). IAM 정책: kafka-cluster:Connect/DescribeCluster/ReadData/WriteData/CreateTopic. SG self-inbound 9098. ★ 내장 sasl_mechanism="AWS_MSK_IAM" 은 타임아웃(안 됨) — signer 방식만. 기반: ../../../../aws/analytics/msk/.
