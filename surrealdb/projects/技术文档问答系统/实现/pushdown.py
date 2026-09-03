# -*- coding: utf-8 -*-
"""pushdown.py —— 逻辑下推：把检索逻辑放进数据库

为什么要下推（而不是应用里拼好几次查询）：
- 检索要 3 次往返（关键词路、向量路、融合），下推后 1 次
- 客户端不需要知道 bigram 与向量的实现细节，换语言不用重写
- 权限在服务端求值，客户端拿不到越权数据的机会都没有

三个产物：
    fn::qa_search()   检索函数（混合检索 + 可选租户过滤）
    DEFINE API /qa    HTTP 端点（直接对外提供问答检索）
    DEFINE TABLE ask_audit + EVENT   提问审计（实时能力的落地）

⚠️ 端点必须 RETURN { body: ... }。RETURN NONE 或裸 RETURN 'x' 走真实 HTTP
   一律 500（课 9 实测，本项目 cap-probe2 复现：/ask 返回 ok，说明只有
   { body: 'ok' } 这种形态可用）。
"""

# 检索函数：把 hybrid 的三段逻辑封装成一个函数
FN_SEARCH = """
DEFINE FUNCTION IF NOT EXISTS fn::qa_search($q: string, $k: number, $tenant: option<string>) {
  -- 关键词路：bigram 加权 BM25。
  -- ⚠️ 函数内无法调用应用层的 bigram 生成器，这里用查询串本身做全文匹配。
  --    因此本函数的关键词路匹配的是"查询串整体"，精度低于应用层生成的
  --    bigram 版本 —— 这是逻辑下推在本项目里的真实取舍，见 README 设计决策 3。
  LET $kw = (
    SELECT id, search::score(0) AS s
    FROM chunk
    WHERE grams @@ $q
    ORDER BY s DESC
    LIMIT $k * 2
  );

  -- 向量路：查询向量必须由调用方传入，函数内无法执行 embedding 模型
  LET $vec = (
    SELECT id, vector::distance::knn() AS d
    FROM chunk
    WHERE emb <|$k, 80|> $qv
    ORDER BY d ASC
    LIMIT $k * 2
  );

  RETURN search::rrf([$kw, $vec], $k, 2);
};
"""

# ⚠️ 这里踩过本项目最严重的一个 P0，实测过程见 diag_downpush.py ~ diag_fnloop4.py。
#
# 原写法：`WHERE grams @@ $q`（$q 是整个查询串"索引怎么加速查询"）
#   结果：**5 个查询全部返回 0 条**，而验收 D1 仍然通过 —— 因为 D1 只测
#   fn::qa_kw('索引', 3) 这种单 term 调用，恰好掩盖了多字查询失效。
#
# 根因链（四条，逐条实测排除）：
#   1. grams @@ 'a b' 是 **AND** 语义（diag_matchop.py：「索引 zzzzz」→ 0 条）
#      → 整个查询串做 tokenize 后要求一块里同时含全部 gram，几乎不可能
#   2. FOR 循环 + LET 累积 → 0 条（diag_fnloop.py P1）
#      → FOR 块内的 LET 不写回外层变量
#   3. 闭包 array::any($terms, |$t| grams @@ $t) → 0 条，且配 score 时报错
#      "no MATCHES clause found"（diag_fnloop2.py P3、diag_fnloop3.py P5）
#      → search::score() 只在**顶层 MATCHES 语法**下可用，闭包里不算
#   4. 只剩：**每个 term 一条子查询，各自带 score，外层合并后按 score 排序**
#      （diag_fnloop4.py P8）—— 可行，且排序结果与应用层完全一致
#
# 代价：函数签名固定为 3 个 term（不是可变数组）。这是 3.2.4 上唯一能
#      同时保住"召回"与"排序"的写法。见设计决策 5 的诚实标注。
FN_SEARCH_KW = """
DEFINE FUNCTION OVERWRITE fn::qa_kw($t1: string, $t2: string, $t3: string, $k: number) {
  LET $a = (SELECT id, text, doc, tenant, seq, search::score(0) AS s
            FROM chunk WHERE grams @@ $t1 ORDER BY s DESC LIMIT $k);
  LET $b = (SELECT id, text, doc, tenant, seq, search::score(0) AS s
            FROM chunk WHERE grams @@ $t2 ORDER BY s DESC LIMIT $k);
  LET $c = (SELECT id, text, doc, tenant, seq, search::score(0) AS s
            FROM chunk WHERE grams @@ $t3 ORDER BY s DESC LIMIT $k);

  -- 同一块可能被多个 term 命中，按 id 归并取最高分
  LET $all = array::concat($a, $b, $c);
  RETURN (SELECT id, text, doc, tenant, seq, math::max(s) AS s
          FROM $all GROUP BY id, text, doc, tenant, seq
          ORDER BY s DESC LIMIT $k);
};
"""

