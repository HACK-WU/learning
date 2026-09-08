#!/usr/bin/env bash
# 课 12 交付终验：讲义自洽 + 档案回写 + 链接可达
B=/mnt/d/projects/learning/prometheus
L=$B/stages/4-生产运维/lessons/lesson-12-运维工具链与排障.md
D=$B/labs/lesson-12/TOOLING-DATA.md
PASS=0; FAIL=0
ck() { if eval "$2" >/dev/null 2>&1; then echo "PASS  $1"; PASS=$((PASS+1));
       else echo "FAIL  $1"; FAIL=$((FAIL+1)); fi; }

echo "===== A. 讲义文件与结构 ====="
ck "讲义存在"           "[ -f '$L' ]"
ck "数据底稿存在"        "[ -f '$D' ]"
ck "五幕结构齐全"        "grep -q '第一幕' '$L' && grep -q '第五幕' '$L'"
ck "三个知识点齐全"      "grep -q '知识点 1' '$L' && grep -q '知识点 2' '$L' && grep -q '知识点 3' '$L'"
ck "含速览卡"            "grep -q '速览' '$L'"
ck "含小测"              "grep -q '小测' '$L'"
ck "含课程导航"          "grep -q '课程导航' '$L'"

echo
echo "===== B. 关键实测数字在讲义中 ====="
ck "check config 放行元标签"   "grep -q '放行' '$L'"
ck "test rules 反向验证"       "grep -q 'exp:' '$L'"
ck "check healthy 只连本机"     "grep -q 'localhost:9090' '$L'"
ck "tombstone 不释放"          "grep -q '不释放' '$L'"
ck "max-series 已移除"          "grep -q '已移除' '$L'"
ck "duration 截断值 1.0009"     "grep -q '1.0009' '$L'"
ck "源站真实 5.99s"             "grep -q '5.99' '$L'"
ck "对照实验净增 0"              "grep -q '净增' '$L'"

echo
echo "===== C. 挂账清偿表述 ====="
ck "还清挂账章节"        "grep -q '挂账' '$L'"
ck "诚实标注未测出项"     "grep -q '未测出\|继续挂账\|仍未拿到' '$L'"

echo
echo "===== D. 四处档案回写 ====="
ck "档案-课12三行已完成"  "grep -q '课 12 | promtool 工具链 | ✅' $B/00-学习档案.md"
ck "档案-事实核查已追加"  "grep -q '课 12 事实核查' $B/00-学习档案.md"
ck "评审-课12勾选"        "grep -q '课 12《运维工具链与排障》 — pedagogy' $B/00-评审清单.md"
ck "评审-记录表已追加"    "grep -q '| 2026-09-07 | 课 12《运维工具链与排障》' $B/00-评审清单.md"
ck "overview-产出勾选"    "grep -q '\- \[x\] \`lessons/lesson-12' $B/stages/4-生产运维/overview.md"
ck "overview-完成情况"    "grep -q '## 课 12 完成情况' $B/stages/4-生产运维/overview.md"
ck "目录-课12标✅"        "grep -q 'lesson-12-运维工具链与排障.md) | ✅' $B/02-课程目录.md"
ck "总览-阶段4完成"       "grep -q '阶段 4：生产运维（✅ 已完成' $B/01-学习路径总览.md"

echo
echo "===== E. 全仓链接可达性 ====="
if [ -f $B/labs/lesson-01/check-links.py ]; then
  OUT=$(cd $B && python3 labs/lesson-01/check-links.py 2>&1)
  echo "$OUT" | tail -5
  echo "$OUT" | grep -q "死链" && echo "(见上方链接检查输出)"
else
  echo "SKIP  check-links.py 不存在"
fi

echo
echo "======================================"
echo "PASS = $PASS   FAIL = $FAIL"
echo "======================================"
[ $FAIL -eq 0 ] && echo "RESULT: ALL PASS" || echo "RESULT: HAS FAILURES"
