-- DynamoDB PartiQL 모음 (aws dynamodb execute-statement --statement "...")
-- PartiQL 은 DynamoDB 의 SQL 호환 쿼리 언어. 콘솔 "PartiQL editor" 에서도 그대로.
-- 실행:  aws dynamodb execute-statement --region ap-northeast-2 --statement "<한 문장>"
-- 주의:  테이블/인덱스 이름은 "쌍따옴표", 문자열 값은 '홑따옴표'. 세미콜론 없음.
--        WHERE 에 PK(+SK) 가 있으면 Query(빠름), 없으면 Scan(느림) 으로 자동 판단.

-- ═══ 1. PK 로 전체 조회 (Query) ═══
SELECT * FROM "lab-ddb" WHERE pk = 'acct#1'

-- ═══ 2. PK + SK 정확히 한 항목 (GetItem) ═══
SELECT * FROM "lab-ddb" WHERE pk = 'acct#1' AND sk = 'balance'

-- ═══ 3. SK begins_with — 같은 PK 아래 접두사 (주문 목록 등) ═══
SELECT * FROM "lab-ddb" WHERE pk = 'acct#1' AND begins_with("sk", 'order#')

-- ═══ 4. SK 범위 (BETWEEN) — 기간 조회 ═══
SELECT * FROM "lab-ddb" WHERE pk = 'acct#1' AND "sk" BETWEEN 'order#2026-01' AND 'order#2026-06'

-- ═══ 5. 특정 속성만 프로젝션 (필요한 컬럼만 → 비용↓) ═══
SELECT pk, sk, amount FROM "lab-ddb" WHERE pk = 'acct#1'

-- ═══ 6. GSI 조회 — 인덱스명을 테이블.인덱스 로 ═══
SELECT * FROM "lab-ddb"."gsi1" WHERE gsipk = 'acct'

-- ═══ 7. IN — 여러 PK 후보 ═══
SELECT * FROM "lab-ddb" WHERE pk IN ['acct#1', 'acct#2', 'acct#3']

-- ═══ 8. contains — 문자열/셋 부분일치 (Scan) ═══
SELECT * FROM "lab-ddb" WHERE contains("name", 'kim')

-- ═══ 9. attribute_exists / attribute_not_exists — 속성 유무 ═══
SELECT * FROM "lab-ddb" WHERE attribute_exists(ttl)

-- ═══ 10. INSERT — 항목 추가 (map/list 중첩 가능) ═══
INSERT INTO "lab-ddb" VALUE {'pk':'acct#9', 'sk':'profile', 'name':'lee', 'tags':['vip','beta'], 'meta':{'age':30}}

-- ═══ 11. UPDATE SET — 원자적 카운터 (잔액 차감) ═══
UPDATE "lab-ddb" SET amount = amount - 100 WHERE pk = 'acct#1' AND sk = 'balance'

-- ═══ 12. UPDATE SET — 리스트/맵 요소 추가·수정 ═══
UPDATE "lab-ddb" SET meta.age = 31 SET tags = list_append(tags, ['gold']) WHERE pk = 'acct#9' AND sk = 'profile'

-- ═══ 13. UPDATE REMOVE — 속성 제거 ═══
UPDATE "lab-ddb" REMOVE tags WHERE pk = 'acct#9' AND sk = 'profile'

-- ═══ 14. DELETE — 조건부 삭제 (있을 때만, 반환값 확인) ═══
DELETE FROM "lab-ddb" WHERE pk = 'acct#9' AND sk = 'profile'

-- ═══ 15. 조건부 UPDATE — 잔액이 충분할 때만 차감 (동시성 안전) ═══
UPDATE "lab-ddb" SET amount = amount - 500 WHERE pk = 'acct#1' AND sk = 'balance' AND amount >= 500
