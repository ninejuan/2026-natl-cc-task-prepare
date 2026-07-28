#!/usr/bin/env bash
# 모든 카드를 ALL.md 한 장으로 합친다. 현장에서 Ctrl+F 한 번으로 전체 검색하는 용도.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/ALL.md"

cards=()
while IFS= read -r line; do cards+=("$line"); done < <(cd "$ROOT" && find recipes -name '*.md' | sort)
if [ ${#cards[@]} -eq 0 ]; then echo "recipes/ 에 카드가 없다"; exit 0; fi

{
  echo "# 전체 카드 병합본"
  echo
  echo "\`bin/build-all.sh\` 생성. 카드 ${#cards[@]}개. Ctrl+F로 찾아라."
  echo "결정 트리는 [README.md](README.md), 현장 절차는 [FIELD-RUNBOOK.md](FIELD-RUNBOOK.md)."
  echo
  echo "## 목차"
  echo
  for c in "${cards[@]}"; do echo "- [$c](#${c//[\/.]/-})"; done

  for c in "${cards[@]}"; do
    echo
    echo "---"
    echo
    echo "<a id=\"${c//[\/.]/-}\"></a>"
    echo
    echo "## $c"
    echo
    # 카드 자체 h1 은 h3 으로 낮춰서 목차 구조를 유지한다
    sed -e 's/^# /### /' -e 's/^## /#### /' -e 's/^### \(.*\)/### \1/' "$ROOT/$c"
  done
} > "$OUT"

echo "wrote ALL.md — 카드 ${#cards[@]}개, $(wc -l < "$OUT") 줄"
