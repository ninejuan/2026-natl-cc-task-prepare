# FireLens → OpenSearch (Kibana 검색)

`containerdef-opensearch.json` — 02-firelens-cw 와 인프라 동일, app 컨테이너 output 을 Fluent Bit **opensearch** 플러그인으로. "로그 저장 및 검색"(2025 #9) 요구 시.

- `Host` = OpenSearch 도메인 엔드포인트, `AWS_Auth: On` + `AWS_Region` → SigV4 서명(도메인 접근정책이 task role 허용).
- **task role 에 `es:ESHttp*`** (대상 도메인) 필요.
- `Suppress_Type_Name: On` — OpenSearch 2.x/ES7+ 는 type 제거.
- OpenSearch 도메인 생성 ~15분 + 시간과금 → 채점은 미리 뜬 전제. Kibana/Dashboards 로 인덱스 조회.
- 기반: CloudWatch 경로(02-firelens-cw, live 검증)와 output options 만 차이.
