#!/bin/bash
# 课13 卫生检查 + 清理测试残留 topic
docker exec l11 /app/.venv/bin/python - <<'PYEOF' 2>&1 | grep -v -e Authlib -e "from ._compat"
import sys
from confluent_kafka.admin import AdminClient
a = AdminClient({"bootstrap.servers": "kafka-1:9092,kafka-2:9092,kafka-3:9092"})
ts = a.list_topics(timeout=10).topics
# 课13 测试产生的临时 topic
junk = [t for t in sorted(ts) if t.startswith(("tp-", "count-", "rv-", "skew-", "capstone-perf", "capstone-seg", "capstone-handle", "capstone-final", "l12-reb"))]
keep = [t for t in sorted(ts) if t.startswith("capstone")]
print(f"  集群共 {len(ts)} 个 topic")
print(f"  课13 临时 topic {len(junk)} 个:")
for t in junk:
    print(f"    - {t}")
print(f"  保留（capstone 工程用）{len(keep)} 个:")
for t in keep:
    print(f"    * {t}")
if junk and "--clean" in sys.argv:
    print(f"\n  清理中…")
    fs = a.delete_topics(junk)
    ok = 0
    for t, f in fs.items():
        try:
            f.result(timeout=10); ok += 1
        except Exception as e:
            print(f"    {t} 失败: {type(e).__name__}")
    print(f"  已删除 {ok}/{len(junk)}")
elif junk:
    print(f"\n  (加 --clean 参数执行删除)")
PYEOF
