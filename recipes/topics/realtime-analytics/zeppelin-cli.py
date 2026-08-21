#!/usr/bin/env python3
"""Zeppelin REST 로 Flink SQL 문단을 하나씩 돌리고 결과 텍스트만 뽑는다.
usage: zep2.py <base> <cookie> [snippet-file]
"""
import sys, json, re, time, urllib.request, html

BASE = sys.argv[1].rstrip("/") + "/zeppelin"
COOKIE = sys.argv[2]


def api(path, data=None, method=None, timeout=600):
    body = json.dumps(data).encode() if data is not None else None
    req = urllib.request.Request(f"{BASE}{path}", data=body,
                                 method=method or ("POST" if body else "GET"),
                                 headers={"Content-Type": "application/json", "Cookie": COOKIE})
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return json.loads(r.read().decode())


def clean(msgs):
    out = []
    for m in msgs or []:
        d = m.get("data", "")
        if m.get("type") == "ANGULAR":
            d = html.unescape(re.sub(r"<[^>]+>", " ", d))
            d = re.sub(r"\s*\{\{[^}]*\}\}\s*", " ", d)
            d = re.sub(r"[ \t]+", " ", d)
        out.append(d.strip())
    return "\n".join(out)


def run(note, title, text, limit=3000):
    p = api(f"/api/notebook/{note}/paragraph", {"title": title, "text": text})["body"]
    t0 = time.time()
    try:
        r = api(f"/api/notebook/run/{note}/{p}", {})
        b = r.get("body", {})
        print(f"\n===== {title}  [{b.get('code')}] {time.time()-t0:.0f}s =====")
        print(clean(b.get("msg"))[:limit])
    except urllib.error.HTTPError as e:
        raw = e.read().decode()
        try:
            b = json.loads(raw).get("body", {})
            print(f"\n===== {title}  [{b.get('code')}] {time.time()-t0:.0f}s =====")
            print(clean(b.get("msg"))[:limit])
        except Exception:
            print(f"\n===== {title} [HTTP {e.code}] =====\n{raw[:limit]}")
    return p


SNIPPETS = json.load(open(sys.argv[3]))
note = api("/api/notebook", {"name": f"probe-{int(time.time())}"})["body"]
print("NOTE", note)
for title, text in SNIPPETS:
    run(note, title, text)
