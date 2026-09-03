# -*- coding: utf-8 -*-
"""诊断三处验收失败：B7 / C5 / D3

C5 最严重：「记录用户无法写入」居然写入成功了 —— 可能是真漏洞，
也可能是我的断言写错了（比如 UPSERT 语义、或 CREATE 走了别的路径）。
必须查清楚，不能糊弄过去。
"""
import sys
import os
import json

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from common import Conn  # noqa: E402
from seed import DEFAULT_PASSWORD  # noqa: E402

conn = Conn()


def show(q, tag, token=None):
    c = Conn(token=token) if token else conn
    ok, payload, err = c.sql(q)
    print("--- %s" % tag)
    if not ok:
        print("    FAIL %s %s" % (err, str(payload)[:260]))
        return None
    if isinstance(payload, list):
        for i, item in enumerate(payload):
            print("    [%d] %s %s" % (i, item.get("status"),
                                      json.dumps(item.get("result"), ensure_ascii=False)[:260]))
    return payload


print("=" * 74)
print("【B7】「不存在的词zzz」为什么有结果？")
print("=" * 74)
from common import grams_field  # noqa: E402
Q = "这个术语肯定不存在zzz"
print("  原串：%s" % Q)
print("  bigram：%s" % grams_field(Q))
terms = grams_field(Q).split()
print("  terms：%s" % terms)
for t in terms[:6]:
    ok, payload, err = conn.sql("SELECT count() FROM chunk WHERE grams @@ '%s' GROUP ALL;" % t)
    n = payload[-1]["result"][0]["count"] if ok else "?"
    print("      term %r 命中 %s 条" % (t, n))

print()
print("  结论方向：中文单字（如「个」「定」「存」「在」）在语料里普遍存在，")
print("  所以「不存在的词」也能召回一堆 —— 这是 bigram 分词的固有噪声，")
print("  不是 bug。验收应改为检查分数极低，而不是检查结果为空。")

print()
print("=" * 74)
print("【C5】记录用户写入 chunk 到底成功没有？")
print("=" * 74)
tok = conn.signin("app", email="alice@acme.io", password=DEFAULT_PASSWORD)
uc = Conn(token=tok)

print("  --- 1. 尝试 CREATE（表级 create NONE）---")
show("CREATE chunk:hack1 SET text='x', tenant='acme', seq=0, grams='x', "
     "emb=[0,0,0,0,0,0,0,0,0,0,0,0];", "alice CREATE chunk", token=tok)

print("  --- 2. 真的写进去了吗？用 root 查（阳性对照）---")
show("SELECT id, tenant FROM chunk WHERE id = chunk:hack1;", "root 查 hack1")

print("  --- 3. 用 alice 自己查 ---")
show("SELECT id FROM chunk WHERE id = chunk:hack1;", "alice 查 hack1", token=tok)

print("  --- 4. 对照：写一个不存在的字段（应该被 SCHEMAFULL 拒）---")
show("CREATE chunk:hack2 SET nonexistent_field = 1;", "alice 写未定义字段", token=tok)

print("  --- 5. 对照：UPSERT 是否也绕过？---")
show("UPSERT chunk:hack3 SET text='y', tenant='acme', seq=0, grams='y', "
     "emb=[0,0,0,0,0,0,0,0,0,0,0,0];", "alice UPSERT chunk", token=tok)
show("SELECT id FROM chunk WHERE id = chunk:hack3;", "root 查 hack3")

print("  --- 6. 对照：写 ask_audit（同样 create NONE）---")
show("CREATE ask_audit SET q='hack', tenant='acme', n=0;", "alice 写 audit", token=tok)

print("  --- 7. 决定性：INFO FOR TABLE chunk 看权限定义 ---")
res = conn.result("INFO FOR TABLE chunk;")
print("    tables 定义：%s" % json.dumps(res, ensure_ascii=False)[:600])

print()
print("=" * 74)
print("【D3】GET /qa 为什么 404？")
print("=" * 74)
res = conn.result("INFO FOR DB;")
apis = res.get("apis", {}) if isinstance(res, dict) else {}
print("  已定义端点：%s" % json.dumps(apis, ensure_ascii=False)[:400])
print()
print("  api() 方法调用 /qa（GET）：", conn.api("/qa", "GET"))
print("  api() 方法调用 /qa（POST）：", conn.api("/qa", "POST", "{}"))
