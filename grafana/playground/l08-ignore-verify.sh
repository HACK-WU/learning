#!/usr/bin/env bash
# 课 8 .gitignore 规则校验：13 条应命中，且不得误伤教学产物
set -u
cd /mnt/d/projects/learning

echo "=========================================================="
echo " 课 8 .gitignore 规则校验"
echo "=========================================================="

echo ""
echo "--- [1] 应被忽略的（每条应为 IGNORED）---"
SHOULD_IGNORE="grafana/playground/l08-envcheck.sh
grafana/playground/l08-diag-anomaly.sh
grafana/playground/l08-diag-409.sh
grafana/playground/l08-diag-backslash.sh
grafana/playground/l08-diag-link.sh
grafana/playground/l08_probe_rule.py
grafana/playground/l08_probe_rule2.py
grafana/playground/l08_probe_verify2.py
grafana/playground/l08_probe_policy.py
grafana/playground/l08-read-bg.sh
grafana/playground/l08-watch.sh
grafana/playground/l08-watch-group.sh
grafana/playground/l08-watch-timing.sh
grafana/playground/l08-check-bg.sh
grafana/playground/l08-check-group.sh
grafana/playground/l08-archive.py
grafana/playground/l08-out-rule.txt
grafana/playground/l08-out-rule2.txt
grafana/playground/l08-out-rule3.txt
grafana/playground/l08-out-policy.txt
grafana/playground/l08-out-policy2.txt
grafana/playground/l08-out-anomaly.txt
grafana/playground/l08-out-verify2.txt
grafana/playground/l08-out-group.txt
grafana/playground/l08-out-timing.txt
grafana/playground/l08-webhook-log.jsonl"
IGN_OK=0
IGN_BAD=0
for f in $SHOULD_IGNORE; do
  R=$(git check-ignore -v "$f" 2>/dev/null)
  if [ -n "$R" ]; then
    IGN_OK=$((IGN_OK+1))
  else
    echo "  ❌ 未被忽略: $f"
    IGN_BAD=$((IGN_BAD+1))
  fi
done
echo "  应忽略命中: $IGN_OK 条, 漏网: $IGN_BAD 条"

echo ""
echo "--- [2] 教学产物（每条应为 NOT ignored）---"
SHOULD_KEEP="grafana/playground/l08_webhook_receiver.py
grafana/playground/l08-start-webhook.sh
grafana/playground/l08-cleanup.sh
grafana/playground/l08-webhook-check.sh
grafana/playground/l08-verify.sh
grafana/playground/l08-review-check.sh
grafana/playground/l08-final.sh
grafana/playground/l08_probe_rule3.py
grafana/playground/l08_probe_policy2.py
grafana/playground/l08_probe_group.py
grafana/playground/l08_probe_timing.py
grafana/stages/3-叫得醒/lessons/lesson-08-告警规则与通知策略实战.md"
KEEP_OK=0
KEEP_BAD=0
for f in $SHOULD_KEEP; do
  R=$(git check-ignore -v "$f" 2>/dev/null)
  if [ -z "$R" ]; then
    KEEP_OK=$((KEEP_OK+1))
  else
    echo "  ❌ 被误伤: $f"
    echo "     规则: $R"
    KEEP_BAD=$((KEEP_BAD+1))
  fi
done
echo "  教学产物保护: $KEEP_OK 条, 误伤: $KEEP_BAD 条"

echo ""
echo "--- [3] 回归：课 7 及之前的教学产物不应被新增规则影响 ---"
OLD_KEEP="grafana/stages/3-叫得醒/lessons/lesson-07-告警架构：规则在哪求值、状态怎么迁移.md
grafana/playground/l07-mkfolder.sh
grafana/playground/l00-env-up.sh
grafana/playground/l01-forms.py
grafana/playground/l03-linkcheck-all.sh
grafana/playground/l03-verify.sh"
OLD_BAD=0
for f in $OLD_KEEP; do
  R=$(git check-ignore -v "$f" 2>/dev/null)
  if [ -n "$R" ]; then
    echo "  ❌ 回归误伤: $f"
    echo "     规则: $R"
    OLD_BAD=$((OLD_BAD+1))
  fi
done
echo "  回归检查: 误伤 $OLD_BAD 条（应为 0）"

echo ""
echo "=========================================================="
if [ "$IGN_BAD" -eq 0 ] && [ "$KEEP_BAD" -eq 0 ] && [ "$OLD_BAD" -eq 0 ]; then
  echo " ✅ 全部通过"
else
  echo " ❌ 存在问题（漏网 $IGN_BAD / 误伤 $KEEP_BAD / 回归 $OLD_BAD）"
fi
echo "=========================================================="
