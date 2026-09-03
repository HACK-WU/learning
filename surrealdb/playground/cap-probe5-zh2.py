# -*- coding: utf-8 -*-
"""决定性实验（重做）：SurrealDB 3.2.4 全文检索对中文到底能不能用？

⚠️ 上一轮（cap-probe4）实验设计有缺陷：全文索引因分析器不存在而根本没建起来，
   于是英文组（阳性对照）也返回 [] —— 对照不成立，那一轮结论全部作废。
   本轮先确认索引真的存在（INFO FOR TABLE 回显 + EXPLAIN 走 IndexScan），再下结论。

变量：分析器（blank / class / punct）× 语种（英文 / 中文 / 中英混合）
"""
import json
import urllib.request
import urllib.error
import base64

BASE = "http://127.0.0.1:8000"
NS = "learn"
ROOT = "Basic " + base64.b64encode(b"root:root").decode()
DB = "cn2"


def sql(q, db=None):
    req = urllib.request.Request(BASE + "/sql", data=q.encode("utf-8"), method="POST")
    req.add_header("Accept", "application/json")
    req.add_header("surreal-ns", NS)
    req.add_header("surreal-db", db or DB)
    req.add_header("Authorization", ROOT)
    try:
        with urllib.request.urlopen(req, timeout=60) as r:
            code, txt = r.status, r.read().decode("utf-8")
    except urllib.error.HTTPError as e:
        code, txt = e.code, e.read().decode("utf-8")
    try:
        return code, json.loads(txt)
    except Exception:
        return code, txt


def run(q, tag="", db=None):
    code, res = sql(q, db)
    if code != 200:
        print("  [%-22s] HTTP %s %s" % (tag, code, str(res)[:220]))
        return None
    if isinstance(res, list) and res:
        last = res[-1]
        if last.get("status") == "OK":
            print("  [%-22s] OK %s" % (tag, json.dumps(last.get("result"), ensure_ascii=False)[:260]))
            return last.get("result")
        print("  [%-22s] %s %s" % (tag, last.get("status"), str(last)[:220]))
        return None
    print("  [%-22s] ??? %s" % (tag, str(res)[:150]))
    return None


print("=" * 78)
print("0. 复位：新建 cn2")
print("=" * 78)
run("REMOVE DATABASE IF EXISTS cn2;", "rm db", db="learn")
run("DEFINE DATABASE cn2;", "def db", db="learn")

run("""
DEFINE TABLE t SCHEMAFULL TYPE NORMAL;
DEFINE FIELD body ON t TYPE string;
DEFINE FIELD tag  ON t TYPE string;""", "ddl t")
run("""
INSERT INTO t [
  {id: t:en1, tag: 'en', body: 'SurrealDB supports indexes and query plans'},
  {id: t:en2, tag: 'en', body: 'Use EXPLAIN to inspect the query plan'},
  {id: t:zh1, tag: 'zh', body: '索引能加速查询 用 EXPLAIN 查看查询计划'},
  {id: t:zh2, tag: 'zh', body: '权限由 PERMISSIONS 子句控制'},
  {id: t:mx1, tag: 'mx', body: 'SurrealDB 的 EXPLAIN 可以查看 query plan'}
];""", "insert 5")

print()
print("=" * 78)
print("1. 先确认无索引时 @@ 的行为（基线）")
print("=" * 78)
run("SELECT id FROM t WHERE body @@ 'EXPLAIN';", "no-idx: EXPLAIN")
run("SELECT id FROM t WHERE body @@ 'EXPLAIN' EXPLAIN;", "no-idx: explain")

print()
print("=" * 78)
print("2. 建 FULLTEXT 索引（三个分析器各一次）")
print("=" * 78)
for az in ["a_blank", "a_class", "a_punct"]:
    run("DEFINE ANALYZER IF NOT EXISTS %s TOKENIZERS %s FILTERS lowercase,ascii;"
        % (az, az.replace("a_", "")), "analyzer " + az)

