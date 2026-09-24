#!/bin/bash
# 课 10 最终卫生检查：档案/链接/集群残留
set -u
R=/mnt/d/projects/learning/kafka/kafka-python-client
S3="$R/stages/3-生产层-吞吐与可靠性"
echo "===== 1. 讲义本地链接 ====="
cd "$S3"
grep -oE '\]\([^)]+\.md\)' "课10-消费者工程与并发模型.md" | sed 's/](//;s/)//' | sort -u | while read l; do
  [ -f "$l" ] && echo "  ✓ $l" || echo "  ✗ 死链: $l"
done

echo ""
echo "===== 2. 四处档案 ====="
grep -c '课 10' "$R/00-学习档案.md" | xargs -I{} echo "  00-学习档案.md  课10行数: {}"
grep -c '课 10' "$R/00-评审清单.md" | xargs -I{} echo "  00-评审清单.md  课10记录: {}"
grep -c '课10-消费者工程与并发模型' "$R/02-课程目录.md" | xargs -I{} echo "  02-课程目录.md  课10链接: {}"
grep -c '课 10.*2026-09-23' "$S3/overview.md" | xargs -I{} echo "  overview.md     课10完成: {}"
grep -c '课 1–10' "$R/01-学习路径总览.md" | xargs -I{} echo "  01-学习路径总览 进度: {}"

echo ""
echo "===== 3. 集群残留 ====="
docker run --rm --network bench_kafka-net kafka-pybench:3.12 \
  /app/.venv/bin/python -c "
from confluent_kafka.admin import AdminClient
a=AdminClient({'bootstrap.servers':'kafka-1:9092'})
ts=[t for t in a.list_topics().topics if t.startswith('l10')]
print('  l10 相关 topic:', sorted(ts) if ts else '无')
" 2>&1 | grep -v -e Authlib -e 'from ._compat'

echo ""
echo "===== 4. 残留容器 ====="
docker ps -a --filter name=l10 --format '  {{.Names}} {{.Status}}' 2>/dev/null | head -5
echo "  (空即为无残留)"