# 带租户过滤的检索函数（与 fn::qa_kw 同样的多 term 方案 + 租户过滤）
FN_SEARCH_SCOPED = """
DEFINE FUNCTION OVERWRITE fn::qa_scoped($t1: string, $t2: string, $t3: string, $k: number, $tenant: string) {
  LET $a = (SELECT id, text, doc, tenant, seq, search::score(0) AS s
            FROM chunk WHERE grams @@ $t1 AND tenant = $tenant
            ORDER BY s DESC LIMIT $k);
  LET $b = (SELECT id, text, doc, tenant, seq, search::score(0) AS s
            FROM chunk WHERE grams @@ $t2 AND tenant = $tenant
            ORDER BY s DESC LIMIT $k);
  LET $c = (SELECT id, text, doc, tenant, seq, search::score(0) AS s
            FROM chunk WHERE grams @@ $t3 AND tenant = $tenant
            ORDER BY s DESC LIMIT $k);

  LET $all = array::concat($a, $b, $c);
  RETURN (SELECT id, text, doc, tenant, seq, math::max(s) AS s
          FROM $all GROUP BY id, text, doc, tenant, seq
          ORDER BY s DESC LIMIT $k);
};
"""

# HTTP 端点：对外提供问答检索
# ⚠️⚠️ $request.body 在 3.2.4 上是**字节数组**，不是对象也不是字符串
#    （diag_body.py 决定性实验：encode 出来是 [123,34,113,...]，
#     $b.q 恒为 null，type::string($b) 得到的是 JSON 文本）。
#    取字段必须先 type::string() 转字符串，再 encoding::json::decode() 转对象。
#    直接写 $b.q 不报错，静默得到 NONE，再用 OR '' 兜底成空串 —— 查询 0 条，
#    端点照样返回 HTTP 200，是本项目第二十一次静默失败。
# ⚠️ 下面这条是**错误写法**，保留下来只作反例对照，不进 ALL 列表。
#    它单独定义 POST /qa，一旦被部署就会覆盖掉上面 API_QA_GET 里的
#    FOR GET, POST 合并定义，导致 GET /qa 直接 404 且不报错。
#    deploy_logic.py 与反例对照.md 会引用这个常量做"错误 vs 正确"的对照演示。
API_QA_POST_ONLY = """
DEFINE API OVERWRITE "/qa" FOR POST THEN {
  LET $raw = type::string($request.body);
  LET $body = encoding::json::decode($raw);
  LET $q = $body.q OR '';
  LET $k = $body.k OR 5;

  LET $hits = (
    SELECT id, text, doc, tenant, seq, search::score(0) AS s
    FROM chunk
    WHERE grams @@ $q
    ORDER BY s DESC
    LIMIT $k
  );

  RETURN {
    body: encoding::json::encode({
      q: $q,
      count: array::len($hits),
      hits: $hits
    })
  };
};
"""

