#!/bin/bash
# 课 10 交付校验：检查正文、SVG、脚本、四处档案回写
# 用法：bash lesson10-verify.sh
# 输出：每项 [OK] / [FAIL]，末尾 VERIFY_OK 或 VERIFY_FAIL

BASE="/mnt/d/projects/learning/doris"
LESSON="$BASE/stages/4-分布式运维与生产落地/lessons/lesson-10-资源隔离与负载管理.md"
ASSETS="$BASE/stages/4-分布式运维与生产落地/assets"
SCRIPTS="$BASE/assets"
PASS=0
FAIL=0

chk() {
  if [ "$1" = "0" ]; then
    echo "  [OK] $2"
    PASS=$((PASS+1))
  else
    echo "  [FAIL] $2"
    FAIL=$((FAIL+1))
  fi
}

echo "=========================================="
echo " 课 10 交付校验"
echo "=========================================="

echo ""
echo "===== 1. 正文文件 ====="
[ -f "$LESSON" ]; chk $? "正文存在"
LINES=$(wc -l < "$LESSON")
[ "$LINES" -gt 1000 ]; chk $? "正文行数 > 1000（当前 $LINES）"

echo ""
echo "===== 2. 五幕结构 ====="
for sec in "第一幕" "第二幕" "第三幕" "第四幕" "第五幕"; do
  grep -q "## $sec" "$LESSON"; chk $? "含 $sec"
done

echo ""
echo "===== 3. 三个知识点 ====="
grep -q "知识点 1：Workload Group 与资源隔离" "$LESSON"; chk $? "含 知识点 1"
grep -q "知识点 2：内存管理" "$LESSON"; chk $? "含 知识点 2"
grep -q "知识点 3：查询并发与队列控制" "$LESSON"; chk $? "含 知识点 3"

echo ""
echo "===== 4. 收尾段落 ====="
grep -q "## 🐞 常见误区" "$LESSON"; chk $? "含常见误区"
grep -q "## ⚡ 速览模式" "$LESSON"; chk $? "含速览模式"
grep -q "## 🎓 课后小测" "$LESSON"; chk $? "含课后小测"
grep -q "## 🚀 下一批接力提示词" "$LESSON"; chk $? "含接力提示词"
grep -q "## 🧭 课程导航" "$LESSON"; chk $? "含课程导航"

echo ""
echo "===== 5. 边界标注（课 9 起强制项）====="
grep -q "实验边界" "$LESSON"; chk $? "含实验边界说明"
grep -q "已实测" "$LESSON"; chk $? "含【已实测】标记"
grep -q "cgroup" "$LESSON"; chk $? "含 cgroup 边界说明"
grep -q "数值浮动" "$LESSON"; chk $? "含数值浮动说明"

echo ""
echo "===== 6. 本课核心实测内容 ===== "
grep -q "MEM_LIMIT_EXCEEDED" "$LESSON"; chk $? "含内存超限报错原文"
grep -q "query waiting queue is full" "$LESSON"; chk $? "含队列满报错原文"
grep -q "query queue timeout" "$LESSON"; chk $? "含排队超时报错原文"
grep -q "Insert one new paused query" "$LESSON"; chk $? "含 paused query 日志证据"
grep -q "enable_spill" "$LESSON"; chk $? "含 enable_spill 默认值说明"
grep -q "memory_limit is not supported" "$LESSON"; chk $? "含废弃属性报错原文"

echo ""
echo "===== 7. SVG 资源 ====="
[ -f "$ASSETS/lesson-10-isolation.svg" ]; chk $? "isolation.svg 存在"
[ -f "$ASSETS/lesson-10-summary.svg" ]; chk $? "summary.svg 存在"
[ -s "$ASSETS/lesson-10-isolation.svg" ]; chk $? "isolation.svg 非空"
[ -s "$ASSETS/lesson-10-summary.svg" ]; chk $? "summary.svg 非空"
grep -q "lesson-10-isolation.svg" "$LESSON"; chk $? "正文引用 isolation.svg"
grep -q "lesson-10-summary.svg" "$LESSON"; chk $? "正文引用 summary.svg"

