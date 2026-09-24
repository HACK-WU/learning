#!/bin/bash
# 课 9 实验⑨：Protobuf 补齐实测
#
# 补齐原因：讲义知识点标题写的是「JSON/Avro/Protobuf」，
#          但课 9 只验证了 Protobuf 客户端"能导入"，等于这块知识点是空的
#
# 关键技巧：本机没有 grpcio-tools（无 protoc），改用 descriptor_pb2
#          动态构造消息类型 —— 不预编译 .proto 也能跑
set -u
cat > /tmp/pb_main.py <<'PYEOF'
import json, time, sys
from google.protobuf import descriptor_pb2, message_factory
from google.protobuf.message import Message

# ============================================================
# 1. 动态构造 Protobuf 消息类型（不依赖 protoc）
# ============================================================
def make_msg_class(name, fields, pkg="bench"):
    """fields: [(字段名, 类型枚举, 是否optional)]"""
    fdp = descriptor_pb2.FileDescriptorProto()
    fdp.name = f"{name.lower()}.proto"
    fdp.package = pkg
    fdp.syntax = "proto3"
    d = fdp.message_type.add()
    d.name = name
    for i, (fname, ftype, *_) in enumerate(fields, start=1):
        f = d.field.add()
        f.name = fname
        f.number = i
        f.type = ftype
        f.label = descriptor_pb2.FieldDescriptorProto.LABEL_OPTIONAL
    pool = descriptor_pool.Default()
    # 同名重复构造会冲突，加随机后缀
    fdp.name = f"{name.lower()}_{int(time.time()*1000)%100000}.proto"
    file_desc = pool.Add(fdp)
    full = f"{pkg}.{name}"
    return message_factory.GetMessageClass(file_desc.message_types_by_name[name])

from google.protobuf import descriptor_pool
from google.protobuf.descriptor_pb2 import FieldDescriptorProto as FDP

FIELDS = [
    ("order_id", FDP.TYPE_STRING),
    ("user_id",  FDP.TYPE_STRING),
    ("amount",   FDP.TYPE_DOUBLE),
    ("status",   FDP.TYPE_STRING),
    ("ts",       FDP.TYPE_INT64),
]

OrderCls = make_msg_class("Order", FIELDS)
print("=" * 74)
print("Protobuf 补齐实测（google.protobuf 7.36.2，动态构造类型）")
print("=" * 74)
print(f"\n[1] 动态构造消息类型成功: {OrderCls.DESCRIPTOR.full_name}")
print(f"    字段: {[(f.name, f.number) for f in OrderCls.DESCRIPTOR.fields]}")

# ============================================================
# 2. 构造一条消息并序列化
# ============================================================
rec = OrderCls(order_id="ORD-1", user_id="U-1001",
               amount=99.5, status="PAID", ts=1735689600000)
pb_bytes = rec.SerializeToString()
print(f"\n[2] 序列化一条订单:")
print(f"    {rec}")
print(f"    字节数: {len(pb_bytes)}")
print(f"    hex   : {pb_bytes.hex()}")

# ============================================================
# 3. 与 JSON / Avro 三方体积对照（同一条数据）
# ============================================================
import fastavro
data = {"order_id":"ORD-1","user_id":"U-1001","amount":99.5,
        "status":"PAID","ts":1735689600000}
json_bytes = json.dumps(data, separators=(",",":")).encode()

avro_schema = {"type":"record","name":"Order","fields":[
    {"name":"order_id","type":"string"},
    {"name":"user_id","type":"string"},
    {"name":"amount","type":"double"},
    {"name":"status","type":"string"},
    {"name":"ts","type":"long"}]}
import io
buf = io.BytesIO()
fastavro.schemaless_writer(buf, fastavro.parse_schema(avro_schema), data)
avro_bytes = buf.getvalue()

print(f"\n[3] 同一条数据，三格式体积对照:")
print(f"    {'格式':<14}{'字节':<10}{'相对JSON'}")
print(f"    {'-'*36}")
base = len(json_bytes)
for n, b in [("JSON", json_bytes), ("Avro", avro_bytes), ("Protobuf", pb_bytes)]:
    print(f"    {n:<14}{len(b):<10}{len(b)/base*100:.0f}%")

# ============================================================
# 4. 吞吐对照（N=20000）
# ============================================================
N = 20000
print(f"\n[4] 吞吐对照 (N={N}):")
print(f"    {'格式':<14}{'编码/s':<16}{'解码/s'}")
print(f"    {'-'*44}")

t0=time.perf_counter()
for _ in range(N): json.dumps(data, separators=(",",":")).encode()
je=(time.perf_counter()-t0)
t0=time.perf_counter()
for _ in range(N): json.loads(json_bytes)
jd=(time.perf_counter()-t0)

