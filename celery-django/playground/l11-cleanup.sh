#!/usr/bin/env bash
# Phase 5 收尾清理：删掉实验工作目录、临时 worker、临时脚本
set -u
BASE=/mnt/d/projects/learning/celery-django

echo "=== 1. 清理残留进程 ==="
pkill -9 -f 'celery -A pw' > /dev/null 2>&1 || true
pkill -9 -f 'celery -A vt' > /dev/null 2>&1 || true
pkill -9 -f 'celery -A mt' > /dev/null 2>&1 || true
pkill -9 -f 'celery -A pw2' > /dev/null 2>&1 || true
sleep 2
echo "  剩余 celery 进程: $(pgrep -fc celery 2>/dev/null || echo 0)"

echo
echo "=== 2. 删除实验工作目录 ==="
rm -rf "$BASE/playground/l11-work" "$BASE/playground/l11-work2" "$BASE/playground/l11-work3"
rm -f /tmp/settings_celery.py.bak /tmp/anchors_used.txt /tmp/anchors_actual.txt /tmp/anchors_actual_raw.txt
echo "  已删除"

echo
echo "=== 3. 清理项目目录的运行时产物 ==="
bash "$BASE/playground/l10-cleanup.sh" 2>&1 | tail -3

echo
echo "=== 4. 最终交付物清单 ==="
cd "$BASE" || exit 1
echo "--- 根目录 Markdown ---"
ls -1 *.md
echo
echo "--- Phase 5 三份产物大小 ---"
wc -l 08-实战经验.md 09-排障速查手册.md 10-场景解法库.md
echo
echo "--- playground 保留的验证脚本（l11 取证/测量用）---"
ls -1 playground/l11-*.sh 2>/dev/null || echo "(无)"

exit 0
