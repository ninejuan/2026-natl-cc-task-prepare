"""
이미지 리사이징: S3 원본 업로드 -> 썸네일 생성 -> S3 저장.
CDN 모듈의 'Lambda@Edge 이미지 리사이징' 또는 S3 이벤트 기반 둘 다.

의존성: Pillow. requirements.txt 로 함께 패키징하거나 AWS 제공 layer 사용.
  주의: Pillow 는 네이티브 확장이라 Lambda(Amazon Linux) 아키텍처에 맞는 wheel 이 필요.
  deploy-lambda.sh 가 --only-binary=:all: 로 설치를 시도하지만, 로컬 OS 와 다르면
  실패할 수 있다. 그 경우 x86_64 manylinux wheel 을 받아 넣거나 컨테이너 이미지로 배포.

IAM: s3:GetObject, s3:PutObject
환경변수: DEST_BUCKET (선택, 없으면 같은 버킷 thumb/ 접두어)
"""
import os
import io
import urllib.parse
import boto3

_s3 = boto3.client("s3")
_SIZE = int(os.environ.get("THUMB_SIZE", "200"))


def handler(event, context):
    # S3 이벤트에서 bucket/key
    rec = event["Records"][0]["s3"]
    bucket = rec["bucket"]["name"]
    key = urllib.parse.unquote_plus(rec["object"]["key"])
    if key.startswith("thumb/"):  # 무한루프 방지
        return {"skipped": key}

    from PIL import Image  # 함수 내 import: layer 없을 때 콜드스타트에서만 실패하게

    obj = _s3.get_object(Bucket=bucket, Key=key)
    img = Image.open(io.BytesIO(obj["Body"].read()))
    img.thumbnail((_SIZE, _SIZE))

    buf = io.BytesIO()
    fmt = img.format or "JPEG"
    img.save(buf, format=fmt)
    buf.seek(0)

    dest_bucket = os.environ.get("DEST_BUCKET", bucket)
    dest_key = f"thumb/{os.path.basename(key)}"
    _s3.put_object(Bucket=dest_bucket, Key=dest_key, Body=buf,
                   ContentType=f"image/{fmt.lower()}")
    return {"src": f"{bucket}/{key}", "thumb": f"{dest_bucket}/{dest_key}", "size": _SIZE}
