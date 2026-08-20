function handler(event) {
    var request = event.request;
    var headers = request.headers;
    // A/B 테스트: 쿠키 없으면 랜덤 배정 (여기선 결정적으로 a)
    if (!headers.cookie || headers.cookie.value.indexOf('x-ab=') === -1) {
        request.headers['x-ab-assigned'] = { value: 'a' };
    }
    // 특정 경로 리라이트
    if (request.uri === '/old') {
        request.uri = '/index.html';
    }
    return request;
}
