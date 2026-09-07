#!/usr/bin/env bash
# 端到端验证：四种样例 → 期望退出码
#   clean=0  warn=1  block=2  tampered=2
set -uo pipefail

cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." || exit 1

declare -A expect=( [clean]=0 [warn]=1 [block]=2 [tampered]=2 )

overall=0

for kind in clean warn block tampered; do
  d="/tmp/ra_e2e_$kind"
  bash tests/make_fixture.sh "$d" "$kind" >/dev/null 2>&1

  printf '################ %s ################\n' "$kind"
  out=$(bash ./release-audit -q "$d" "$d/MANIFEST" 2>/dev/null)
  rc=$?

  printf '%s\n' "$out" | tail -8
  printf -- '--- 退出码: %s （期望 %s）\n' "$rc" "${expect[$kind]}"

  if [[ $rc == "${expect[$kind]}" ]]; then
    printf '✅ 通过\n\n'
  else
    printf '❌ 失败\n\n'
    overall=1
  fi
done

echo '################ 参数错误场景 ################'
bash ./release-audit --help >/dev/null 2>&1
printf '  --help        -> rc=%s（期望 0）\n' "$?"

bash ./release-audit -V >/dev/null 2>&1
printf '  -V            -> rc=%s（期望 0）\n' "$?"

bash ./release-audit /nonexistent-dir-xyz >/dev/null 2>&1
printf '  不存在的目录   -> rc=%s（期望 66）\n' "$?"

bash ./release-audit --bad-option >/dev/null 2>&1
printf '  未知选项       -> rc=%s（期望 64）\n' "$?"

bash ./release-audit >/dev/null 2>&1
printf '  无参数         -> rc=%s（期望 64）\n' "$?"

printf '\n=== 整体结果: %s ===\n' "$([[ $overall == 0 ]] && echo PASS || echo FAIL)"
exit "$overall"
