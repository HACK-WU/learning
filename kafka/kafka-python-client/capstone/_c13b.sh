#!/bin/bash
docker exec l11 /app/.venv/bin/python -c '
from confluent_kafka.admin import AdminClient
a = AdminClient({"bootstrap.servers": "kafka-1:9092,kafka-2:9092,kafka-3:9092"})
ts = a.list_topics(timeout=10).topics
junk = [t for t in sorted(ts) if t.startswith("capstone-") and len(t) == 10 and t[-1] in "ABCDEFG"]
print("  junk:", junk)
if junk:
    fs = a.delete_topics(junk)
    ok = 0
    for t, f in fs.items():
        try:
            f.result(timeout=10); ok += 1
        except Exception as e:
            print("  fail", t, type(e).__name__)
    print("  deleted", ok, "/", len(junk))
left = [t for t in sorted(a.list_topics(timeout=10).topics) if t.startswith("capstone")]
print("  left:", left)
print("  total topics:", len(a.list_topics(timeout=10).topics))
'
