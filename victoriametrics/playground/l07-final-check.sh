#!/bin/bash
# 课 7 最终校验：全局链接 + 交付自检
cd /mnt/d/projects/learning/victoriametrics/playground || exit 1
echo "===== 全局链接可达性 ====="
python3 l05-link-check.py 2>&1 | tail -10
echo
echo "===== 课 7 交付自检（仅看问题项）====="
bash l07-check-delivery.sh 2>&1 | grep -E 'MISS|BAD|合计问题|断链数'
