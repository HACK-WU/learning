#!/bin/bash
# 课 9 实验①：Avro schema 演进兼容性 —— 本地判定（不依赖 Schema Registry）
#
# 目的：验证"哪些改动安全、哪些会炸"。这是课 9 的核心知识，
#       Schema Registry 只是把这套规则搬到服务端强制执行。
# 方法：用 fastavro 实测 writer/reader schema 解析，而非凭文档推断
#
# API 修正记录（实测）：
#   fastavro.write / fastavro.schema.parse_schema 在 1.12 里是【模块】不是函数
#   正确入口：fastavro.schemaless_writer / schemaless_reader / parse_schema
#   用 schemaless 更贴合 Kafka：消息体不含 schema，靠外部 schema id 引用
set -u
cat > /tmp/compat.py <<'PYEOF'
import io, fastavro

def enc(schema, rec):
    """用 writer schema 编码（schemaless：不含 schema 本身）"""
    buf = io.BytesIO()
    fastavro.schemaless_writer(buf, fastavro.parse_schema(schema), rec)
    return buf.getvalue()

def dec(writer_schema, reader_schema, data):
    """用 reader schema 解码 writer 写的数据 —— 演进的本质"""
    buf = io.BytesIO(data)
    return fastavro.schemaless_reader(
        buf, fastavro.parse_schema(writer_schema),
        fastavro.parse_schema(reader_schema))

v1 = {"type":"record","name":"Order","fields":[
    {"name":"order_id","type":"string"},
    {"name":"amount","type":"double"}]}
d1 = enc(v1, {"order_id":"ORD-1","amount":99.5})
print(f"v1 编码 {len(d1)} 字节（schemaless，不含 schema 文本）\n")

cases = []

def run(name, w, r, note, data=None):
    try:
        out = dec(w, r, data if data is not None else d1)
        print(f"  ✓ {name}: {out}")
        cases.append((name, "读得通", note)); return out
    except Exception as e:
        print(f"  ✗ {name}: {type(e).__name__}: {str(e)[:70]}")
        cases.append((name, "报错", f"{type(e).__name__}")); return None

print("--- 演进 1：新增字段【带默认值】（BACKWARD 兼容）---")
run("新字段+默认值", v1,
    {"type":"record","name":"Order","fields":[
        {"name":"order_id","type":"string"},
        {"name":"amount","type":"double"},
        {"name":"currency","type":"string","default":"CNY"}]},
    "旧数据读出默认 currency=CNY")

print("\n--- 演进 2：新增字段【无默认值】（BACKWARD 不兼容）---")
run("新字段无默认值", v1,
    {"type":"record","name":"Order","fields":[
        {"name":"order_id","type":"string"},
        {"name":"amount","type":"double"},
        {"name":"currency","type":"string"}]},
    "旧数据缺该字段")

print("\n--- 演进 3：删除字段（reader 少字段）---")
run("删字段", v1,
    {"type":"record","name":"Order","fields":[{"name":"order_id","type":"string"}]},
    "reader 忽略多余字段")

print("\n--- 演进 4：字段类型提升 int -> long（Avro 允许）---")
vi = {"type":"record","name":"M","fields":[{"name":"n","type":"int"}]}
di = enc(vi, {"n":42})
run("int->long 提升", vi,
    {"type":"record","name":"M","fields":[{"name":"n","type":"long"}]},
    "Avro 原生支持的类型提升", di)

print("\n--- 演进 5：字段类型缩窄 long -> int（危险）---")
vl = {"type":"record","name":"M","fields":[{"name":"n","type":"long"}]}
dl = enc(vl, {"n":42})
run("long->int 缩窄(小值42)", vl,
    {"type":"record","name":"M","fields":[{"name":"n","type":"int"}]},
    "小值侥幸读出，大值溢出", dl)

dl_big = enc(vl, {"n":3000000000})   # 超出 int32 范围
try:
    out = dec(vl, {"type":"record","name":"M","fields":[{"name":"n","type":"int"}]}, dl_big)
    print(f"  ? long->int 缩窄(大值30亿): 读出 {out} <- 数据已损坏")
    cases.append(("long->int 缩窄(大值)", "静默损坏", "30亿读成负数/错值"))
except Exception as e:
    print(f"  ✗ long->int 缩窄(大值30亿): {type(e).__name__}: {str(e)[:60]}")
    cases.append(("long->int 缩窄(大值)", "报错拦截", type(e).__name__))

print("\n--- 演进 6：改字段名 amount -> total（等同删+加）---")
run("改字段名", v1,
    {"type":"record","name":"Order","fields":[
        {"name":"order_id","type":"string"},
        {"name":"total","type":"double","default":0.0}]},
    "total 拿默认值 0.0，原 amount 数据丢失")

print("\n" + "=" * 70)
print("兼容性判定汇总（fastavro 1.12.2 本地实测）")
print("=" * 70)
print(f"{'演进类型':<22}{'本地结果':<12}说明")
print("-" * 70)
for a,b,c in cases:
    print(f"{a:<22}{b:<12}{c}")
print("=" * 70)
print("实测修正（重要）：我最初预判的 3 个'静默危险'，实测只中 1 个")
print("  1. 新字段无默认值  -> 本地真报错（SchemaResolutionError），非静默")
print("  2. long->int 缩窄  -> 本地真报错（Schema mismatch），非大值才炸")
print("  3. 改字段名        -> 【本地静默通过】amount=99.5 变成 total=0.0，零警告")
print()
print("真正的风险排序（按实测危险度）：")
print("  🥇 改字段名：数据语义丢失且无任何报错，只能靠规范/SR 的字段名策略防")
print("  🥈 删字段  ：读得通，但下游若还要该字段会拿到 None/缺失")
print("  🥉 类型变更：fastavro 本地就拦得住，反而是安全的")
print()
print("结论：'读得通'不等于'演进安全'。改字段名是唯一本地完全静默的破坏性改动，")
print("      这正是必须上 Schema Registry 的核心理由——把规范变成强制校验。")
PYEOF
docker run --rm -v /tmp/compat.py:/c.py kafka-pybench:3.12 \
  /app/.venv/bin/python /c.py 2>&1 | head -45
