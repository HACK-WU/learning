# -*- coding: utf-8 -*-
"""技术文档问答系统 · 公共层

统一三件事：
1. HTTP 连接与鉴权（⚠️ root 用 Basic，记录用户用 Bearer —— 3.2.4 实测）
2. 中文分词（⚠️ SurrealDB 3.2.4 内置全文检索对中文无效，必须自建 bigram）
3. 主题向量（本机无 embedding 模型，用确定性主题分布代替，见 README 诚实标注）

所有"看起来多余"的注释都对应一次真实踩坑，删掉就会重犯。
"""
import base64
import json
import math
import re
import urllib.error
import urllib.request

BASE = "http://127.0.0.1:8000"
NS = "learn"
DB = "docsqa"

ROOT_USER = "root"
ROOT_PASS = "root"
ROOT_AUTH = "Basic " + base64.b64encode(
    ("%s:%s" % (ROOT_USER, ROOT_PASS)).encode("utf-8")).decode("ascii")

# 12 个主题维度：与 TOPIC_KEYWORDS 一一对应，顺序即向量下标
TOPICS = [
    "index",        # 0 索引与查询计划
    "permission",   # 1 权限与多租户
    "graph",        # 2 图与关系
    "vector",       # 3 向量与检索
    "realtime",     # 4 实时推送
    "function",     # 5 函数与逻辑下推
    "storage",      # 6 存储后端
    "deploy",       # 7 部署与运维
    "schema",       # 8 建模与类型
    "crud",         # 9 增删改查
    "transaction",  # 10 事务
    "observability" # 11 可观测
]

TOPIC_KEYWORDS = {
    "index":        ["索引", "index", "查询计划", "explain", "全表扫描", "tablescan", "indexscan"],
    "permission":   ["权限", "permission", "多租户", "tenant", "隔离", "roles", "access", "登录", "signin"],
    "graph":        ["图", "graph", "关系", "边", "relate", "遍历", "traverse", "递归", "深度"],
    "vector":       ["向量", "vector", "embedding", "knn", "相似度", "hnsw", "混合检索", "rrf"],
    "realtime":     ["实时", "live", "订阅", "推送", "event", "触发器", "websocket"],
    "function":     ["函数", "function", "逻辑下推", "api", "端点", "视图", "view", "computed"],
    "storage":      ["存储", "storage", "rocksdb", "内存", "memory", "持久", "版本化", "时间旅行"],
    "deploy":       ["部署", "deploy", "集群", "docker", "备份", "export", "import", "分布式"],
    "schema":       ["schema", "字段", "类型", "建模", "schemafull", "schemaless", "记录id", "record"],
    "crud":         ["增删改查", "crud", "create", "select", "update", "delete", "upsert", "写入", "批量"],
    "transaction":  ["事务", "transaction", "回滚", "commit", "原子"],
    "observability":["监控", "metrics", "日志", "可观测", "指标", "耗时", "性能", "慢查询"],
}

# ---------------------------------------------------------------- 中文分词

_CJK = re.compile(r"[\u4e00-\u9fff]")
_TOKEN = re.compile(r"[a-z0-9]+|[\u4e00-\u9fff]")


def tokenize(text):
    """切成 token 列表：英文/数字按词，中文按字。"""
    return _TOKEN.findall((text or "").lower())


