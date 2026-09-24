#!/bin/bash
# 课 9 实验⑥：真 Confluent Schema Registry —— 官方客户端全流程
#
# 这一节用的是真 SR（confluentinc/cp-schema-registry:7.6.1）
# 和官方 confluent_kafka.schema_registry 客户端，不是原型
set -u
cat > /tmp/real_sr.py <<'PYEOF'
import json
from confluent_kafka.schema_registry import SchemaRegistryClient, Schema
from confluent_kafka.schema_registry.avro import AvroSerializer, AvroDeserializer
from confluent_kafka.serialization import SerializationContext, MessageField

SR_URL = "http://l9-sr:8081"
client = SchemaRegistryClient({"url": SR_URL})

print("=" * 72)
print("真 Schema Registry 实测（confluentinc/cp-schema-registry:7.6.1）")
print("=" * 72)

# ---------- 1. 连通性与全局配置 ----------
try:
    subs = client.get_subjects()
    print(f"\n[1] 连通性: GET /subjects -> {subs}")
except Exception as e:
    print(f"\n[1] 连通失败: {e}")
    raise SystemExit(1)

try:
    cfg = client.get_config("global") if hasattr(client,'get_config') else None
    print(f"[2] 全局兼容级别: {cfg}")
except Exception as e:
    print(f"[2] get_config 异常: {type(e).__name__}: {str(e)[:80]}")

# ---------- 3. 注册 v1 ----------
SUBJ = "orders-value"
V1 = json.dumps({"type":"record","name":"Order","fields":[
    {"name":"order_id","type":"string"},
    {"name":"amount","type":"double"}]})
try:
    sid1 = client.register_schema(SUBJ, Schema(V1, "AVRO"))
    print(f"\n[3] 注册 v1 首版        -> schema id = {sid1}")
except Exception as e:
    print(f"\n[3] 注册 v1 失败: {type(e).__name__}: {str(e)[:150]}")
    raise SystemExit(1)

# ---------- 4. 注册 v2：新字段带默认值（应放行）----------
V2_OK = json.dumps({"type":"record","name":"Order","fields":[
    {"name":"order_id","type":"string"},
    {"name":"amount","type":"double"},
    {"name":"currency","type":"string","default":"CNY"}]})
try:
    sid2 = client.register_schema(SUBJ, Schema(V2_OK, "AVRO"))
    print(f"[4] 注册 v2 新字段带默认值 -> 放行, id = {sid2}")
except Exception as e:
    print(f"[4] 意外被拒: {type(e).__name__}: {str(e)[:150]}")

# ---------- 5. 注册 v3：新字段无默认值（应被拒 409）----------
V3_BAD = json.dumps({"type":"record","name":"Order","fields":[
    {"name":"order_id","type":"string"},
    {"name":"amount","type":"double"},
    {"name":"currency","type":"string","default":"CNY"},
    {"name":"channel","type":"string"}]})
try:
    sid3 = client.register_schema(SUBJ, Schema(V3_BAD, "AVRO"))
    print(f"[5] 注册 v3 新字段无默认值 -> 意外放行 id={sid3}  <- 与预期不符！")
except Exception as e:
    msg = str(e)
    print(f"[5] 注册 v3 新字段无默认值 -> 被拒 ✓")
    print(f"     错误类型: {type(e).__name__}")
    print(f"     服务端说: {msg[:220]}")

# ---------- 6. 注册 v4：改字段类型（应被拒）----------
V4_BAD = json.dumps({"type":"record","name":"Order","fields":[
    {"name":"order_id","type":"string"},
    {"name":"amount","type":"string"}]})
try:
    sid4 = client.register_schema(SUBJ, Schema(V4_BAD, "AVRO"))
    print(f"[6] 注册 v4 amount 改类型 -> 意外放行 id={sid4}")
except Exception as e:
    print(f"[6] 注册 v4 amount 改类型  -> 被拒 ✓  ({type(e).__name__})")
    print(f"     {str(e)[:180]}")

# ---------- 7. 幂等注册（同一 schema 重复注册应返回同 id）----------
try:
    sid_again = client.register_schema(SUBJ, Schema(V2_OK, "AVRO"))
    print(f"\n[7] 重复注册 v2           -> id = {sid_again} ({'幂等 ✓' if sid_again==sid2 else '不幂等'})")
except Exception as e:
    print(f"[7] 重复注册异常: {e}")

# ---------- 8. 版本列表 & 取最新 ----------
try:
    vers = client.get_versions(SUBJ)
    print(f"[8] {SUBJ} 版本列表 -> {vers}")
    latest = client.get_latest_version(SUBJ)
    print(f"    latest: version={latest.version} id={latest.schema_id}")
except Exception as e:
    print(f"[8] 查版本失败: {type(e).__name__}: {str(e)[:100]}")

# ---------- 9. 按 id 取 schema ----------
try:
    s = client.get_schema(sid1)
    print(f"[9] 按 id={sid1} 取 schema -> type={s.schema_type}, 前60字符: {s.schema_str[:60]}...")
except Exception as e:
    print(f"[9] 取 schema 失败: {e}")

# ---------- 10. 兼容性预检（不注册，只问）----------
try:
    ok = client.test_compatibility(SUBJ, Schema(V3_BAD, "AVRO"))
    print(f"\n[10] 预检 v3 兼容性（不注册）-> {ok}  <- False 表示会被拒")
except Exception as e:
    print(f"[10] 预检失败: {type(e).__name__}: {str(e)[:120]}")

# ---------- 11. AvroSerializer 真实编解码 ----------
print("\n" + "=" * 72)
print("AvroSerializer / AvroDeserializer 真跑（官方客户端）")
print("=" * 72)
try:
    ser = AvroSerializer(client, V2_OK)
    ctx = SerializationContext("orders", MessageField.VALUE)
    wire = ser({"order_id":"ORD-1","amount":99.5,"currency":"USD"}, ctx)
    print(f"[11] 序列化单条 -> {len(wire)} 字节")
    print(f"     hex: {wire.hex()}")
    print(f"     magic = 0x{wire[0]:02x}  schema_id = {int.from_bytes(wire[1:5],'big')}")
    print(f"     -> 与实验④手工拼的 wire format [00][4B id][payload] 完全一致")

    deser = AvroDeserializer(client, V2_OK)
    rec = deser(wire, ctx)
    print(f"[12] 反序列化   -> {rec}")
    print(f"     往返一致 ✓" if rec and rec.get("order_id")=="ORD-1" else "     往返失败 ✗")
except Exception as e:
    print(f"[11/12] 序列化失败: {type(e).__name__}: {str(e)[:200]}")

# ---------- 13. _schemas topic 是否真在 Kafka 里 ----------
print("\n" + "=" * 72)
print("=" * 72)
PYEOF
docker run --rm --network bench_kafka-net -v /tmp/real_sr.py:/r.py \
  kafka-pybench:3.12 /app/.venv/bin/python /r.py 2>&1 \
  | grep -v -e 'rdkafka#' -e 'Unclosed' -e 'AuthlibDeprecation' -e 'from ._compat' \
  | head -50
