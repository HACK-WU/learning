#!/bin/bash
# 课 9 实验②：序列化格式对照 —— 体积 / 速度 / 自描述性
#
# 课 9 的决策起点："消息格式怎么演进而不炸"
# 先看清楚各格式的代价，才能理解为什么 Avro+SR 是 Kafka 生态默认解
set -u
cat > /tmp/fmt.py <<'PYEOF'
import json, time, io, statistics as st
import fastavro

# 一条贴近真实的订单消息
rec = {"order_id":"ORD-20260922-000123","user_id":88012345,
       "amount":1299.50,"currency":"CNY","status":"PAID","paid":True,
       "sku_list":["SKU-1","SKU-2"],"ts":1769000000000}

N = 20000

# ---------- 1. JSON（无 schema，自描述靠重复 key）----------
t0=time.perf_counter()
jb_list=[json.dumps(rec,separators=(",",":")).encode() for _ in range(N)]
t_json_enc=time.perf_counter()-t0
t0=time.perf_counter()
for b in jb_list: json.loads(b)
t_json_dec=time.perf_counter()-t0
sz_json=len(jb_list[0])

# ---------- 2. Avro schemaless（schema 外部持有）----------
avsc={"type":"record","name":"Order","fields":[
  {"name":"order_id","type":"string"},{"name":"user_id","type":"long"},
  {"name":"amount","type":"double"},{"name":"currency","type":"string"},
  {"name":"status","type":"string"},{"name":"paid","type":"boolean"},
  {"name":"sku_list","type":{"type":"array","items":"string"}},
  {"name":"ts","type":"long"}]}
parsed=fastavro.parse_schema(avsc)
t0=time.perf_counter()
ab_list=[]
for _ in range(N):
    buf=io.BytesIO(); fastavro.schemaless_writer(buf,parsed,rec); ab_list.append(buf.getvalue())
t_avro_enc=time.perf_counter()-t0
t0=time.perf_counter()
for b in ab_list: fastavro.schemaless_reader(io.BytesIO(b),parsed)
t_avro_dec=time.perf_counter()-t0
sz_avro=len(ab_list[0])

# ---------- 3. Avro + 每条内嵌 schema（自描述的代价）----------
sz_avro_inline=sz_avro+len(json.dumps(avsc))

# ---------- 4. JSON + 内嵌 schema 名（常见折中：加个 type 字段）----------
rec_tagged=dict(rec); rec_tagged["_t"]="Order.v1"
sz_json_tagged=len(json.dumps(rec_tagged,separators=(",",":")).encode())

print("=" * 74)
print(f"序列化格式对照（N={N} 条同一订单消息，本机实测）")
print("=" * 74)
print(f"{'格式':<26}{'单条字节':>10}{'相对JSON':>10}")
print("-" * 74)
print(f"{'JSON（无 schema）':<26}{sz_json:>10}{'100%':>10}")
print(f"{'JSON + type 标记':<26}{sz_json_tagged:>10}{100*sz_json_tagged//sz_json:>9}%")
print(f"{'Avro（schema 外部）':<26}{sz_avro:>10}{100*sz_avro//sz_json:>9}%")
print(f"{'Avro + 内嵌 schema':<26}{sz_avro_inline:>10}{100*sz_avro_inline//sz_json:>9}%")
print("-" * 74)
print(f"  Avro 省下的 {sz_json-sz_avro} 字节/条 = 每条少 {(sz_json-sz_avro)/sz_json*100:.0f}%")
print(f"  但把 schema 塞回每条，立刻涨到 {sz_avro_inline} 字节（比裸 JSON 还大）")

print("\n" + "=" * 74)
print(f"{'格式':<26}{'编码吞吐':>16}{'解码吞吐':>16}")
print("-" * 74)
print(f"{'JSON':<26}{N/t_json_enc:>13,.0f}/s{N/t_json_dec:>13,.0f}/s")
print(f"{'Avro (fastavro 纯Python)':<26}{N/t_avro_enc:>13,.0f}/s{N/t_avro_dec:>13,.0f}/s")
print("-" * 74)
print(f"  ⚠ fastavro 是纯 Python 实现，比 json（C 加速）慢属预期。")
print(f"    生产上 Avro 的收益在【体积】与【演进】，不在单机编解码速度。")

print("\n" + "=" * 74)
print("关键洞察：为什么 Kafka 生态选 Avro 而不是 JSON")
print("=" * 74)
print(f"1. 体积：Avro {sz_avro} vs JSON {sz_json} 字节 —— 每条省 {sz_json-sz_avro} 字节")
print(f"   按 1 亿条/天算，省 {(sz_json-sz_avro)*1e8/1024/1024/1024:.1f} GB/天，磁盘+网络双省")
print(f"2. 演进：schema 有版本号，能校验'新旧能否互读'（上一实验已实测）")
print(f"3. 契约：schema 本身就是接口文档，跨语言团队不会各写各的")
print(f"4. 代价：必须额外部署 Schema Registry —— 多一个要运维的服务")
print("=" * 74)
PYEOF
docker run --rm -v /tmp/fmt.py:/f.py kafka-pybench:3.12 \
  /app/.venv/bin/python /f.py 2>&1 | head -45
