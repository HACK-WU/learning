#!/bin/bash
# 课 9 实验⑤（续）：用最小 SR 原型实测"注册时强制校验"
#
# 核心问题：手工方案里，我可以直接塞个不兼容 schema 进去没人管
#           上了 SR 之后，注册动作本身就会被拒 —— 这才是 SR 的价值
set -u
cat > /tmp/mini_test.py <<'PYEOF'
import json, urllib.request, urllib.error

SR = "http://l9-minisr:8081"

def req(method, path, body=None):
    data = json.dumps(body).encode() if body is not None else None
    r = urllib.request.Request(SR + path, data=data, method=method,
                              headers={"Content-Type":"application/json"})
    try:
        with urllib.request.urlopen(r) as resp:
            return resp.status, json.loads(resp.read())
    except urllib.error.HTTPError as e:
        return e.code, json.loads(e.read())

V1 = json.dumps({"type":"record","name":"Order","fields":[
    {"name":"order_id","type":"string"},
    {"name":"amount","type":"double"}]})

print("=" * 72)
print("最小 SR 原型：注册时兼容性校验实测")
print("=" * 72)

# 1. 注册 v1（首个版本，无条件接受）
c, r = req("POST", "/subjects/orders-value/versions", {"schema": V1})
print(f"\n[1] 注册 v1（首版）      -> HTTP {c}  schema id = {r.get('id')}")

# 2. 注册 v2：加字段【带默认值】 —— 应放行
V2_OK = json.dumps({"type":"record","name":"Order","fields":[
    {"name":"order_id","type":"string"},
    {"name":"amount","type":"double"},
    {"name":"currency","type":"string","default":"CNY"}]})
c, r = req("POST", "/subjects/orders-value/versions", {"schema": V2_OK})
print(f"[2] 注册 v2 新字段带默认值 -> HTTP {c}  {'放行 id='+str(r.get('id')) if c==200 else '被拒'}")

# 3. 注册 v3：加字段【无默认值】 —— 应被拒
V3_BAD = json.dumps({"type":"record","name":"Order","fields":[
    {"name":"order_id","type":"string"},
    {"name":"amount","type":"double"},
    {"name":"currency","type":"string","default":"CNY"},
    {"name":"channel","type":"string"}]})
c, r = req("POST", "/subjects/orders-value/versions", {"schema": V3_BAD})
print(f"[3] 注册 v3 新字段无默认值 -> HTTP {c}  {'放行' if c==200 else '被拒 ✓'}")
if c != 200:
    print(f"     拒绝原因: {r.get('message','')[:150]}")

# 4. 注册 v4：类型缩窄 double -> float? 用 string->int 演示
V4_BAD = json.dumps({"type":"record","name":"Order","fields":[
    {"name":"order_id","type":"string"},
    {"name":"amount","type":"string"}]})
c, r = req("POST", "/subjects/orders-value/versions", {"schema": V4_BAD})
print(f"[4] 注册 v4 amount 改类型  -> HTTP {c}  {'放行' if c==200 else '被拒 ✓'}")
if c != 200:
    print(f"     拒绝原因: {r.get('message','')[:150]}")

# 5. int -> long 提升（应放行）
req("POST", "/subjects/num-value/versions", {"schema": json.dumps(
    {"type":"record","name":"N","fields":[{"name":"n","type":"int"}]})})
c, r = req("POST", "/subjects/num-value/versions", {"schema": json.dumps(
    {"type":"record","name":"N","fields":[{"name":"n","type":"long"}]})})
print(f"[5] 注册 int->long 提升    -> HTTP {c}  {'放行 ✓' if c==200 else '被拒'}")

# 6. 查 latest
c, r = req("GET", "/subjects/orders-value/versions/latest")
print(f"\n[6] 查 latest              -> HTTP {c}  version={r.get('version')} id={r.get('id')}")

# 7. 按 id 取 schema
c, r = req("GET", "/schemas/ids/1")
ok = c == 200 and "order_id" in str(r)
print(f"[7] 按 id=1 取 schema      -> HTTP {c}  {'取到 ✓' if ok else '失败'}")

print("\n" + "=" * 72)
print('结论：SR 的核心价值 = 把「能不能演进」从【上线后炸】提前到【注册时拒】')
print("=" * 72)
print("  · 手工方案：不兼容 schema 直接写进 topic，消费者读到才炸")
print("  · SR 方案 ：注册请求 HTTP 409，坏 schema 根本进不了系统")
print("  · 这是治理能力，不是序列化能力 —— 序列化两库都能做")
print()
print("⚠ 诚实标注：本原型只实现了 backward 一种策略 + 基础校验。")
print("  真 Confluent SR 还有 forward/full/full_transitive/none 等 7 种策略、")
print("  _schemas topic 持久化、多节点 HA、SSL/OAuth、数据脱敏规则(CSFLE)等。")
print("  原型用来理解机制，不能当生产实现。")
PYEOF
docker run --rm --network bench_kafka-net -v /tmp/mini_test.py:/t.py \
  kafka-pybench:3.12 /app/.venv/bin/python /t.py 2>&1 | head -40
