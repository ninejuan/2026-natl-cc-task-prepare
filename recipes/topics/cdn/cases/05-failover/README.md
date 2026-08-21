# Origin Failover (origin group)

primary origin 이 지정 status(500/502/503/504)를 반환하면 secondary 로 자동 전환.
설정은 `../04-behaviors/distribution-config.json` 의 `OriginGroups` 블록(같은 배포에서 04 behavior + 05 failover 함께 검증됨 — config 수락 + Deployed).

```json
"OriginGroups": { "Quantity": 1, "Items": [
  { "Id": "og1",
    "FailoverCriteria": { "StatusCodes": { "Quantity": 2, "Items": [500, 502] } },
    "Members": { "Quantity": 2, "Items": [{ "OriginId": "pri" }, { "OriginId": "sec" }] } }
]}
```
- **DefaultCacheBehavior.TargetOriginId 를 origin group id(og1)** 로 지정해야 failover 적용(개별 origin 아님).
- FailoverCriteria StatusCodes 는 5xx 계열만(403/404 로 failover 하려면 custom error response 병용).
- 실검증: 이 구성으로 `create-distribution` 수락 + `Status=Deployed` 확인.