def bigrams(text):
    """中文 bigram：把「索引能加速」切成 索引/引能/能加/加速 ...

    ⚠️ 为什么必须这么做（3.2.4 实测，cap-probe5-zh2.py）：
    内置 FULLTEXT 用 blank/class 分析器时，「索引」这类中文查询**一条都查不到**，
    而同样的索引查英文 EXPLAIN 正常命中 —— 说明索引是好的，是分析器不会切中文。
    把中文预先切成 bigram 再交给全文索引，命中率与 BM25 打分都正常，且 EXPLAIN
    确认走 FullTextScan。3.2.4 不支持 ngram() tokenizer（Parse error），只能自己做。
    """
    toks = tokenize(text)
    out = []
    for t in toks:
        if len(t) == 1 and _CJK.match(t):
            out.append(t)
    # 连续汉字串才有 bigram 价值
    for run in re.findall(r"[\u4e00-\u9fff]{2,}", (text or "").lower()):
        for i in range(len(run) - 1):
            out.append(run[i:i + 2])
    # 英文/数字 token 原样保留，让全文索引也能吃到英文关键词
    for t in toks:
        if not (_CJK.match(t) and len(t) == 1):
            out.append(t)
    return out


def grams_field(text):
    """生成写进 chunk.grams 的字符串（空格分隔），供 FULLTEXT 索引使用。"""
    return " ".join(bigrams(text))


# ---------------------------------------------------------------- 主题向量

def embed(text, dim=None):
    """确定性主题向量：统计各主题关键词命中次数 → 归一化。

    ⚠️ 诚实标注：这不是真实 embedding。本机没有 embedding 模型与外网模型下载，
    用「主题直方图」代替，保证：
      - 同一类文档彼此靠近（同主题词多 → 向量接近）
      - 与关键词检索捕捉的信号不同（关键词是字面精确，这是语义主题分布）
    因此混合检索的互补性仍然真实可演示，只是"语义"退化成"主题"。
    换成真 embedding 只需替换本函数，其余代码不动。
    """
    n = dim or len(TOPICS)
    low = (text or "").lower()
    vec = [0.0] * n
    for i, topic in enumerate(TOPICS[:n]):
        for kw in TOPIC_KEYWORDS[topic]:
            if kw in low:
                vec[i] += 1.0
    norm = math.sqrt(sum(v * v for v in vec))
    if norm > 0:
        vec = [v / norm for v in vec]
    else:
        # 全零向量在 COSINE 距离下无意义，给一个均匀分布做兜底
        vec = [1.0 / math.sqrt(n)] * n
    return vec


# ---------------------------------------------------------------- HTTP

