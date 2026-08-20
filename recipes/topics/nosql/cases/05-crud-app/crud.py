#!/usr/bin/env python3
"""DynamoDB CRUD 앱 (배포파일 형 — 출제자 제공 코드). boto3 resource API.
선수는 이걸로 NoSQL 읽기/쓰기에 집중. 환경변수 TABLE, AWS_DEFAULT_REGION.
"""
import os, boto3
from boto3.dynamodb.conditions import Key

ddb = boto3.resource("dynamodb", region_name=os.environ.get("AWS_DEFAULT_REGION", "ap-northeast-2"))
table = ddb.Table(os.environ.get("TABLE", "lab-ddb"))


def put(pk, sk, **attrs):
    table.put_item(Item={"pk": pk, "sk": sk, **attrs})


def get(pk, sk):
    return table.get_item(Key={"pk": pk, "sk": sk}).get("Item")


def query(pk):
    return table.query(KeyConditionExpression=Key("pk").eq(pk)).get("Items", [])


def delete(pk, sk):
    table.delete_item(Key={"pk": pk, "sk": sk})


def demo():
    put("user#1", "profile", name="kim", grade="premium")
    put("user#1", "order#001", amount=100)
    assert get("user#1", "profile")["name"] == "kim"
    items = query("user#1")
    assert len(items) == 2, items
    delete("user#1", "order#001")
    assert len(query("user#1")) == 1
    print("✓ CRUD 왕복 OK")


if __name__ == "__main__":
    demo()
