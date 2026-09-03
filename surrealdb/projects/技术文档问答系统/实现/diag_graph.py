# -*- coding: utf-8 -*-
"""诊断：为什么图扩展说「无邻居」？l05 明明 RELATE 到 l04。

嫌疑排序：
1. graph_expand 里 doc_ids 取到的是 record 对象而非字符串，IN 比较失败
2. 多语句查询（两条 SELECT）的返回结果结构与我的解析不符
3. refs 边的 PERMISSIONS 在 root 下也生效？不太可能（root 不受约束）
"""
import sys
import os
import json

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from common import Conn  # noqa: E402

conn = Conn()


def show(q, tag):
    ok, payload, err = conn.sql(q)
    print("--- %s" % tag)
    if not ok:
        print("    FAIL %s %s" % (err, str(payload)[:300]))
        return None
    if not isinstance(payload, list):
        print("    %s" % str(payload)[:300])
        return None
    for i, item in enumerate(payload):
        st = item.get("status")
        res = item.get("result")
        print("    [%d] status=%s  %s" % (i, st, json.dumps(res, ensure_ascii=False)[:300]))
    return payload


print("=" * 74)
print("1. refs 边到底有没有")
print("=" * 74)
show("SELECT count() FROM refs GROUP ALL;", "refs count")
show("SELECT id, in, out, kind FROM refs LIMIT 4;", "refs sample")

print()
print("=" * 74)
print("2. 直接遍历（最简形式）")
print("=" * 74)
show("SELECT * FROM refs LIMIT 2;", "refs raw")
show("SELECT id FROM doc:l05->refs->doc;", "l05 出边")
show("SELECT id FROM doc:l05<-refs<-doc;", "l05 入边")
show("SELECT id FROM doc:l04->refs->doc;", "l04 出边")
show("SELECT ->refs->doc AS out FROM doc:l05;", "l05 fetch 写法")

print()
print("=" * 74)
print("3. 多语句返回结构（graph_expand 用的就是这种）")
print("=" * 74)
show("SELECT id FROM doc:l05->refs->doc; SELECT id FROM doc:l05<-refs<-doc;",
     "两条语句一次发")

print()
print("=" * 74)
print("4. doc 字段取出来是什么类型")
print("=" * 74)
show("SELECT id, doc FROM chunk WHERE id = chunk:l05_0;", "chunk.doc 类型")
show("SELECT doc, type::string(doc) AS s FROM chunk WHERE id = chunk:l05_0;",
     "转字符串")

print()
print("=" * 74)
print("5. 复现 graph_expand 的取值逻辑")
print("=" * 74)
rows = conn.result("SELECT id, doc FROM chunk WHERE doc IN [doc:l05] LIMIT 2;")
print("    chunk.doc 原样 = %s" % json.dumps(rows, ensure_ascii=False)[:300])
if rows:
    d = rows[0].get("doc")
    print("    type = %s, 值 = %r" % (type(d).__name__, d))
    doc_ids = {r["doc"] for r in rows}
    print("    doc_ids = %r" % doc_ids)
    for dd in doc_ids:
        print("    用 %r 去遍历：" % dd)
        show("SELECT id FROM %s->refs->doc;" % dd, "  ->")