# ⚠️ 三个坑，都是实测出来的：
#   坑 1：同一路径的 GET 与 POST 必须写成**一条** DEFINE（FOR GET, POST）。
#        分两条写时，后定义的会覆盖前面的 —— GET /qa 直接 404，且不报错
#        （deploy_logic.py 验证 1.5 复现：只 FOR POST 时 GET 返回 404）。
#   坑 2：IF 块里的 RETURN **不会终止**端点执行。写成
#        `IF $method = 'GET' { RETURN ... };` 后代码会继续往下走，
#        对 GET 的空 body 执行 encoding::json::decode('')，报
#        "Invalid JSON" → HTTP 500。必须用 IF / ELSE 分开两条路。
#   坑 3：$request.method 是**小写**（diag_method.py dump 实测：
#        GET 得到 'get'，POST 得到 'post'）。跟 'GET' 比较永远为假，
#        于是 GET 请求静默走进 POST 分支，返回 count=0 的空结果 ——
#        状态码还是 200，看起来"能用"但结果不对，是本项目第二十二次静默失败。
API_QA_GET = """
DEFINE API OVERWRITE "/qa" FOR GET, POST THEN {
  LET $method = $request.method;

  IF $method = 'get' {
    RETURN { body: 'use POST /qa with {"q": "your question", "k": 5}' };
  } ELSE {
    -- ⚠️ $request.body 在 3.2.4 上是字节数组，必须先 type::string() 再 decode
    LET $raw = type::string($request.body);
    LET $body = IF $raw = '' THEN {} ELSE encoding::json::decode($raw) END;
    LET $q = $body.q OR '';
    LET $k = $body.k OR 5;

    LET $hits = (
      SELECT id, text, doc, tenant, seq, search::score(0) AS s
      FROM chunk
      WHERE grams @@ $q
      ORDER BY s DESC
      LIMIT $k
    );

    RETURN {
      body: encoding::json::encode({
        q: $q,
        count: array::len($hits),
        hits: $hits
      })
    };
  };
};
"""

# 审计：每次经端点提问都留痕
AUDIT = """
DEFINE TABLE IF NOT EXISTS ask_audit SCHEMAFULL TYPE NORMAL
  PERMISSIONS FOR select WHERE tenant = $auth.tenant,
                FOR create NONE, FOR update NONE, FOR delete NONE;
DEFINE FIELD IF NOT EXISTS q      ON ask_audit TYPE string;
DEFINE FIELD IF NOT EXISTS tenant ON ask_audit TYPE string;
DEFINE FIELD IF NOT EXISTS who    ON ask_audit TYPE option<record<user>>;
DEFINE FIELD IF NOT EXISTS n      ON ask_audit TYPE number;
DEFINE FIELD IF NOT EXISTS at     ON ask_audit TYPE datetime DEFAULT time::now();
"""

# 带审计的提问端点
API_ASK = """
DEFINE API OVERWRITE "/ask" FOR POST THEN {
  LET $raw = type::string($request.body);
  LET $body = IF $raw = '' THEN {} ELSE encoding::json::decode($raw) END;
  LET $q = $body.q OR '';
  LET $k = $body.k OR 5;

  LET $hits = (
    SELECT id, text, doc, tenant, seq, search::score(0) AS s
    FROM chunk
    WHERE grams @@ $q
    ORDER BY s DESC
    LIMIT $k
  );

  -- 审计留痕：租户取自登录用户（$auth），不是客户端传的 —— 防伪造
  CREATE ask_audit SET q = $q, n = array::len($hits),
                       tenant = $auth.tenant, who = $auth.id;

  RETURN {
    body: encoding::json::encode({
      q: $q,
      tenant: $auth.tenant,
      count: array::len($hits),
      hits: $hits
    })
  };
};
"""

ALL = [FN_SEARCH_KW, FN_SEARCH_SCOPED, AUDIT, API_QA_GET, API_ASK]
