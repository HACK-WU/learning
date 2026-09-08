set -x
cd /mnt/d/projects/learning/prometheus/labs/lesson-03

FIRST=$(ls blocks | head -1)
echo "=== 首个 block: $FIRST ==="
ls blocks | wc -l

echo
echo "=== 该 block 的完整文件结构 ==="
find "blocks/$FIRST" -type f | sort

echo
echo "=== meta.json ==="
cat "blocks/$FIRST/meta.json"

echo
echo "=== 各文件大小 ==="
ls -la "blocks/$FIRST"
