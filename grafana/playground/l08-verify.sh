#!/usr/bin/env bash
# 课 8 结构校验
set -u
cd /mnt/d/projects/learning/grafana
F="stages/3-叫得醒/lessons/lesson-08-告警规则与通知策略实战.md"

echo "=========================================================="
echo " 课 8 结构校验"
echo "=========================================================="
echo ""
echo "--- [0] 文件规模 ---"
echo "  行数: $(wc -l < "$F")"
echo "  字节: $(wc -c < "$F")"

echo ""
echo "--- [1] 九项结构（必须全 1）---"
declare -a ITEMS=(
  '^## 📖 开篇'
  '^## 🧠 8\.1'
  '^## 🧠 8\.2'
  '^## 🧠 8\.3'
  '^## 🔗 跨课串联'
  '^## ✅ 本课验收'
  '^## 🔍 评审结论'
  '^## 🎯 小测'
  '^## 🚀 下一批接力提示词'
)
FAIL=0
for pat in "${ITEMS[@]}"; do
  c=$(grep -cE "$pat" "$F")
  if [ "$c" -ge 1 ]; then
    echo "  ✅ $pat  ($c)"
  else
    echo "  ❌ 缺失: $pat"
    FAIL=$((FAIL+1))
  fi
done

echo ""
echo "--- [2] 六要素（每个知识点都要有）---"
for k in "一句话定义" "直觉建立" "核心原理" "示例演示" "常见误区" "一句话记住"; do
  c=$(grep -c "$k" "$F")
  echo "  $k: $c 处（8.1+8.2+8.3 各 1，应为 3）"
done

echo ""
echo "--- [3] 未实测声明（应显式标注，不得为 0 且不得含糊）---"
grep -nE '⚠️' "$F" | sed 's/^/  /'

echo ""
echo "--- [4] 硬约束：命令单行（代码块外不得有反斜杠续行）---"
python3 - <<'PY'
import re
p="stages/3-叫得醒/lessons/lesson-08-告警规则与通知策略实战.md"
lines=open(p,encoding="utf-8").read().split("\n")
in_block=False
bad=0
fence=0
for i,l in enumerate(lines,1):
    s=l.strip()
    # 支持 Markdown 引用块内的代码块（"> ```bash" 形式）
    s2=s.lstrip(">").strip()
    if s2.startswith("```"):
        in_block = not in_block
        fence+=1
        continue
    if not in_block and l.rstrip().endswith("\\"):
        print("  ❌ 第 %d 行代码块外反斜杠续行: %s"%(i,l[:80]))
        bad+=1
print("  代码块外续行：%d（应为 0）"%bad)
print("  代码块围栏数：%d（应为偶数，当前 %s）"%(fence,"配对" if fence%2==0 else "❌ 不配对"))
PY

echo ""
echo "--- [5] 关键数据是否出现在正文 ---"
for kw in "2 条通知" "6 条通知" "90 秒" "60 秒" "alerting=3" "webhook=0 条" "1m" "40s"; do
  c=$(grep -c "$kw" "$F")
  echo "  $kw: $c 处"
done

echo ""
echo "--- [6] 三要素是否讲全 ---"
for kw in "查询" "Reduce" "阈值" "for" "noDataState" "execErrState" "keep_firing_for"; do
  c=$(grep -c "$kw" "$F")
  echo "  $kw: $c 处"
done

echo ""
echo "--- [7] 通知策略三组件 ---"
for kw in "Contact point" "策略树" "静默" "object_matchers" "group_by" "mute timing"; do
  c=$(grep -c "$kw" "$F")
  echo "  $kw: $c 处"
done

echo ""
echo "--- [8] 四个分组参数 ---"
for kw in "group_wait" "group_interval" "repeat_interval"; do
  c=$(grep -c "$kw" "$F")
  echo "  $kw: $c 处"
done

echo ""
echo "=========================================================="
if [ "$FAIL" -eq 0 ]; then
  echo " 结构校验：✅ 全部通过"
else
  echo " 结构校验：❌ $FAIL 项缺失"
fi
echo "=========================================================="
