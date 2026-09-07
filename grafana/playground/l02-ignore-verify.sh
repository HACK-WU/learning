#!/usr/bin/env bash
# 课 2 的 .gitignore 规则校验：A 组应忽略 / B 组应保留 / C 组 git status / D 组其他主题未波及
set -u
cd /mnt/d/projects/learning || exit 1
FAIL=0

echo "=== A. 应被忽略（9 项）==="
for f in \
  playground/__pycache__/l02-panel.cpython-312.pyc \
  playground/l02-diag-mu.sh \
  playground/l02-link-diag.sh \
  playground/l02-link-run.sh \
  playground/l02-verify-run.sh \
  playground/l02-portaudit.sh \
  playground/l02-review-probe.sh \
  playground/l02-syntax.sh \
  playground/l02-panel.sh ; do
  if git check-ignore -q "grafana/$f"; then echo "  ✅ 已忽略: $f"
  else echo "  ❌ 未被忽略: $f"; FAIL=$((FAIL+1)); fi
done

echo
echo "=== B. 应保留的教学产物（check-ignore 必须无命中）==="
for f in \
  00-学习档案.md 00-评审清单.md 01-学习路径总览.md 02-课程目录.md \
  assets/learning-path-overview.svg \
  stages/1-看得见/overview.md \
  stages/1-看得见/lessons/lesson-01-Grafana是谁：一个不存数据的看图工具.md \
  stages/1-看得见/lessons/lesson-02-第一个面板：从零到看得见.md \
  stages/1-看得见/assets/stage-01-kan-de-jian-path.svg \
  playground/l00-env-up.sh \
  playground/l01-forms.py \
  playground/prometheus.yml \
  playground/l01-verify.sh \
  playground/l01-verify-diag.sh \
  playground/l01-hygiene.sh \
  playground/l01-ignore-verify.sh \
  playground/l02-verify.sh \
  playground/l02-linkcheck.sh \
  playground/l02-readyfix.sh \
  playground/l02-envcheck.sh \
  playground/l02-init.sh \
  playground/l02-init2.sh \
  playground/l02-timing.sh \
  playground/l02-ds.sh \
  playground/l02-cors.sh \
  playground/l02-cors2.sh \
  playground/l02-panel.py \
  playground/l02-diag-health.sh \
  playground/l02-plugins.sh \
  playground/l02-archive-append.py ; do
  if git check-ignore -q "grafana/$f" 2>/dev/null; then
    echo "  ❌ 被误伤: $f"; FAIL=$((FAIL+1))
  else
    echo "  ✅ 保留: $f"
  fi
done

echo
echo "=== C. git status 现状（grafana/ 下未提交项概览）==="
git status --porcelain -- grafana/ | head -5
echo "  （总计 $(git status --porcelain -- grafana/ | wc -l) 项）"

echo
echo "=== D. 其他主题是否被波及（抽查既有规则仍生效）==="
for f in elasticsearch/playground/l5-probe.sh surrealdb/playground/l05-probe-x.sh doris/assets/lesson05-probe.sh; do
  if git check-ignore -q "$f" 2>/dev/null; then echo "  ✅ $f -> 已忽略（规则仍生效）"
  else echo "  ⚠️  $f -> 未被忽略"; fi
done

echo
echo "RESULT: ${FAIL} 误伤/漏网项"
