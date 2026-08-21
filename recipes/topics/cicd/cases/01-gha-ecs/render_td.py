#!/usr/bin/env python3
"""현재 taskdef 를 받아 image 만 갈아끼운 새 리비전 입력을 만든다.
★ register-task-definition 은 describe 응답의 읽기전용 필드를 그대로 받으면 거부한다 → 제거 필수."""
import json, os, sys
d = json.load(open(sys.argv[1]))
for k in ("taskDefinitionArn","revision","status","requiresAttributes","compatibilities",
          "registeredAt","registeredBy","deregisteredAt"):
    d.pop(k, None)
for c in d["containerDefinitions"]:
    if c["name"] == os.environ["CONTAINER"]:
        c["image"] = os.environ["IMG"]
        c.pop("command", None)          # 부트스트랩용 command 제거 → 이미지 CMD 사용
json.dump(d, open(sys.argv[2], "w"))
print("rendered", c["image"])
