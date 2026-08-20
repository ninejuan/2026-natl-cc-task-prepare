// viewer-request: 캐시 적중률 향상. 경로 소문자화 + 추적 파라미터(utm_*, fbclid, gclid) 제거.
// (동일 리소스가 마케팅 파라미터 때문에 캐시 분열되는 것을 막아 캐시 키를 통합)
// ★ 주의: request.querystring 을 새 객체로 재할당해도 CFF 런타임은 "키 순서"를 바꾸지 않는다
//   (검증됨 — 정렬은 no-op). 그래서 정렬 대신 "삭제(delete)"로 정규화한다.
function handler(event) {
    var request = event.request;
    request.uri = request.uri.toLowerCase();
    var qs = request.querystring;
    for (var k in qs) {
        if (k.indexOf('utm_') === 0 || k === 'fbclid' || k === 'gclid') {
            delete qs[k];
        }
    }
    return request;
}
