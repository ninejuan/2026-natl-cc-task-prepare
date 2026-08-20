#!/usr/bin/env python3
"""Data API 로 커넥션 없이 쿼리 (출제자 제공 코드 형태). boto3 rds-data.
VPC 연결 불필요 — Lambda 에서도 이대로. 환경변수 CLUSTER_ARN, SECRET_ARN, DB_NAME.
"""
import os, boto3

rds = boto3.client("rds-data", region_name=os.environ.get("AWS_DEFAULT_REGION", "ap-northeast-2"))
CLUSTER = os.environ["CLUSTER_ARN"]
SECRET = os.environ["SECRET_ARN"]
DB = os.environ.get("DB_NAME", "lab")


def q(sql, params=None):
    return rds.execute_statement(
        resourceArn=CLUSTER, secretArn=SECRET, database=DB,
        sql=sql, parameters=params or [],
    )


def handler(event=None, context=None):
    # 파라미터 바인딩(SQL 인젝션 방지) — :name 플레이스홀더
    q("CREATE TABLE IF NOT EXISTS items(id serial primary key, name text)")
    q("INSERT INTO items(name) VALUES(:n)", [{"name": "n", "value": {"stringValue": "from-lambda"}}])
    r = q("SELECT id, name FROM items ORDER BY id DESC LIMIT 5")
    rows = [[c.get("longValue", c.get("stringValue")) for c in rec] for rec in r["records"]]
    return {"rows": rows}


if __name__ == "__main__":
    print(handler())
