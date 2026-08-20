# Tier 1 — 1과제 추가 최다 출현

2024 추가 1과제(DNS Security·CDN Security)가 이 영역이었다. **2026 가이드 12작업범위 밖**이라(Route53·ACM 은 가이드에 없음) 재출제 방지 대비 1순위.

| 카드 | 다루는 것 | 검증 |
|---|---|---|
| `route53.md` | **split-view**(내부172/외부54), NS 위임, 라우팅정책 7종, 헬스체크, Resolver | ✓ split-view + 정책4종 실검증 |
| `cloudfront.md` + `cloudfront/functions/` | **OAC** S3, VPC Origin, behavior 분기, **Functions**, Lambda@Edge, 무효화 | ✓ OAC(CF200/S3직접403) + Function test |
| `acm.md` | DNS 검증, **us-east-1(CF용)**, 와일드카드/SAN, CF/ALB 연결 | ✓ 발급 요청(us-east-1) |

## 2024 재현 매핑

- **DNS Security** → `route53.md` 케이스 A(split-view) + B(NS 위임). PHZ 금지 변형은 케이스 F.
- **CDN Security** → `cloudfront.md` 케이스 A(OAC) + `acm.md`(HTTPS) + `route53.md` alias(CNAME).

## 공통

- CloudFront·ACM·WAF 는 **us-east-1**(글로벌). Route53 은 리전 무관.
- 채점은 CloudFront 를 **Comment 로 식별**(Name 태그 없이).
- 배포 반영/DNS 전파 대기 → 채점 전 여유. CF 실측 ~2분.
