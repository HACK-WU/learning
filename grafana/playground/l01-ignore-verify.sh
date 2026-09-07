#!/usr/bin/env bash
# 校验：新加的 .gitignore 规则是否既拦住过程残留、又没误伤教学产物
set -u
cd /mnt/d/projects/learning || exit 1
FAIL=0

echo "=== A. 应被忽略的一次性脚本（6 个）==="
for f in l00-smoke.sh l00-smoke2.sh l01-probe-store.sh \
         l01-probe-store2.sh l01-forms.sh l01-forms2.sh; do
  if git check-ignore -q "grafana/playground/$f"; then
    echo "  ✅ 已忽略: $f"
  else
    echo "  ❌ 未被忽略: $f"; FAIL=$((FAIL+1))
  fi
done

echo
echo "=== B. 应保留的教学产物（check-ignore 必须无命中）==="
for f in 00-学习档案.md 00-评审清单.md 01-学习路径总览.md 02-课程目录.md \
         assets/learning-path-overview.svg \
         "stages/1-看得见/overview.md" \
         "stages/1-看得见/lessons/lesson-01-Grafana是谁：一个不存数据的看图工具.md" \
         "stages/1-看得见/assets/stage-01-kan-de-jian-path.svg" \
         playground/l00-env-up.sh playground/l01-forms.py \
         playground/prometheus.yml playground/l01-verify.sh \
         playground/l01-verify-diag.sh playground/l01-hygiene.sh; do
  if git check-ignore -q "grafana/$f"; then
    echo "  ❌ 被误伤: $f"; FAIL=$((FAIL+1))
  else
    echo "  ✅ 保留: $f"
  fi
done

echo
echo "=== C. git status 现状（grafana/ 下未提交项）==="
git status --porcelain -- "grafana/" | head -20

echo
echo "=== D. 其他主题是否被波及（抽查既有规则仍生效）==="
for f in elasticsearch/playground/l5-probe.sh surrealdb/playground/l05-probe-x.sh \
         doris/assets/lesson05-probe.sh; do
  R=$(git check-ignore -q "$f" 2>/dev/null && echo "已忽略（规则仍生效）" || echo "未匹配（该路径本就无此规则）")
  echo "  $f -> $R"
done

echo
[ "$FAIL" -eq 0 ] && echo "RESULT: OK（0 误伤）" || echo "RESULT: FAIL（$FAIL 项）"
exit $FAIL
