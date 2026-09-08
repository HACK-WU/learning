#!/usr/bin/env bash
# 课 9 交付终验：全仓链接 + 讲义引用文件存在性 + 档案回写核验
set -uo pipefail
ROOT=/mnt/d/projects/learning/prometheus
LESSON=$ROOT/stages/3-规模化与生态/lessons/lesson-09-长期存储选型.md
PASS=0; FAIL=0
ok(){ PASS=$((PASS+1)); echo "  [PASS] $1"; }
bad(){ FAIL=$((FAIL+1)); echo "  [FAIL] $1 ($2)"; }

echo "============ 1. 正式交付物 Markdown 链接可达性 ============"
# 只扫正式交付物；排除 labs/**（那里是合并用的中间分片 part*.md，
# 其链接按最终目录书写，在 labs 下自然不通，不属于缺陷）
dead=0; total=0
find "$ROOT" -name '*.md' \
     -not -path '*/node_modules/*' \
     -not -path "$ROOT/labs/*" | while read -r f; do
  d=$(dirname "$f")
  grep -oE '\]\(\.\.?[^)#]+\.md\)' "$f" 2>/dev/null | sed 's/^](//; s/)$//' | while read -r rel; do
    if [ ! -f "$d/$rel" ]; then echo "DEAD|$f|$rel"; fi
  done
done > /tmp/deadlinks.txt 2>/dev/null
n=$(wc -l < /tmp/deadlinks.txt)
if [ "$n" -eq 0 ]; then ok "全仓无死链"; else
  bad "存在死链" "$n 条"; head -10 /tmp/deadlinks.txt | sed 's/^/    /'
fi

echo
echo "============ 2. 讲义引用的实验文件存在性 ============"
for f in setup.sh setup-thanos.sh setup-mimir.sh setup-mimir-tenants.sh setup-vm.sh \
         exp2-thanos-dedup-decisive.sh exp4-mimir-isolation.sh exp8-otlp-real.sh \
         exp10-final-compare.sh exp11-vmcluster.sh probe-bucket-field.sh \
         probe-bucket-field2.sh verify-part4.sh review-check.sh DATA.md; do
  if [ -f "$ROOT/labs/lesson-09/$f" ]; then ok "labs/lesson-09/$f"
  else bad "缺文件" "$f"; fi
done

echo
echo "============ 3. 四处档案回写核验 ============"
grep -q '课 9' "$ROOT/00-学习档案.md" && ok "① 00-学习档案.md 含课 9" || bad "① 学习档案" "无课 9"
grep -q '课 9' "$ROOT/00-评审清单.md" && ok "② 00-评审清单.md 含课 9" || bad "② 评审清单" "无课 9"
grep -q '课 9 完成情况' "$ROOT/stages/3-规模化与生态/overview.md" && ok "③ 阶段 overview 含课 9" || bad "③ overview" "无课 9"
grep -q '| 9 | 长期存储选型 | \[lesson-09' "$ROOT/02-课程目录.md" && ok "④ 02-课程目录.md 课 9 已标 ✅" || bad "④ 课程目录" "未标记"
grep -q '课 9 ✅' "$ROOT/01-学习路径总览.md" && ok "④ 01-学习路径总览.md 课 9 已标 ✅" || bad "④ 路径总览" "未标记"

echo
echo "============ 4. 进度数字一致性 ============"
a=$(grep -o '累计 \*\*27/36\*\*' "$ROOT/00-学习档案.md" | head -1)
b=$(grep -o '\*\*27/36 知识点\*\*' "$ROOT/01-学习路径总览.md" | head -1)
[ -n "$a" ] && ok "学习档案 27/36" || bad "学习档案进度" "非 27/36"
[ -n "$b" ] && ok "路径总览 27/36" || bad "路径总览进度" "非 27/36"

echo
echo "============ 5. 讲义体量 ============"
sz=$(wc -c < "$LESSON"); ln=$(wc -l < "$LESSON")
echo "  [INFO] $sz bytes / $ln lines"
[ "$ln" -gt 1500 ] && ok "行数 > 1500" || bad "篇幅偏短" "$ln"

echo
echo "============ 汇总 ============"
echo "  PASS=$PASS  FAIL=$FAIL"
[ "$FAIL" -eq 0 ] && echo "  ✅ 交付终验通过" || echo "  ❌ 有失败项"