parsed = fastavro.parse_schema(avro_schema)
t0=time.perf_counter()
for _ in range(N):
    b=io.BytesIO(); fastavro.schemaless_writer(b, parsed, data)
ae=(time.perf_counter()-t0)
t0=time.perf_counter()
for _ in range(N):
    fastavro.schemaless_reader(io.BytesIO(avro_bytes), parsed, parsed)
ad=(time.perf_counter()-t0)

# ⚠ 测法说明（核验后修正）：
#   首版复用同一 message 对象，得 7,428,822/s —— 该数字【夸大了 3.1 倍】。
#   upb 实现对复用对象有加成。核验用三种测法对比：
#     A 复用对象      6,517,458/s
#     B 每次新建      2,136,465/s
#     C 新建+逐字段   2,076,020/s   <- 最保守，讲义采用此值
#   结论：Protobuf 仍比 Avro 快约 2.7x，但不是 10x。
t0=time.perf_counter()
for _ in range(N):
    m = OrderCls()
    m.order_id = data["order_id"]; m.user_id = data["user_id"]
    m.amount = data["amount"]; m.status = data["status"]; m.ts = data["ts"]
    OrderCls.SerializeToString(m)
pe=(time.perf_counter()-t0)
t0=time.perf_counter()
for _ in range(N):
    m=OrderCls(); m.ParseFromString(pb_bytes)
pd=(time.perf_counter()-t0)

for n, e, d in [("JSON", je, jd), ("Avro", ae, ad), ("Protobuf", pe, pd)]:
    print(f"    {n:<14}{N/e:>12,.0f}   {N/d:>12,.0f}")

# ============================================================
# 5. Protobuf 演进：加字段（field number 递增）
# ============================================================
print(f"\n[5] Protobuf 演进实测 —— 加字段（新 field number）:")
FIELDS2 = FIELDS + [("currency", FDP.TYPE_STRING)]
OrderCls2 = make_msg_class("Order2", FIELDS2)
# 用新 schema 解析旧数据
old = OrderCls2(); old.ParseFromString(pb_bytes)
print(f"    新 reader 读旧数据: {old}")
print(f"    -> currency 自动为默认值 ''（proto3 无显式默认值语义）")

# 旧 reader 读新数据
new_rec = OrderCls2(order_id="ORD-2", user_id="U-1002", amount=50.0,
                    status="NEW", ts=1735689600000, currency="USD")
new_bytes = new_rec.SerializeToString()
old_reader = OrderCls(); old_reader.ParseFromString(new_bytes)
print(f"    旧 reader 读新数据: {old_reader}")
print(f"    -> 未知的 currency 被放进 unknown fields，不报错")

# ============================================================
# 6. Protobuf 的致命坑：改 field number
# ============================================================
print(f"\n[6] Protobuf 独占的坑 —— 改 field number 会怎样:")
# 把 amount 的 number 从 3 改成 6，模拟"重构时重排编号"
FIELDS_RENUM = [
    ("order_id", FDP.TYPE_STRING),   # 1
    ("user_id",  FDP.TYPE_STRING),   # 2
    ("status",   FDP.TYPE_STRING),   # 3  <- 原本 amount 是 3！
    ("amount",   FDP.TYPE_DOUBLE),   # 4
    ("ts",       FDP.TYPE_INT64),    # 5
]
OrderRenum = make_msg_class("OrderR", FIELDS_RENUM)
misread = OrderRenum(); misread.ParseFromString(pb_bytes)
print(f"    原始: amount=99.5, status='PAID'")
print(f"    被重排编号的 schema 读出: {misread}")
print(f"    -> 字段错位！amount 的 wire data 被当成了 status 来解析（或反之）")
print(f"    ⚠ Protobuf 靠【数字编号】识别字段，不看字段名。")
print(f"      改编号 = 数据语义错位，且不报错 —— 这是 Avro 没有的风险。")

print("\n" + "=" * 74)
print("Protobuf 结论")
print("=" * 74)
print(f"  1. 体积: Protobuf {len(pb_bytes)} 字节 vs Avro {len(avro_bytes)} vs JSON {base}")
print(f"  2. 三格式同量级，都不是瓶颈；选型的真正分水岭在生态与演进安全")
print(f"  3. Protobuf 演进靠【只增不改 field number】保证安全")
print(f"  4. ⚠ 改 field number 会静默错位 —— Protobuf 独有风险")
print(f"  5. 无 protoc 也能玩：descriptor_pb2 动态构造即可")
print("=" * 74)
PYEOF
docker run --rm -v /tmp/pb_main.py:/p.py kafka-pybench:3.12 \
  /app/.venv/bin/python /p.py 2>&1 | grep -v -e Authlib -e 'from ._compat' | head -60
