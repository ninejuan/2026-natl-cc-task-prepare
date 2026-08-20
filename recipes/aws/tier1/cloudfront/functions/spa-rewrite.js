// viewer-request: SPA 라우팅. 확장자 없는 경로(=클라이언트 라우트)를 /index.html 로.
// 정적 자산(.js/.css/.png ...)과 이미 파일인 경로는 그대로 통과.
function handler(event) {
    var request = event.request;
    var uri = request.uri;
    // 디렉토리 요청 → index.html 부여
    if (uri.endsWith('/')) {
        request.uri = uri + 'index.html';
    } else if (!uri.includes('.')) {
        // 확장자 없음 = SPA 라우트 → 앱 셸로
        request.uri = '/index.html';
    }
    return request;
}
