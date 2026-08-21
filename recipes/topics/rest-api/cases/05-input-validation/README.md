# 입력 검증 + 에러 응답
`handler.py`(crud-booking) — 필수 필드 없으면 400, 정상이면 201/200. HTTP API base64 body 함정(02 참조) 처리. APIGW 레벨 검증(request validator + JSON schema model)도 가능하나 코드 검증이 유연.
