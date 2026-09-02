#!/bin/bash
# 评审 C 类：场景解法库结构核查 —— details 折叠开合配对 + 三件套内部链接目标可达性
set -u
cd /mnt/d/projects/learning/redis

echo "===== 1. details 折叠标签配对 ====="
for f in 10-场景解法库.md; do
  o=$(grep -c '<details>' "$f")
  c=$(grep -c '</details>' "$f")
  s=$(grep -c '<summary>' "$f")
  echo "  $f : details 开=$o 闭=$c  summary=$s"
  if [ "$o" = "$c" ]; then echo "    [OK] 配对正确"; else echo "    [FAIL] 配对不一致"; fi
done

echo
echo "===== 2. 每个场景是否都有三要素（先自己想 / 提示 / 展开解法）====="
for f in 08-实战经验.md 09-排障速查手册.md 10-场景解法库.md; do
  echo "  --- $f ---"
  echo "    场景数: $(grep -c '^## 场景' "$f")"
  echo "    先自己想: $(grep -c '先自己想' "$f")"
  echo "    提示折叠: $(grep -c '💡 提示' "$f")"
  echo "    展开解法: $(grep -c '展开解法' "$f")"
  echo "    解法一览: $(grep -c '解法一览' "$f")"
  echo "    知识点挂钩: $(grep -c '知识点挂钩' "$f")"
  echo "    不适用边界: $(grep -c '什么情况下此方案不适用' "$f")"
  echo "    做错会踩坑: $(grep -c '做错会踩的坑' "$f")"
done

echo
echo "===== 3. 三件套内部链接目标是否真实存在 ====="
for l in 08-实战经验.md 09-排障速查手册.md projects/电商大促数据层/README.md projects/电商大促数据层/设计决策.md; do
  if [ -f "$l" ]; then echo "  OK   $l"; else echo "  MISS $l"; fi
done

echo
echo "===== 4. 08/09/10 中引用的课时文件是否存在 ====="
for l in stages/1-为什么需要Redis/lessons/lesson-01-Redis是什么.md \
         stages/4-分布式与生产实践/lessons/lesson-08-缓存设计.md \
         stages/4-分布式与生产实践/lessons/lesson-09-生产实践与选型.md; do
  if [ -f "$l" ]; then echo "  OK   $l"; else echo "  MISS $l"; fi
done
