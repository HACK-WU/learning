#!/bin/bash
# 课 9 交付校验：检查正文、SVG、脚本、四处档案回写
# 用法：bash lesson09-verify.sh
# 输出：每项 [OK] / [FAIL]，末尾 VERIFY_OK 或 VERIFY_FAIL

BASE="/mnt/d/projects/learning/doris"
LESSON="$BASE/stages/4-分布式运维与生产落地/lessons/lesson-09-副本高可用与扩缩容.md"
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
echo " 课 9 交付校验"
echo "=========================================="

echo ""
echo "===== 1. 正文文件 ====="
[ -f "$LESSON" ]; chk $? "正文存在"
LINES=$(wc -l < "$LESSON")
[ "$LINES" -gt 1000 ]; chk $? "正文行数 > 1000（当前 $LINES）"

echo ""
echo "===== 2. 五幕结构 ====="
for sec in "第一幕" "第二幕" "第三幕" "第四幕" "第五幕"; do
  grep -q "$sec" "$LESSON"; chk $? "含 $sec"
done

echo ""
echo "===== 3. 三个知识点 ====="
for kp in "知识点 1：多副本与自动修复" "知识点 2：FE 高可用" "知识点 3：扩缩容与数据均衡"; do
  grep -q "$kp" "$LESSON"; chk $? "含 $kp"
done

echo ""
echo "===== 4. 收尾段落 ====="
grep -q "## 🐞 常见误区" "$LESSON"; chk $? "含常见误区"
grep -q "## ⚡ 速览模式" "$LESSON"; chk $? "含速览模式"
grep -q "## 🎓 课后小测" "$LESSON"; chk $? "含课后小测"
grep -q "## 🚀 下一批接力提示词" "$LESSON"; chk $? "含接力提示词"
grep -q "## 🧭 课程导航" "$LESSON"; chk $? "含课程导航"

echo ""
echo "===== 5. 边界标注（课 9 新增强制项）====="
grep -q "实验边界" "$LESSON"; chk $? "含实验边界说明"
grep -q "已实测" "$LESSON"; chk $? "含【已实测】标记"
grep -q "原理推演" "$LESSON"; chk $? "含【原理推演】标记"
grep -q "same host" "$LESSON"; chk $? "含反亲和报错原文"

echo ""
echo "===== 6. SVG 资源 ====="
[ -f "$ASSETS/lesson-09-replica.svg" ]; chk $? "replica.svg 存在"
[ -f "$ASSETS/lesson-09-summary.svg" ]; chk $? "summary.svg 存在"
[ -s "$ASSETS/lesson-09-replica.svg" ]; chk $? "replica.svg 非空"
[ -s "$ASSETS/lesson-09-summary.svg" ]; chk $? "summary.svg 非空"
grep -q "lesson-09-replica.svg" "$LESSON"; chk $? "正文引用 replica.svg"
grep -q "lesson-09-summary.svg" "$LESSON"; chk $? "正文引用 summary.svg"

echo ""
echo "===== 7. 交付脚本 ====="
for s in lesson09-setup.sh lesson09-step4.sh lesson09-step5.sh \
         lesson09-add-be2.sh lesson09-cleanup.sh lesson09-verify.sh; do
  [ -f "$SCRIPTS/$s" ]; chk $? "脚本存在: $s"
done

echo ""
echo "===== 8. 脚本语法检查 ====="
for s in lesson09-setup.sh lesson09-step4.sh lesson09-step5.sh \
         lesson09-add-be2.sh lesson09-cleanup.sh; do
  cp "$SCRIPTS/$s" /tmp/l9syn.sh 2>/dev/null
  bash -n /tmp/l9syn.sh 2>/dev/null
  chk $? "语法正确: $s"
done

echo ""
echo "===== 9. 脚本不能出现的省略写法（硬约束）====="
BAD=0
while IFS= read -r f; do
  # 跳过校验脚本自身（它内含待检模式串）
  case "$f" in
    */lesson09-verify.sh) continue ;;
  esac
  if grep -qE "（同上）|\(同上\)|列定义同上" "$f"; then
    echo "    ⚠ 发现省略写法: $f"
    BAD=1
  fi
done < <(ls "$SCRIPTS"/lesson09-*.sh)
[ "$BAD" = "0" ]; chk $? "脚本无「同上」类省略"

echo ""
echo "===== 10. 正文不能出现的省略写法 ====="
# 排除「引用规则本身」的元描述行（如 禁止出现"（同上）"这类省略 / 没有"（同上）"这类省略）
if grep -qE "（同上）|\(同上\)|列定义同上" "$LESSON" \
   && grep -vE "禁止出现|这类省略|没有「|无「" "$LESSON" | grep -qE "（同上）|\(同上\)|列定义同上"; then
  chk 1 "正文无「同上」类省略"
else
  chk 0 "正文无「同上」类省略"
fi

echo ""
echo "===== 11. 四处档案回写 ====="
grep -q "课 9 | 多副本与自动修复 | ✅" "$BASE/00-学习档案.md"; chk $? "学习档案：多副本与自动修复 已勾"
grep -q "课 9 | FE 高可用 | ✅" "$BASE/00-学习档案.md"; chk $? "学习档案：FE 高可用 已勾"
grep -q "课 9 | 扩缩容与数据均衡 | ✅" "$BASE/00-学习档案.md"; chk $? "学习档案：扩缩容与数据均衡 已勾"
grep -qE "阶段 3·课 9|阶段 4·课 9" "$BASE/00-评审清单.md"; chk $? "评审清单：课 9 已记录"
grep -qE "课 9《副本[、]?高可用与扩缩容》核心结论" "$BASE/stages/4-分布式运维与生产落地/overview.md"; chk $? "阶段 overview：课 9 核心结论"
grep -q "lesson-09-副本高可用与扩缩容.md" "$BASE/02-课程目录.md"; chk $? "课程目录：课 9 已链接"
grep -qE "27 */ *36" "$BASE/01-学习路径总览.md"; chk $? "学习路径：进度 27/36"

echo ""
echo "===== 12. 导航链接 ====="
grep -q "../../3-数据导入与查询/lessons/lesson-08-多表关联与高级SQL.md" "$LESSON"; chk $? "上一课链接正确（../../3-...）"
grep -q "lesson-10-资源隔离与负载管理.md" "$LESSON"; chk $? "下一课链接存在"
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
