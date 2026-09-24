import sys
from confluent_kafka.admin import AdminClient

a = AdminClient({"bootstrap.servers": "kafka-1:9092,kafka-2:9092,kafka-3:9092}")
ts = a.list_topics(timeout=10).topics
# 逐行排除实验自建的单字母 topic（A~G）
junk = [t for t in sorted(ts) if len(t) == 11 and t.startswith("capstone-")
        and t[-1] in "ABCDEFG" and t[-2] == "-"]
print(f"  待清理: {junk}")
if junk and "clean" in sys.argv:
    fs = a.delete_topics(junk)
    ok = 0
    for t, f in fs.items():
        try:
            f.result(timeout=10)
            ok += 1
        except Exception as e:
            print(f"    {t} 失败: {type(e).__name__}")
    print(f"  已删除 {ok}/{len(junk)}")
left = sorted(a.list_topics(timeout=10).topics)
print(f"\n  剩余 capstone 相关:")
for t in left:
    if t.startswith("capstone"):
        print(f"    * {t}")
print(f"  集群共 {len(left)} 个 topic")
