#!/bin/bash
# 核验：Protobuf 7,428,822/s 比 Avro 快 10 倍，是否可信？
# 怀疑：循环中复用同一 message 对象，protobuf 的 upb 实现可能有内部缓存/复用
# 方法：每次新建对象再序列化，排除对象复用带来的偏差
set -u
cat > /tmp/pb_verify.py <<'PYEOF'
import json, time, io
from google.protobuf import descriptor_pb2, message_factory, descriptor_pool
from google.protobuf.descriptor_pb2 import FieldDescriptorProto as FDP
import fastavro

def make_msg_class(name, fields, pkg="bench"):
    fdp = descriptor_pb2.FileDescriptorProto()
    fdp.name = f"{name.lower()}_{int(time.time()*1000)%100000}_{name}.proto"
    fdp.package = pkg; fdp.syntax = "proto3"
    d = fdp.message_type.add(); d.name = name
    for i, (fn, ft) in enumerate(fields, 1):
        f = d.field.add(); f.name=fn; f.number=i; f.type=ft
        f.label = FDP.LABEL_OPTIONAL
    fd = descriptor_pool.Default().Add(fdp)
    return message_factory.GetMessageClass(fd.message_types_by_name[name])

F = [("order_id",FDP.TYPE_STRING),("user_id",FDP.TYPE_STRING),
     ("amount",FDP.TYPE_DOUBLE),("status",FDP.TYPE_STRING),("ts",FDP.TYPE_INT64)]
C = make_msg_class("OrderV", F)
data = {"order_id":"ORD-1","user_id":"U-1001","amount":99.5,
        "status":"PAID","ts":1735689600000}
N = 20000

print("=" * 72)
print("核验：Protobuf 吞吐为何比 Avro 高 10 倍")
print("=" * 72)

# A. 复用同一对象（首版测法）
rec = C(**data)
t0=time.perf_counter()
for _ in range(N): b = rec.SerializeToString()
a_e = N/(time.perf_counter()-t0)

# B. 每次新建对象（更公平）
t0=time.perf_counter()
for _ in range(N):
    b = C(**data).SerializeToString()
b_e = N/(time.perf_counter()-t0)

# C. 每次新建 + 逐个赋值（最保守）
t0=time.perf_counter()
for _ in range(N):
    m = C()
    m.order_id=data["order_id"]; m.user_id=data["user_id"]
    m.amount=data["amount"]; m.status=data["status"]; m.ts=data["ts"]
    b = m.SerializeToString()
c_e = N/(time.perf_counter()-t0)

# Avro 对照
sch = {"type":"record","name":"Order","fields":[
    {"name":"order_id","type":"string"},{"name":"user_id","type":"string"},
    {"name":"amount","type":"double"},{"name":"status","type":"string"},
    {"name":"ts","type":"long"}]}
parsed = fastavro.parse_schema(sch)
t0=time.perf_counter()
for _ in range(N):
    buf=io.BytesIO(); fastavro.schemaless_writer(buf, parsed, data)
av = N/(time.perf_counter()-t0)

# JSON 对照
t0=time.perf_counter()
for _ in range(N): json.dumps(data, separators=(",",":")).encode()
js = N/(time.perf_counter()-t0)

print(f"\n编码吞吐 (N={N}):")
print(f"  {'测法':<34}{'吞吐/s':>14}")
print(f"  {'-'*50}")
print(f"  {'A. Protobuf 复用同一对象':<34}{a_e:>14,.0f}")
print(f"  {'B. Protobuf 每次新建(构造参数)':<34}{b_e:>14,.0f}")
print(f"  {'C. Protobuf 每次新建+逐字段赋值':<34}{c_e:>14,.0f}")
print(f"  {'   Avro (fastavro)':<34}{av:>14,.0f}")
print(f"  {'   JSON':<34}{js:>14,.0f}")
print()
print(f"判定:")
print(f"  A vs B 差 {a_e/b_e:.1f}x  -> {'存在对象复用加成' if a_e/b_e > 1.5 else '复用不是主因'}")
print(f"  C 是最保守测法，C/Avro = {c_e/av:.1f}x")
print(f"  结论以【C】为准，不用 A（A 夸大了 protobuf）")
print("=" * 72)
PYEOF
docker run --rm -v /tmp/pb_verify.py:/v.py kafka-pybench:3.12 \
  /app/.venv/bin/python /v.py 2>&1 | grep -v -e Authlib -e 'from ._compat' | head -30
