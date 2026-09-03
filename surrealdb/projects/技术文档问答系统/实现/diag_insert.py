# -*- coding: utf-8 -*-
"""诊断：INSERT INTO chunk 为什么留下 0 条？

假设：我的 sql() 把 HTTP 200 当成成功，但 SurrealDB 会在 HTTP 200 的响应体里
      返回 status=ERR（课 9 / 课 12 反复出现的"成功信号不可信"）。
      所以 init_db 报"6433/6433 成功"是假象。
"""
import sys
import os
import json

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from common import Conn  # noqa: E402
from seed import CORPUS, grams_field, embed  # noqa: E402

conn = Conn()


def raw(q, tag):
    ok, payload, err = conn.sql(q)
    print("--- %s" % tag)
    if not ok:
        print("    HTTP FAIL %s %s" % (err, str(payload)[:300]))
        return
    if isinstance(payload, list):
        for i, item in enumerate(payload):
            st = item.get("status")
            print("    [%d] status=%s time=%s" % (i, st, item.get("time")))
            if st != "OK":
                print("        %s" % json.dumps(item, ensure_ascii=False)[:400])
            else:
                print("        result=%s" % json.dumps(item.get("result"), ensure_ascii=False)[:200])
    else:
        print("    %s" % str(payload)[:300])


print("=" * 70)
print("1. 当前 chunk 数量（基线）")
print("=" * 70)
raw("SELECT count() FROM chunk GROUP ALL;", "count before")
raw("REMOVE TABLE IF EXISTS chunk_probe;", "rm probe table")
raw("DEFINE TABLE chunk_probe SCHEMAFULL TYPE NORMAL; "
    "DEFINE FIELD text ON chunk_probe TYPE string; "
    "DEFINE FIELD seq ON chunk_probe TYPE number;", "def probe table")

print()
print("=" * 70)
print("2. 四种 id 写法对照（找 INSERT 静默失败的真凶）")
print("=" * 70)

# A: id 作为字符串
raw("""INSERT INTO chunk_probe [{id: 'chunk_probe:a1', text: 'A字符串id', seq: 1}];""",
    "A: id 用字符串 'chunk_probe:a1'")

# B: id 作为 record id 字面量
raw("""INSERT INTO chunk_probe [{id: chunk_probe:b1, text: 'B记录id', seq: 2}];""",
    "B: id 用记录字面量 chunk_probe:b1")

# C: 不写 id
raw("""INSERT INTO chunk_probe [{text: 'C无id', seq: 3}];""", "C: 不写 id")

raw("SELECT count() FROM chunk_probe GROUP ALL;", "probe count")
raw("SELECT id, text FROM chunk_probe;", "probe rows")

print()
print("=" * 70)
print("3. 回到真实表：用 seed 生成的语句试一篇文档")
print("=" * 70)
did = CORPUS[0][0]
chunks = CORPUS[0][4]
rows = []
for i, text in enumerate(chunks):
    rows.append({
        "id": "chunk:%s_%d" % (did, i),
        "doc": "doc:%s" % did,
        "tenant": CORPUS[0][1],
        "seq": i,
        "text": text,
        "grams": grams_field(text),
        "emb": embed(text),
    })
print("  第 0 条 row 的 id 值 = %r (类型 %s)" % (rows[0]["id"], type(rows[0]["id"]).__name__))

q = "INSERT INTO chunk %s;" % json.dumps(rows, ensure_ascii=False)
raw(q, "INSERT 真实 chunk（字符串 id）")
raw("SELECT count() FROM chunk GROUP ALL;", "chunk count after")

print()
print("  ---- 改成记录字面量 id 再试 ----")
rows2 = []
for i, text in enumerate(chunks):
    rows2.append({
        "doc": "doc:%s" % did,
        "tenant": CORPUS[0][1],
        "seq": i,
        "text": text,
        "grams": grams_field(text),
        "emb": embed(text),
    })
q2 = "INSERT INTO chunk %s;" % json.dumps(rows2, ensure_ascii=False)
raw(q2, "INSERT 真实 chunk（无 id）")
raw("SELECT count() FROM chunk GROUP ALL;", "chunk count after2")

print()
print("=" * 70)
print("4. 用 CREATE 逐条写（慢但可靠）")
print("=" * 70)
for i, text in enumerate(chunks[:1]):
    raw("CREATE chunk:%s_%d SET doc=doc:%s, tenant='acme', seq=%d, text=%s, grams=%s, emb=%s;" % (
        did, i, did, i,
        "'" + text.replace("'", "\\'") + "'",
        "'" + grams_field(text).replace("'", "\\'") + "'",
        json.dumps(embed(text))), "CREATE chunk:%s_%d" % (did, i))
raw("SELECT count() FROM chunk GROUP ALL;", "chunk count after create")
