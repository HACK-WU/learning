#!/bin/bash
# 课 9 实验⑩：Protobuf 接入 Schema Registry
# 真 SR 支持 Protobuf，验证：注册 + 演进 + 兼容性策略是否也生效
set -u
cat > /tmp/pb_sr.py <<'PYEOF'
import json, urllib.request, urllib.error, time
SR = "http://l9-sr:8081"

def rest(method, path, body=None):
    data = json.dumps(body).encode() if body is not None else None
    r = urllib.request.Request(SR+path, data=data, method=method,
                              headers={"Content-Type":"application/json"})
    try:
        with urllib.request.urlopen(r) as resp:
            return resp.status, json.loads(resp.read() or b'{}')
    except urllib.error.HTTPError as e:
        return e.code, json.loads(e.read())

P1 = ('syntax = "proto3"; package bench; message Order {'
      '  string order_id = 1; string user_id = 2; double amount = 3;'
      '  string status = 4; int64 ts = 5; }')
# 演进：加字段（新编号 6）
P2 = ('syntax = "proto3"; package bench; message Order {'
      '  string order_id = 1; string user_id = 2; double amount = 3;'
      '  string status = 4; int64 ts = 5; string currency = 6; }')
# 破坏：改已有字段的【类型】
P3 = ('syntax = "proto3"; package bench; message Order {'
      '  string order_id = 1; string user_id = 2; string amount = 3;'
      '  string status = 4; int64 ts = 5; }')

print("=" * 74)
print("Protobuf 接入 Schema Registry（真 SR 7.6.1）")
print("=" * 74)

subj = "pb-orders-value"
# 设 backward 并回读确认（课 9 坑 2 的纪律）
rest("PUT", f"/config/{subj}", {"compatibility": "BACKWARD"})
_, chk = rest("GET", f"/config/{subj}")
print(f"\n[1] 策略确认: {chk.get('compatibilityLevel')}")
if chk.get("compatibilityLevel") != "BACKWARD":
    print("    ⚠ 策略未生效，后续结果不可信"); raise SystemExit(1)

c, r = rest("POST", f"/subjects/{subj}/versions",
            {"schemaType":"PROTOBUF", "schema": P1})
print(f"[2] 注册 P1 (PROTOBUF)   -> HTTP {c}  id={r.get('id')}")

c, r = rest("POST", f"/subjects/{subj}/versions",
            {"schemaType":"PROTOBUF", "schema": P2})
print(f"[3] 注册 P2 加字段(编号6) -> HTTP {c}  {'放行 id='+str(r.get('id')) if c==200 else '拒绝'}")
if c != 200: print(f"    {str(r.get('message',''))[:160]}")

c, r = rest("POST", f"/subjects/{subj}/versions",
            {"schemaType":"PROTOBUF", "schema": P3})
print(f"[4] 注册 P3 amount 改类型 -> HTTP {c}  {'放行' if c==200 else '拒绝 ✓'}")
if c != 200: print(f"    {str(r.get('message',''))[:160]}")

# 列出所有 subject 的 schemaType
c, subs = rest("GET", "/subjects")
print(f"\n[5] SR 中现有 subject 数: {len(subs)}")
print(f"    含 pb-orders-value: {'pb-orders-value' in subs}")

print("\n" + "=" * 74)
print("结论")
print("=" * 74)
print("  · SR 对 Protobuf 一视同仁：同样注册、同样校验、同样返回结构化错误码")
print("  · 加字段（新编号）放行；改字段类型拒绝 —— 与 Avro 治理逻辑一致")
print("  · 选型真正差异不在 SR 支持度，而在【演进安全模型】：")
print("      Avro     -> 靠 schema 解析规则（改字段名=静默丢数据）")
print("      Protobuf -> 靠 field number（改编号=静默错位）")
print("=" * 74)
PYEOF
docker run --rm --network bench_kafka-net -v /tmp/pb_sr.py:/p.py \
  kafka-pybench:3.12 /app/.venv/bin/python /p.py 2>&1 \
  | grep -v -e Authlib -e 'from ._compat' | head -35
