// CloudFront Function (viewer-response): 응답에 보안 헤더 추가. CDN 모듈 "HTTP Header 변경".
// behavior FunctionAssociations EventType=viewer-response 로 연결.
function handler(event) {
    var response = event.response;
    var headers = response.headers;
    headers['strict-transport-security'] = { value: 'max-age=63072000; includeSubdomains; preload' };
    headers['x-content-type-options']   = { value: 'nosniff' };
    headers['x-frame-options']          = { value: 'DENY' };
    headers['x-custom-marker']          = { value: 'cloud-skills-2026' };
    return response;
}
