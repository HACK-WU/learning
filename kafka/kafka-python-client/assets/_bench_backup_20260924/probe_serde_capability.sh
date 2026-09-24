#!/bin/bash
# 课 9 探路①：三库【客户端侧】序列化/schema 能力边界
# 不启动任何服务，纯看已装库里有什么
set -u
cat > /tmp/s9.py <<'PYEOF'
import importlib, importlib.metadata as md

def try_imp(name):
    try:
        m = importlib.import_module(name)
        return m
    except Exception:
        return None

print("=" * 62)
print("A. confluent-kafka 的 schema_registry 子包")
print("=" * 62)
sr = try_imp("confluent_kafka.schema_registry")
if sr is None:
    print("  ✗ confluent_kafka.schema_registry 不存在（未装或版本不含）")
else:
    print(f"  ✓ 存在: {sr.__file__}")
    for sub in ("avro", "protobuf", "json_schema", "SchemaRegistryClient"):
        f = try_imp(f"confluent_kafka.schema_registry.{sub}")
        print(f"    .{sub:<22} = {'✓' if f else '✗'}")
    try:
        import confluent_kafka.schema_registry as S
        print(f"    导出符号: {[x for x in dir(S) if not x.startswith('_')][:14]}")
    except Exception as e:
        print(f"    取导出失败: {e}")

print("\n" + "=" * 62)
print("B. 独立序列化库可用性")
print("=" * 62)
for lib in ("avro", "fastavro", "google.protobuf",
            "jsonschema", "msgspec", "orjson", "pydantic"):
    m = try_imp(lib)
    if m:
        try:
            v = md.version(lib.replace(".", "-"))
        except Exception:
            try: v = md.version(lib)
            except Exception: v = "?"
        print(f"  ✓ {lib:<20} {v}")
    else:
        print(f"  ✗ {lib:<20} 未安装")

print("\n" + "=" * 62)
print("C. kafka-python / kafka-python-ng 的 schema 支持")
print("=" * 62)
import kafka
print(f"  kafka 版本: {md.version('kafka-python')}")
hits = [x for x in dir(kafka) if "schema" in x.lower() or "avro" in x.lower()]
print(f"  顶层含 schema/avro 的导出符号: {hits if hits else '（无）'}")
print("  ⚠ kafka-python 定位是纯协议客户端，序列化交给用户自己 —— 需实测确认")

print("\n" + "=" * 62)
print("D. 各格式序列化体积对照（同一条业务消息，1 库 1 表）")
print("=" * 62)
import json, struct
rec = {"order_id": "ORD-20260921-000123", "user_id": 88012345,
       "amount": 1299.50, "currency": "CNY", "status": "PAID",
       "items": [{"sku": "SKU-1", "qty": 2}, {"sku": "SKU-2", "qty": 1}],
       "paid": True}
jb = json.dumps(rec, separators=(",", ":")).encode()
print(f"  JSON  (无 schema)      {len(jb):>4} 字节")

# 手写紧凑二进制（模拟 schema 化：省掉重复 key）
b = rec["order_id"].encode() + b"|" + str(rec["user_id"]).encode() \
    + b"|" + str(rec["amount"]).encode() + b"|" + rec["currency"].encode() \
    + b"|" + rec["status"].encode() + b"|" + str(rec["paid"]).encode()
print(f"  紧凑二进制(无自描述)   {len(b):>4} 字节  <- 省 {100-100*len(b)//len(jb)}% 但无法演进")

if try_imp("fastavro"):
    import io, fastavro
    schema = {"type": "record", "name": "Order", "fields": [
        {"name": "order_id", "type": "string"},
        {"name": "user_id", "type": "long"},
        {"name": "amount", "type": "double"},
        {"name": "currency", "type": "string"},
        {"name": "status", "type": "string"},
        {"name": "paid", "type": "boolean"}]}
    buf = io.BytesIO()
    fastavro.write(buf, schema, [{k: rec[k] for k in
                   ("order_id","user_id","amount","currency","status","paid")}])
    ab = buf.getvalue()
    print(f"  Avro  (schema 分离)    {len(ab):>4} 字节  <- 不含 schema 时")
    print(f"  Avro  +内嵌 schema     {len(ab)+len(json.dumps(schema)):>4} 字节  <- 自描述时")
print("  ⚠ Avro 的关键：schema 不随每条消息走，靠 schema id 引用")
PYEOF
docker run --rm -v /tmp/s9.py:/s9.py kafka-pybench:3.12 \
  /app/.venv/bin/python /s9.py 2>&1 | grep -v -e 'rdkafka#' -e 'Unclosed' | head -50
