# Composite Alarm (여러 알람 AND/OR) — 실검증됨(a1 OR a2)
```bash
aws cloudwatch put-composite-alarm --alarm-name comp \
  --alarm-rule 'ALARM("a1") OR ALARM("a2")'
```
자식 알람들을 AND/OR/NOT 로 조합 → 노이즈 감소(예: 5xx AND latency 둘 다 나쁠 때만). 자식 알람이 먼저 존재해야.
