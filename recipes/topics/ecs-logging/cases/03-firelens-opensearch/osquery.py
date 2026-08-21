#!/usr/bin/env python3
"""SigV4 로 OpenSearch 도메인에 GET 요청. usage: osquery.py <host> <path>"""
import sys, json, urllib.request
import botocore.session
from botocore.awsrequest import AWSRequest
from botocore.auth import SigV4Auth

host, path = sys.argv[1], sys.argv[2]
region = "ap-northeast-2"
url = f"https://{host}{path}"
sess = botocore.session.get_session()
creds = sess.get_credentials().get_frozen_credentials()
req = AWSRequest(method="GET", url=url, headers={"Host": host})
SigV4Auth(creds, "es", region).add_auth(req)
r = urllib.request.Request(url, headers=dict(req.headers))
try:
    print(urllib.request.urlopen(r, timeout=30).read().decode())
except urllib.error.HTTPError as e:
    print("HTTP", e.code, e.read().decode())
