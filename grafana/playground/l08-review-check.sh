#!/usr/bin/env bash
# 课 8 双视角评审：逐条回读原文核验
set -u
cd /mnt/d/projects/learning/grafana
F="stages/3-叫得醒/lessons/lesson-08-告警规则与通知策略实战.md"

echo "=========================================================="
echo " 课 8 双视角评审（pedagogy + learner）"
echo "=========================================================="

echo ""
echo "########## A. 数据一致性：正文说的 vs 实测输出 ##########"
echo ""
echo "--- A1. classic→1 条 / reduce→3 条（对照 l08-out-verify2.txt）---"
echo "  实测（verify2）："
grep -A2 'Alertmanager 实例数' playground/l08-out-verify2.txt | grep '实例数' | sed 's/^/    /'
echo "  正文声称："
grep -oE '\*\*[0-9]+ 条\*\*' "$F" | sort | uniq -c | sed 's/^/    /'

echo ""
echo "--- A2. 分组实验（对照 l08-out-group.txt）---"
echo "  实测场景A："
grep -E '→ 3 台机器，通知条数' playground/l08-out-group.txt | sed 's/^/    /'
echo "  正文表格："
grep -E '^\| `\[alertname\]`|^\| `\[alertname, instance\]`' "$F" | sed 's/^/    /'

echo ""
echo "--- A3. 静默：通知 0 条但状态 alerting=3 ---"
echo "  实测："
grep -E '静默期间|但告警状态' playground/l08-out-group.txt | sed 's/^/    /'
echo "  正文："
grep -E '静默期间通知 0 条' "$F" | sed 's/^/    /'

echo ""
echo "--- A4. 时间参数（对照 l08-out-timing.txt）---"
echo "  实测三组："
grep -E '配置：group_wait|首次告警 → 首条通知' playground/l08-out-timing.txt | sed 's/^/    /'
echo "  正文表格："
grep -E '^\| [123] \| [0-9]+s \| 30s \|' "$F" | sed 's/^/    /'

echo ""
echo "--- A5. contact point 类型数（对照 l08-out-policy.txt）---"
echo "  实测可用（✅）数量："
grep -c '✅' playground/l08-out-policy.txt | sed 's/^/    ✅数: /'
echo "  实测不可用（❌）数量："
grep -c '❌' playground/l08-out-policy.txt | sed 's/^/    ❌数: /'
echo "  正文声称 13 可用 / 7 缺参数："
grep -E '13 可用|13 可用 / 7' "$F" | sed 's/^/    /'

echo ""
echo "########## B. learner 视角：照抄能跑通吗 ##########"
echo ""
echo "--- B1. 所有 bash 代码块是否单行可执行 ---"
python3 - <<'PY'
import re
p="stages/3-叫得醒/lessons/lesson-08-告警规则与通知策略实战.md"
txt=open(p,encoding="utf-8").read()
blocks=re.findall(r'```bash\n(.*?)```', txt, re.S)
print("  bash 代码块数：%d"%len(blocks))
multi=0
for i,b in enumerate(blocks,1):
    if "\\" in b:
        multi+=1
        print("    ⚠️ 第 %d 个 bash 块含反斜杠续行"%i)
print("  含续行的块：%d（应为 0）"%multi)
PY

echo ""
echo "--- B2. 是否出现禁止的省略写法 ---"
for kw in "（同上）" "同上" "列定义同上" "以此类推" "省略"; do
  c=$(grep -c "$kw" "$F")
  if [ "$c" -gt 0 ]; then
    echo "  ❌ 出现「$kw」$c 次"
    grep -n "$kw" "$F" | sed 's/^/      /'
  fi
done
echo "  （无输出=未出现禁止写法）"

echo ""
echo "--- B3. 每个知识点是否都有可执行的示例 ---"
python3 - <<'PY'
import re
p="stages/3-叫得醒/lessons/lesson-08-告警规则与通知策略实战.md"
txt=open(p,encoding="utf-8").read()
for k in ["8.1","8.2","8.3"]:
    # 取该知识点到下一个知识点/章节之间的内容
    m=re.search(r'## 🧠 %s(.*?)(?=\n## )'%re.escape(k), txt, re.S)
    if m:
        seg=m.group(1)
        has_code = "```" in seg
        has_bash = "```bash" in seg
        has_py = "```python" in seg
        print("  %s: 代码块=%s bash=%s python=%s"%(k,has_code,has_bash,has_py))
PY

echo ""
echo "########## C. pedagogy 视角 ##########"
echo ""
echo "--- C1. 五幕结构（开篇冲突→揭示→验证→收束）---"
for kw in "开篇" "直觉建立" "核心原理" "示例演示" "常见误区" "一句话记住"; do
  c=$(grep -c "$kw" "$F")
  echo "  $kw: $c"
done

echo ""
echo "--- C2. 是否有跨课串联 ---"
grep -cE '课 7|课 4|课 5|课 6|跨课' "$F" | sed 's/^/  跨课引用处数: /'

echo ""
echo "--- C3. 本课的三个坑是否点明 ---"
grep -nE '这是本课最重要的|本课最反直觉|最值得记住' "$F" | sed 's/^/  /'

echo ""
echo "--- C4. 悬念与下一课衔接 ---"
grep -cE '课 9|下一课|接力提示词' "$F" | sed 's/^/  衔接处数: /'

echo ""
echo "=========================================================="
echo " 评审核查完成"
echo "=========================================================="