for az in ["a_blank", "a_class", "a_punct"]:
    print("  ---------- 分析器 = %s ----------" % az)
    run("REMOVE INDEX IF EXISTS idx_ft ON TABLE t;", "rm idx")
    run("DEFINE INDEX idx_ft ON TABLE t COLUMNS body FULLTEXT ANALYZER %s BM25 HIGHLIGHTS;" % az,
        "def idx " + az)
    run("INFO FOR TABLE t;", "info")
    run("SELECT id, search::score(0) AS s FROM t WHERE body @@ 'EXPLAIN';", "en EXPLAIN")
    run("SELECT id, search::score(0) AS s FROM t WHERE body @@ 'query';", "en query")
    run("SELECT id, search::score(0) AS s FROM t WHERE body @@ 'query plan';", "en phrase")
    run("SELECT id, search::score(0) AS s FROM t WHERE body @@ '索引';", "zh 索引")
    run("SELECT id, search::score(0) AS s FROM t WHERE body @@ '查询';", "zh 查询")
    run("SELECT id, search::score(0) AS s FROM t WHERE body @@ '权限';", "zh 权限")
    run("SELECT id FROM t WHERE body @@ 'EXPLAIN' EXPLAIN;", "explain en")

print()
print("=" * 78)
print("3. 中文是否整个被当成一整块 token？用整句精确匹配验证")
print("=" * 78)
run("SELECT id, search::score(0) AS s FROM t WHERE body @@ '索引能加速查询';", "整句 索引能加速查询")
run("SELECT id, search::score(0) AS s FROM t WHERE body @@ '权限由';", "片段 权限由")
run("SELECT id, search::score(0) AS s FROM t WHERE body @@ '子句控制';", "片段 子句控制")

print()
print("=" * 78)
print("4. ascii filter 把中文吃掉了？去掉 ascii 再试")
print("=" * 78)
run("DEFINE ANALYZER IF NOT EXISTS a_zh_blank TOKENIZERS blank FILTERS lowercase;", "az no-ascii")
run("REMOVE INDEX IF EXISTS idx_ft ON TABLE t;", "rm idx")
run("DEFINE INDEX idx_ft ON TABLE t COLUMNS body FULLTEXT ANALYZER a_zh_blank BM25 HIGHLIGHTS;", "def idx")
run("SELECT id, search::score(0) AS s FROM t WHERE body @@ '索引';", "zh 索引(no ascii)")
run("SELECT id, search::score(0) AS s FROM t WHERE body @@ '查询计划';", "zh 查询计划")
run("SELECT id, search::score(0) AS s FROM t WHERE body @@ 'EXPLAIN';", "en EXPLAIN")

print()
print("=" * 78)
print("5. 结论钉死：带空格的中文（模拟分词后）能否命中")
print("=" * 78)
run("UPDATE t:zh1 SET body = '索引 能 加速 查询 用 EXPLAIN 查看 查询 计划';", "加空格")
run("SELECT id, search::score(0) AS s FROM t WHERE body @@ '索引';", "zh 索引(空格版)")
run("SELECT id, search::score(0) AS s FROM t WHERE body @@ '查询';", "zh 查询(空格版)")
run("SELECT id, search::score(0) AS s FROM t WHERE body @@ 'EXPLAIN';", "en EXPLAIN(空格版)")

print()
print("=" * 78)
print("6. 最终采用方案可行性：自建 bigram 字段 + 全文索引")
print("=" * 78)
run("DEFINE FIELD grams ON t TYPE string;", "def grams")
run("""UPDATE t:zh1 SET grams = '索引 引能 能加 加速 速查 查询 询用 用E EX XP PL LA AI IN 查看 看查 查询 询计 计划';
UPDATE t:zh2 SET grams = '权限 限由 由P PE ER RM MI IS SS SI IO ON NS 子句 句控 控制';""", "fill grams")
run("REMOVE INDEX IF EXISTS idx_ft ON TABLE t;", "rm idx")
run("DEFINE INDEX idx_ft2 ON TABLE t COLUMNS grams FULLTEXT ANALYZER a_zh_blank BM25 HIGHLIGHTS;", "def idx grams")
run("SELECT id, search::score(0) AS s FROM t WHERE grams @@ '索引';", "grams 索引")
run("SELECT id, search::score(0) AS s FROM t WHERE grams @@ '查询';", "grams 查询")
run("SELECT id, search::score(0) AS s FROM t WHERE grams @@ '权限';", "grams 权限")
run("SELECT id, search::score(0) AS s FROM t WHERE grams @@ '计划';", "grams 计划")
run("SELECT id FROM t WHERE grams @@ '索引' EXPLAIN;", "grams explain")
run("SELECT id, search::highlight('<b>','</b>',0) AS h FROM t WHERE grams @@ '查询';", "grams highlight")
