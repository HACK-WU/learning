#!/bin/bash
# 课 9 实验③：没有 Schema Registry 时，kafka-python 怎么管 schema？
#
# 预设待验证：总览写"Schema Registry 是 confluent-kafka 独占"
# 实测：kafka-python 顶层确实无 schema 符号（探路①已确认）
# 本实验回答：那用 kafka-python 的人怎么活？手工方案长什么样、代价是什么
set -u
cat > /tmp/nosr.py <<'PYEOF'
import json, io, struct, fastavro

print("=" * 72)
print("没有 Schema Registry 时，三种手工管 schema 的方案（实测）")
print("=" * 72)

avsc = {"type":"record","name":"Order","fields":[
    {"name":"order_id","type":"string"},
    {"name":"amount","type":"double"}]}
parsed = fastavro.parse_schema(avsc)
rec = {"order_id":"ORD-1","amount":99.5}
buf = io.BytesIO(); fastavro.schemaless_writer(buf, parsed, rec)
payload = buf.getvalue()

print(f"\n原始 Avro payload: {len(payload)} 字节  {payload.hex()}")

# ---- 方案 A：magic byte + schema id（Confluent 官方 wire format）----
# 布局: [0x00][4字节 big-endian schema id][payload]
schema_id = 7
wire = b"\x00" + struct.pack(">I", schema_id) + payload
print(f"\n【方案A】Confluent wire format（手工拼）")
print(f"  布局: magic(1) + schema_id(4) + payload({len(payload)})")
print(f"  总计: {len(wire)} 字节  ->  {wire.hex()}")
print(f"  读侧: 取前5字节拿到 id={struct.unpack('>I', wire[1:5])[0]}，再查 schema")
print(f"  代价: 每条多 5 字节；必须有个地方存 id->schema 映射")

# ---- 方案 B：每条消息带 schema 版本号 + 外部 schema 仓库 ----
v_wire = json.dumps({"v": 1, "d": rec}, separators=(",",":")).encode()
print(f"\n【方案B】消息内带版本号（最常见土办法）")
print(f"  JSON: {v_wire.decode()}")
print(f"  总计: {len(v_wire)} 字节")
print(f"  读侧: 按 v 字段 switch 到对应解析逻辑")
print(f"  代价: 版本散落在消费者代码里，加一版要改所有消费者")

# ---- 方案 C：把 schema 文本塞进 Kafka message header ----
print(f"\n【方案C】schema 放 Kafka Header（kafka-python 支持 headers）")
from kafka import KafkaProducer
# 修正：headers 是 send() 的参数，不是 __init__ 的。
# 首版脚本用 __init__ 检测得出 False 是【检测方法错误】，不是 kafka-python 不支持
sig_send = inspect.signature(KafkaProducer.send)
has_headers = "headers" in sig_send.parameters
print(f"  KafkaProducer.send 签名: {sig_send}")
print(f"  send() 支持 headers: {has_headers}  <- 在 send 上，不在 __init__ 上")
print(f"  做法: producer.send(topic, value=payload, headers=[('schema_id', b'7')])")
print(f"  代价: header 每条都传，比 magic byte 方案更啰嗦；无集中校验")

# ---- 关键对照 ----
print("\n" + "=" * 72)
print("三种方案 vs Schema Registry：差在哪")
print("=" * 72)
rows = [
    ("schema 存在哪",      "自己找地方存",        "SR 集中存 _schemas topic"),
    ("兼容性谁校验",        "没人校验/人肉评审",    "SR 注册时强制校验"),
    ("能设兼容策略吗",      "不能",               "SR 支持 backward/forward/full"),
    ("消费端怎么拿 schema", "约定俗成/硬编码",      "按 id 自动拉取+缓存"),
    ("改坏 schema 会怎样",  "上线后炸，回滚数据难",  "注册时就拒绝，炸不到生产"),
]
print(f"{'维度':<18}{'手工方案 (kafka-python)':<26}{'Schema Registry (confluent)'}")
print("-" * 72)
for a, b, c in rows:
    print(f"{a:<18}{b:<26}{c}")
print("=" * 72)
print("结论：")
print("  · kafka-python 不是'不能'用 Avro —— 序列化库是通用的，能自己拼")
print("  · 缺的是【集中式兼容性校验】这个治理能力，不是序列化能力本身")
print("  · 所以总览里'Schema Registry 独占'需改成：")
print("     'SR 客户端是 confluent-kafka 独占；Avro 序列化本身两库都能做'")
PYEOF
docker run --rm -v /tmp/nosr.py:/n.py kafka-pybench:3.12 \
  /app/.venv/bin/python /n.py 2>&1 | head -45
