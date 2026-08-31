#!/usr/bin/env bash
# 检查每条手册条目是否都有「止血」步骤（手册特征 3 的硬要求）
set -u
cd /mnt/d/projects/learning/celery-django || exit 1

awk '
/^## [0-9]+ · /  { if (sec != "" && has == 0) print "❌ 缺止血: " sec; sec = $0; has = 0 }
/^\| \*\*止血/  { has = 1 }
END              { if (sec != "" && has == 0) print "❌ 缺止血: " sec }
' 09-排障速查手册.md

echo "--- 汇总 ---"
total=$(grep -cE '^## [0-9]+ · ' 09-排障速查手册.md)
with_stop=$(grep -cE '^\| \*\*止血' 09-排障速查手册.md)
echo "条目总数: $total"
echo "有止血步的条目数: $with_stop"
exit 0