echo ""
echo "===== 8. 交付脚本 ====="
for s in lesson10-setup.sh lesson10-step1.sh lesson10-step2.sh \
         lesson10-step3.sh lesson10-cleanup.sh; do
  [ -f "$SCRIPTS/$s" ]; chk $? "脚本存在: $s"
done

echo ""
echo "===== 9. 脚本语法检查 ====="
for s in lesson10-setup.sh lesson10-step1.sh lesson10-step2.sh \
         lesson10-step3.sh lesson10-cleanup.sh; do
  cp "$SCRIPTS/$s" /tmp/l10syn.sh 2>/dev/null
  bash -n /tmp/l10syn.sh 2>/dev/null
  chk $? "语法正确: $s"
done

echo ""
echo "===== 10. 脚本不能出现的省略写法（硬约束）====="
BAD=0
while IFS= read -r f; do
  case "$f" in
    */lesson10-verify.sh|*/lesson10-review*.sh|*/lesson10-syntax.sh|*/lesson10-*.sh) ;;
  esac
  if grep -qE "（同上）|\(同上\)|列定义同上" "$f"; then
    echo "    ⚠ 发现省略写法: $f"
    BAD=1
  fi
done < <(ls "$SCRIPTS"/lesson10-[sc]*.sh)
[ "$BAD" = "0" ]; chk $? "脚本无「同上」类省略"

echo ""
echo "===== 11. 正文不能出现的省略写法 ====="
if grep -qE "（同上）|\(同上\)|列定义同上" "$LESSON" \
   && grep -vE "禁止出现|这类省略|没有「|无「" "$LESSON" | grep -qE "（同上）|\(同上\)|列定义同上"; then
  chk 1 "正文无「同上」类省略"
else
  chk 0 "正文无「同上」类省略"
fi

echo ""
echo "===== 12. 四处档案回写 ====="
grep -q "课 10 | Workload Group 与资源隔离 | ✅" "$BASE/00-学习档案.md"; chk $? "学习档案：Workload Group 已勾"
grep -q "课 10 | 内存管理与 Spill to Disk | ✅" "$BASE/00-学习档案.md"; chk $? "学习档案：Spill to Disk 已勾"
grep -q "课 10 | 查询并发与队列控制 | ✅" "$BASE/00-学习档案.md"; chk $? "学习档案：并发队列 已勾"
grep -qE "阶段 4·课 10" "$BASE/00-评审清单.md"; chk $? "评审清单：课 10 已记录"
grep -qE "课 10《资源隔离与负载管理》核心结论" "$BASE/stages/4-分布式运维与生产落地/overview.md"; chk $? "阶段 overview：课 10 核心结论"
grep -q "lesson-10-资源隔离与负载管理.md" "$BASE/02-课程目录.md"; chk $? "课程目录：课 10 已链接"
grep -qE "30 */ *36" "$BASE/01-学习路径总览.md"; chk $? "学习路径：进度 30/36"

echo ""
echo "===== 13. 导航链接 ====="
grep -q "lesson-09-副本高可用与扩缩容.md" "$LESSON"; chk $? "上一课链接正确"
grep -q "lesson-11-日常运维SchemaChange备份与升级.md" "$LESSON"; chk $? "下一课链接存在"
grep -q "../../../02-课程目录.md" "$LESSON"; chk $? "返回目录链接正确（../../../）"
grep -q "../overview.md" "$LESSON"; chk $? "返回阶段链接正确（../overview.md）"

echo ""
echo "=========================================="
echo " 通过: $PASS   失败: $FAIL"
if [ "$FAIL" = "0" ]; then
  echo " VERIFY_OK"
else
  echo " VERIFY_FAIL"
fi
echo "=========================================="
