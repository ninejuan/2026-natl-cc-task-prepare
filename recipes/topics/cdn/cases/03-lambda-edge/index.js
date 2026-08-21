// Lambda@Edge (origin-response) 이미지 리사이징 — Node.js + sharp.
// ★ Lambda@Edge 는 환경변수를 못 쓴다 → 버킷/리전을 request.origin.s3.domainName 에서 파싱.
// ★ 새 응답 객체를 만들어 반환하지 말고 받은 response 를 "수정"해서 돌려준다.
//   (통째로 갈아끼우면 origin 이 준 read-only 헤더가 사라져 502 "read-only header" 로 거부됨 — 실측)
const { S3Client, GetObjectCommand } = require("@aws-sdk/client-s3");
const sharp = require("sharp");

exports.handler = async (event) => {
  const { request, response } = event.Records[0].cf;
  const w = parseInt(new URLSearchParams(request.querystring || "").get("w") || "0", 10);
  if (!w) {
    response.headers["x-resized-by"] = [{ key: "x-resized-by", value: "skip" }];
    return response; // 원본 그대로
  }
  const domain = request.origin?.s3?.domainName || "";
  const bucket = domain.split(".s3.")[0];
  const region = (domain.split(".s3.")[1] || "us-east-1.amazonaws.com").split(".")[0];
  const key = decodeURIComponent(request.uri.replace(/^\//, ""));

  const obj = await new S3Client({ region }).send(new GetObjectCommand({ Bucket: bucket, Key: key }));
  const out = await sharp(Buffer.from(await obj.Body.transformToByteArray())).resize(w).png().toBuffer();

  response.status = "200";
  response.statusDescription = "OK";
  response.headers["content-type"] = [{ key: "Content-Type", value: "image/png" }];
  response.headers["cache-control"] = [{ key: "Cache-Control", value: "max-age=60" }];
  response.headers["x-resized-by"] = [{ key: "x-resized-by", value: `w=${w}` }];
  delete response.headers["content-length"]; // 길이가 바뀌므로 CloudFront 가 다시 계산하게
  response.body = out.toString("base64");
  response.bodyEncoding = "base64"; // ★ origin-response 생성본문은 1MB 제한
  return response;
};
