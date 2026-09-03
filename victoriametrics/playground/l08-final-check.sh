#!/bin/bash
# 课 8 最终校验
cd /mnt/d/projects/learning/victoriametrics/playground || exit 1
echo "===== 1. 课 8 交付自检（仅看问题项）====="
bash l08-check-delivery.sh 2>&1 | grep -E 'MISS|BAD|合计问题|断链数'
echo
echo "===== 2. 全局链接可达性 ====="
python3 l05-link-check.py 2>&1 | tail -8
echo
echo "===== 3. 双 agent 评审（结论行）====="
bash l08-run-review.sh 2>&1 | grep -A5 '评审结论'
echo
echo "===== 4. 四处档案落盘确认 ====="
cd /mnt/d/projects/learning/victoriametrics
echo "-- 1) 00-学习档案.md --"
grep -c '课 8' 00-学习档案.md | awk '{print "     课 8 出现次数:", $1}'
grep '课 8' 00-学习档案.md | head -4
echo "-- 2) 00-评审清单.md --"
grep '课 8' 00-评审清单.md | head -3
echo "-- 3) 阶段 4 概览 --"
grep -n '课 8' 'stages/4-怎么横向扩展/README.md' | head -3
echo "-- 4a) 课程目录 --"
grep -n '8-集群三件套' 02-课程目录.md
echo "-- 4b) 学习路径总览 --"
grep -n '已完成 8 课\|28 个' 01-学习路径总览.md
