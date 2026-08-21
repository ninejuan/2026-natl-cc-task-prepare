# MSK Serverless vs Provisioned — ✅ live 비교 검증

`verify.sh` 가 **같은 VPC 에 두 타입을 동시에 띄워** 관찰 가능한 차이를 실측하고 지운다(us-east-1, 2026-08-21).
"어느 쪽을 쓸지"보다 **채점자가 무엇을 보고 구분하는지**가 중요하다.

## 생성 (같은 서브넷·SG, 인증도 둘 다 IAM SASL)

```jsonc
// provisioned
{"ClusterName":"lab-msk-prov","Provisioned":{
  "BrokerNodeGroupInfo":{"InstanceType":"kafka.t3.small","ClientSubnets":["$S1","$S2"],
    "SecurityGroups":["$SG"],"StorageInfo":{"EbsStorageInfo":{"VolumeSize":10}}},
  "NumberOfBrokerNodes":2,"KafkaVersion":"3.6.0",
  "ClientAuthentication":{"Sasl":{"Iam":{"Enabled":true}}},
  "EncryptionInfo":{"EncryptionInTransit":{"ClientBroker":"TLS","InCluster":true}}}}
// serverless
{"ClusterName":"lab-msk-srvless","Serverless":{
  "VpcConfigs":[{"SubnetIds":["$S1","$S2"],"SecurityGroupIds":["$SG"]}],
  "ClientAuthentication":{"Sasl":{"Iam":{"Enabled":true}}}}}
```
```bash
aws kafka create-cluster-v2 --cli-input-json file://prov.json
aws kafka create-cluster-v2 --cli-input-json file://srvless.json
```

## 실측 차이

`list-clusters-v2` 가 **`ClusterType` 으로 바로 구분**된다 — 채점의 1차 식별자.
```
lab-msk-prov      PROVISIONED   ACTIVE
lab-msk-srvless   SERVERLESS    ACTIVE
```

| 관찰 | SERVERLESS | PROVISIONED |
|---|---|---|
| `get-bootstrap-brokers` | `BootstrapBrokerStringSaslIam` **하나뿐**<br>`boot-abmnftlq.c2.kafka-serverless.us-east-1.amazonaws.com:9098` | `b-1.…:9098,b-2.…:9098` (브로커 목록) |
| ZooKeeper | **없음** | `z-1/z-2/z-3.….kafka.us-east-1.amazonaws.com:2181` |
| 브로커 설정 | 노출 안 됨(`VpcConfigs` 만) | `NumberOfBrokerNodes=2`, `InstanceType=kafka.t3.small`, `StorageInfo.EbsStorageInfo.VolumeSize=10`, `KafkaVersion=3.6.0` |
| `list-nodes` | ❌ `BadRequestException: This operation cannot be performed on serverless clusters.` | `BrokerId 1 → subnet-053e…` / `BrokerId 2 → subnet-0a0b…` |
| 인증 | **IAM SASL 강제**(9098 만) | IAM/SCRAM/TLS/평문 선택 가능 |
| 생성 시간(실측) | ~10분 | **~60분**(t3.small 2브로커) |

## 어느 쪽을 쓰나

- **채점이 브로커 수·인스턴스 타입·스토리지·버전을 본다** → PROVISIONED 밖에 답이 없다(serverless 는 그 필드가 없음).
- **채점이 "MSK 클러스터가 ACTIVE + 토픽에 메시지"** 수준이면 SERVERLESS 가 빠르고 안전(파티션 자동, 용량 걱정 없음).
- **스케일 조작(브로커 추가·스토리지 확장)을 요구**하면 PROVISIONED(`update-broker-count`, `update-broker-storage`).
- 둘 다 **VPC 내부 전용** + `--enable-dns-hostnames` 필수(실측, 없으면 create 자체가 거부).

## 함정 (실측)

- **provisioned 생성이 매우 느리다 — 1시간 가까이**. 대회에서 "지금 만들자"는 선택지가 아니다. Serverless 도 ~10분.
- **`NumberOfBrokerNodes` 는 ClientSubnets 개수의 배수**여야 한다(2서브넷이면 2, 4, …).
- **serverless 에 provisioned 전용 API 를 쓰면 BadRequestException** — `list-nodes`, `update-broker-*` 등. 스크립트 재사용 시 분기 필요.
- 삭제도 느리다(각 수 분). 삭제 완료 전엔 서브넷/VPC 가 `DependencyViolation`.
- 나머지 인증/연결 함정(signer+OAUTHBEARER, `AWS_DEFAULT_REGION`, SG self-inbound 9098)은 토픽 README 참조.
