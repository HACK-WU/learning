# -*- coding: utf-8 -*-
"""诊断：$request.body 到底是什么？为什么 q 是空的、count=0？

课 9 的教训：$request.body 当对象用会静默写空。本项目 cap-probe2 里
`/askp` 返回了 {"q": "EXPLAIN"}，说明对象访问在某种条件下是通的。
差异可能在：① Content-Type ② 端点用了 LET 中转 ③ 字符串拼接。
"""
import sys
import os
import json

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from common import Conn  # noqa: E402

conn = Conn()


def defapi(name, body_expr, method="POST"):
    q = """DEFINE API OVERWRITE "%s" FOR %s THEN {
  RETURN { body: encoding::json::encode(%s) };
};""" % (name, method, body_expr)
    ok, payload, err = conn.sql(q)
    if not ok:
        print("  ✗ 定义 %s 失败 %s" % (name, str(payload)[:200]))
        return False
    return True


def call(name, body=None, ct="application/json"):
    import urllib.request
    import urllib.error
    data = body.encode("utf-8") if isinstance(body, str) else body
    req = urllib.request.Request("http://127.0.0.1:8000/api/learn/docsqa%s" % name,
                                 data=data, method="POST")
    req.add_header("Authorization", "Basic " + __import__("base64").b64encode(b"root:root").decode())
    if ct:
        req.add_header("Content-Type", ct)
    try:
        with urllib.request.urlopen(req, timeout=15) as r:
            return r.status, r.read().decode("utf-8")
    except urllib.error.HTTPError as e:
        return e.code, e.read().decode("utf-8")
    except Exception as e:
        return -1, str(e)


PAYLOAD = json.dumps({"q": "索引", "k": 3})

print("=" * 74)
print("1. 直接回显 $request.body 整体")
print("=" * 74)
if defapi("/d1", "$request.body"):
    print("  →", call("/d1", PAYLOAD))

print()
print("=" * 74)
print("2. 取字段 $request.body.q")
print("=" * 74)
if defapi("/d2", "{ raw: $request.body, q: $request.body.q }"):
    print("  →", call("/d2", PAYLOAD))

print()
print("=" * 74)
print("3. 用 LET 中转后取字段（当前实现用的写法）")
print("=" * 74)
ok, _, err = conn.sql("""DEFINE API OVERWRITE "/d3" FOR POST THEN {
  LET $b = $request.body;
  LET $q = $b.q OR '';
  RETURN { body: encoding::json::encode({ b: $b, q: $q, t: type::string($b) }) };
};""")
print("  def:", "OK" if ok else err)
print("  →", call("/d3", PAYLOAD))

print()
print("=" * 74)
print("4. 不带 Content-Type 时")
print("=" * 74)
print("  →", call("/d3", PAYLOAD, ct=None))

print()
print("=" * 74)
print("5. 用 form 编码")
print("=" * 74)
print("  →", call("/d3", "q=%E7%B4%A2%E5%BC%95&k=3", ct="application/x-www-form-urlencoded"))

print()
print("=" * 74)
print("6. 空 body 时（GET 风格）")
print("=" * 74)
print("  →", call("/d3", "", ct="application/json"))

print()
print("=" * 74)
print("7. 对比：课 9 验证过的可用写法（裸字符串 body）")
print("=" * 74)
conn.sql("""DEFINE API OVERWRITE "/d4" FOR POST THEN {
  RETURN { body: $request.body };
};""")
print("  →", call("/d4", "hello", ct="text/plain"))

print()
print("=" * 74)
print("8. 关键：n 为什么是 0？查 grams @@ '' 的行为")
print("=" * 74)
ok, payload, err = conn.sql("SELECT count() FROM chunk WHERE grams @@ '' GROUP ALL;")
print("  空串查询：%s" % (payload[-1].get("result") if ok else str(payload)[:200]))
ok, payload, err = conn.sql("SELECT count() FROM chunk WHERE grams @@ '索引' GROUP ALL;")
print("  非空查询：%s" % (payload[-1].get("result") if ok else str(payload)[:200]))
