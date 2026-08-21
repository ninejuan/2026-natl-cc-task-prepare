#!/usr/bin/env python3
"""CloudFront signed URL — 콘텐츠 보호(만료시각까지만 접근). 키그룹/트러스티드 키 방식.
사전준비:
  openssl genrsa -out priv.pem 2048; openssl rsa -pubout -in priv.pem -out pub.pem
  aws cloudfront create-public-key --public-key-config ...(pub.pem, CallerReference)
  aws cloudfront create-key-group --key-group-config ...(위 public key id)
  배포의 behavior 에 TrustedKeyGroups 연결(그 behavior 는 서명 없으면 403).
서명:  pip install cryptography botocore
  python3 sign.py https://d123.cloudfront.net/private/file.mp4 <keypair_id>
"""
import sys, datetime
from botocore.signers import CloudFrontSigner
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import padding


def rsa_signer(message):
    key = serialization.load_pem_private_key(open("priv.pem", "rb").read(), password=None)
    return key.sign(message, padding.PKCS1v15(), hashes.SHA1())


def main():
    url, key_id = sys.argv[1], sys.argv[2]
    signer = CloudFrontSigner(key_id, rsa_signer)
    expire = datetime.datetime(2030, 1, 1)   # 만료시각(예시). 실전은 now + timedelta.
    signed = signer.generate_presigned_url(url, date_less_than=expire)
    print(signed)
    # 서명 없이 접근하면 403, 이 signed URL 로만 접근 가능(만료 전까지).


if __name__ == "__main__":
    main()
