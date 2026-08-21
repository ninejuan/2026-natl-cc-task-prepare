// viewer-request: HTTP Basic 인증. 헤더 없거나 틀리면 401. (CDN 모듈 "접근 제한")
// user:pass = admin:skills2026 → base64("admin:skills2026") = YWRtaW46c2tpbGxzMjAyNg==
function handler(event) {
    var request = event.request;
    var expected = 'Basic YWRtaW46c2tpbGxzMjAyNg==';
    var auth = request.headers.authorization && request.headers.authorization.value;
    if (auth !== expected) {
        return {
            statusCode: 401,
            statusDescription: 'Unauthorized',
            headers: { 'www-authenticate': { value: 'Basic realm="restricted"' } }
        };
    }
    return request;
}
