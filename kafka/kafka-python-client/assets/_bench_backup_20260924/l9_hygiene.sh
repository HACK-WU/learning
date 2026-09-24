#!/bin/bash
# 课 9 交付前卫生检查
# 1. 讲义内本地链接可达性（课 9 的教训：索引曾滞后 5 课）
# 2. 四处档案是否都已回写
# 3. 集群残留：按课 7 教训，用客户端 API 列举，不用 CLI+2>/dev/null（会假阴性）
set -u
R=/mnt/d/projects/learning/kafka/kafka-python-client
D="$R/stages/3-生产层-吞吐与可靠性/课9-序列化与SchemaRegistry.md"

echo "===== 1. 讲义内本地链接可达性 ====="
grep -oE '\]\(\.\.?/[^)]+\)' "$D" | sed 's/](\(.*\))/\1/' | sort -u | while read L; do
  # 相对讲义所在目录解析
  T="$(dirname "$D")/$L"
  if [ -e "$T" ]; then echo "  ✓ $L"
  else echo "  ✗ 断链: $L"; fi
done

echo ""
echo "===== 2. 四处档案回写核验 ====="
echo "  00-学习档案.md:"
grep -c '| 3 | 课 9 | .*| ✅ 已完成 |' "$R/00-学习档案.md" | xargs -I{} echo "    课9 已完成行数: {}"
echo "  00-评审清单.md:"
grep -c '课 9 序列化与 Schema Registry' "$R/00-评审清单.md" | xargs -I{} echo "    课9 评审记录: {}"
echo "  02-课程目录.md:"
grep -c '课9-序列化与SchemaRegistry.md' "$R/02-课程目录.md" | xargs -I{} echo "    课9 链接: {}"
echo "  stages/3 overview.md:"
grep -c '课 9 | .*✅ 已讲解' "$R/stages/3-生产层-吞吐与可靠性/overview.md" | xargs -I{} echo "    课9 标记: {}"
echo "  01-学习路径总览.md:"
grep -c '已完成 9 课\|课 1–9' "$R/01-学习路径总览.md" | xargs -I{} echo "    进度更新: {}"

echo ""
echo "===== 3. 集群残留（客户端 API 列举，非 CLI）====="
cat > /tmp/hyg.py <<'PYEOF'
from kafka.admin import KafkaAdminClient
try:
    a = KafkaAdminClient(bootstrap_servers="kafka-1:9092,kafka-2:9092,kafka-3:9092",
                         client_id="hyg", request_timeout_ms=15000)
    ts = sorted(a.list_topics())
    a.close()
    print(f"  现存 topic ({len(ts)} 个):")
    for t in ts:
        mark = "  [课9资产]" if t.startswith("l9-") else ""
        print(f"    - {t}{mark}")
except Exception as e:
    print(f"  列举失败: {type(e).__name__}: {str(e)[:100]}")
PYEOF
docker run --rm --network bench_kafka-net -v /tmp/hyg.py:/h.py \
  kafka-pybench:3.12 /app/.venv/bin/python /h.py 2>&1 \
  | grep -v -e 'rdkafka#' -e 'Unclosed' | head -25
