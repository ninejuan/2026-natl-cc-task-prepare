// viewer-request: 국가별 경로 분기. CloudFront-Viewer-Country 헤더로 콘텐츠 지역화.
// (배포에 CloudFront-Viewer-Country 헤더 전달 활성 필요 — cache/origin request policy)
function handler(event) {
    var request = event.request;
    var country = request.headers['cloudfront-viewer-country'];
    var code = country ? country.value : 'US';
    // 이미 /kr, /jp 등으로 시작하면 통과
    if (!/^\/(kr|jp|us)\//.test(request.uri)) {
        var prefix = { KR: '/kr', JP: '/jp' }[code] || '/us';
        request.uri = prefix + request.uri;
    }
    return request;
}