class Conn:
    def __init__(self, base=BASE, ns=NS, db=DB, token=None):
        self.base, self.ns, self.db = base, ns, db
        self.token = token  # None = 走 root（Basic）

    def _headers(self, json_body=False):
        h = {"Accept": "application/json",
             "surreal-ns": self.ns,
             "surreal-db": self.db}
        # ⚠️ 关键：root 必须用 Basic；记录用户 token 必须用 Bearer。
        # 反过来用会 401 InvalidToken（3.2.4 实测，cap-auth.sh）。
        h["Authorization"] = ("Bearer " + self.token) if self.token else ROOT_AUTH
        if json_body:
            h["Content-Type"] = "application/json"
        return h

    def sql(self, query):
        """返回 (ok, payload, err)。

        ⚠️⚠️ 三个真实的坑，缺一个就会静默失败（本项目第二十次，diag_insert 抓出）：

        坑 1：HTTP 200 ≠ 语句成功。SurrealDB 会在 HTTP 200 的响应体里返回
              status=ERR（如字段类型不匹配）。只看 HTTP 码会以为全部成功。
              → 必须检查响应体里**每一条**语句的 status。

        坑 2：JSON 里给 record 字段传字符串（如 "doc": "doc:l01"）不会被自动
              转换，报 Expected `record<doc>` but found `'doc:l01'`。
              → 记录字段要用 surrealdb 的记录字面量语法，不能加引号。

        坑 3：JSON 里给 id 传字符串 "chunk:l01_0" 不会报错，但会生成一个
              嵌套 id：chunk:`chunk:l01_0`（反引号包裹）。数据写进去了，但
              你按原 id 永远查不到。
              → id 要么不写，要么用记录字面量。
        """
        req = urllib.request.Request(self.base + "/sql",
                                     data=query.encode("utf-8"), method="POST")
        for k, v in self._headers().items():
            req.add_header(k, v)
        try:
            with urllib.request.urlopen(req, timeout=60) as r:
                payload = json.loads(r.read().decode("utf-8"))
        except urllib.error.HTTPError as e:
            return False, e.read().decode("utf-8"), "HTTP %s" % e.code
        except Exception as e:
            return False, str(e), type(e).__name__

        if isinstance(payload, list):
            for item in payload:
                if item.get("status") == "ERR":
                    return False, item, item.get("result") or item.get("kind")
        return True, payload, None

    def result(self, query):
        """执行并取最后一条语句的 result；失败抛 RuntimeError。"""
        ok, payload, err = self.sql(query)
        if not ok:
            raise RuntimeError("SQL failed (%s): %s" % (err, str(payload)[:400]))
        if not isinstance(payload, list) or not payload:
            return None
        last = payload[-1]
        if last.get("status") != "OK":
            raise RuntimeError("SQL status=%s: %s"
                               % (last.get("status"), json.dumps(last, ensure_ascii=False)[:400]))
        return last.get("result")

    def run_batch(self, statements):
        """逐条执行并打印结果。单条失败不阻断整批（课 9 块级运行器教训）。"""
        ok_count = 0
        for s in statements:
            s = s.strip()
            if not s:
                continue
            ok, payload, err = self.sql(s)
            if ok:
                ok_count += 1
            else:
                print("  ✗ %s\n    %s" % (err, str(payload)[:200]))
        return ok_count

    def api(self, path, method="GET", body=None):
        """调用 /api/:ns/:db 下的自定义端点（走真实 HTTP）。

        ⚠️ 不要用 api::invoke() 验证端点：它会把 500 伪装成 200（课 9 教训，
        本项目 cap-probe2 复现）。端点必须 RETURN { body: ... }。
        """
        data = body.encode("utf-8") if isinstance(body, str) else body
        url = "%s/api/%s/%s%s" % (self.base, self.ns, self.db, path)
        req = urllib.request.Request(url, data=data, method=method)
        for k, v in self._headers(json_body=data is not None).items():
            req.add_header(k, v)
        try:
            with urllib.request.urlopen(req, timeout=30) as r:
                return r.status, r.read().decode("utf-8")
        except urllib.error.HTTPError as e:
            return e.code, e.read().decode("utf-8")
        except Exception as e:
            return -1, str(e)

    def signin(self, access, **creds):
        body = {"NS": self.ns, "DB": self.db, "AC": access}
        body.update(creds)
        req = urllib.request.Request(self.base + "/signin",
                                     data=json.dumps(body).encode("utf-8"), method="POST")
        req.add_header("Accept", "application/json")
        req.add_header("Content-Type", "application/json")
        try:
            with urllib.request.urlopen(req, timeout=15) as r:
                return json.loads(r.read().decode("utf-8")).get("token")
        except urllib.error.HTTPError as e:
            # ⚠️ 登录失败返回 404 而非 401（不泄露用户是否存在，课 10）
            raise RuntimeError("signin failed: HTTP %s %s" % (e.code, e.read().decode()[:200]))
        except Exception as e:
            raise RuntimeError("signin failed: %s" % e)


def fmt_ms(t):
    """把服务端自报的 time 字段解析成毫秒。

    ⚠️ 不要写 float(t.rstrip("ms"))：rstrip 按字符集剔除，遇 "177.871µs"
    会剩 "177.871µ"，float() 直接抛 ValueError（课 12 P0-1）。
    """
    if t is None:
        return None
    s = str(t).strip()
    for suf, mult in (("ns", 1e-6), ("µs", 1e-3), ("us", 1e-3),
                      ("ms", 1.0), ("s", 1000.0)):
        if s.endswith(suf):
            try:
                return float(s[: -len(suf)]) * mult
            except ValueError:
                return None
    try:
        return float(s)
    except ValueError:
        return None
