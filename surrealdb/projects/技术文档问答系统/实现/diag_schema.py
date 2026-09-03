# -*- coding: utf-8 -*-
"""诊断：schema 里到底哪一条 400？chunk 表为什么是 0 条？"""
import sys
import os

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from common import Conn  # noqa: E402
from schema import SCHEMA  # noqa: E402
from init_db import split_statements, strip_comments  # noqa: E402

conn = Conn()

print("=" * 70)
print("1. 逐条执行 schema，打印每条的真实结果")
print("=" * 70)
stmts = split_statements(strip_comments(SCHEMA))
for i, s in enumerate(stmts):
    ok, payload, err = conn.sql(s)
    head = s.replace("\n", " ")[:88]
    if ok:
        print("  [%2d] OK    %s" % (i, head))
    else:
        body = payload if isinstance(payload, str) else str(payload)
        print("  [%2d] FAIL  %s" % (i, head))
        print("       %s" % body[:400])

print()
print("=" * 70)
print("2. chunk 表结构到底长什么样")
print("=" * 70)
ok, payload, err = conn.sql("INFO FOR TABLE chunk;")
res = payload[-1].get("result") if isinstance(payload, list) and payload else None
if res:
    print("  fields :", list(res.get("fields", {}).keys()))
    print("  indexes:", list(res.get("indexes", {}).keys()))
    print("  events :", list(res.get("events", {}).keys()))
    for k, v in res.get("indexes", {}).items():
        print("     %s -> %s" % (k, v))

print()
print("=" * 70)
print("3. 直接插一条试试（阳性对照）")
print("=" * 70)
ok, payload, err = conn.sql("""INSERT INTO chunk [{id: chunk:probe, doc: doc:l01, tenant: 'acme',
 seq: 99, text: '探针', grams: '探针', emb: [0.1,0.1,0.1,0.1,0.1,0.1,0.1,0.1,0.1,0.1,0.1,0.1]}];""")
print("  insert:", "OK" if ok else "FAIL")
print("  ", str(payload)[:400])
ok, payload, err = conn.sql("SELECT count() FROM chunk GROUP ALL;")
print("  count:", payload[-1].get("result") if isinstance(payload, list) else payload)
