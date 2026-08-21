// viewer-request: apex(example.com) → www 로 301 리다이렉트. (CDN 모듈 "리다이렉트")
function handler(event) {
    var request = event.request;
    var host = request.headers.host.value;
    if (host === 'example.com') {
        return {
            statusCode: 301,
            statusDescription: 'Moved Permanently',
            headers: { location: { value: 'https://www.example.com' + request.uri } }
        };
    }
    return request;
}
