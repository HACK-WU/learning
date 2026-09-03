# -*- coding: utf-8 -*-
"""seed.py —— 技术文档问答系统 · 种子数据 + 灌入

数据来自 SurrealDB 课程本身：12 篇"文档"对应 12 课，每篇切成若干块。
两个租户（acme / beta）各自持有部分文档，用于验证行级隔离。

为什么用自己的课程内容当语料：
- 检索结果对不对，你自己就能判断，不需要领域专家
- 主题分布天然分散（索引/权限/图/向量/实时...），混合检索的互补性看得出来
- 文档之间有真实引用关系（课 7 引用课 6，课 12 引用课 11），图扩展有意义
"""
import sys
import os

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from common import grams_field, embed  # noqa: E402

# (doc_id, tenant, category, title, [chunk texts...], [引用的 doc_id...])
CORPUS = [
    ("l01", "acme", "基础", "为什么需要 SurrealDB", [
        "一个应用里同时存在五种数据形状：关系型的结构化数据、文档型的嵌套数据、图型的关联数据、向量型的语义数据、时序型的流水数据。传统做法是每个形状上一个数据库，于是有了五个数据库要维护。",
        "形状分裂的代价不只是运维成本，更是数据一致性：跨库关联做不了事务，跨库查询只能搬数据。SurrealDB 的答案是多模型，一个引擎同时提供文档、图、关系与向量能力。",
        "多模型不等于什么都强。它的价值在于消除跨库搬运，代价是单项能力通常不如专用库。选型时要问的是痛点是跨形状还是单形状不够快。",
    ], []),
    ("l02", "acme", "基础", "安装与第一次查询", [
        "SurrealDB 是单二进制文件，启动命令指定存储后端。内存后端适合测试，重启即丢；RocksDB 后端持久化到磁盘，适合单机生产。",
        "三种客户端各有用途：REPL 适合随手试，HTTP 适合任何语言与脚本，Surrealist 是官方图形界面。生产应用一般用 HTTP 或官方 SDK。",
        "四级层级从上到下是命名空间、数据库、表、记录。命名空间是最高层的隔离边界，数据库是常用的业务边界。",
    ], ["l01"]),
    ("l03", "acme", "建模", "记录 ID 与数据建模", [
        "记录 ID 由表名和标识符两部分组成，形如 user:alice。它不只是主键，还可以直接参与查询与关联，不需要额外的外键列。",
        "Schema 有两种模式：SCHEMALESS 允许任意字段，灵活但无校验；SCHEMAFULL 强制字段类型，写入时校验。生产建议 SCHEMAFULL。",
        "REFERENCE 类型声明字段指向另一张表的记录，但要注意它只在 SCHEMAFULL 下校验存在性，且不保证级联。",
    ], ["l02"]),
    ("l04", "acme", "建模", "CRUD 与查询子句", [
        "五种写操作：CREATE 新建、SELECT 查询、UPDATE 更新、UPSERT 有则更新无则插入、DELETE 删除。UPDATE 一条不存在的记录不报错，只返回空数组。",
        "查询子句支持 WHERE 过滤、ORDER 排序、LIMIT 分页、SPLIT 拆分、GROUP 分组。语法与 SQL 相似但有 SurrealDB 自己的扩展。",
        "事务用 BEGIN TRANSACTION 与 COMMIT TRANSACTION 包裹，中间任意语句失败整个事务回滚。也可以用 THROW 主动触发回滚。",
    ], ["l03"]),
    ("l05", "acme", "图", "图：RELATE 与遍历", [
        "RELATE 语句创建边，边本身也是一条记录，可以有自己的字段。这让边能携带权重、时间等元信息。",
        "遍历语法用箭头：正向遍历用 ->，反向遍历用 <-。可以在一条查询里连续写多个箭头做多跳遍历。",
        "边的创建必须用 RELATE。在 TYPE RELATION 的表上用 INSERT INTO 不会报错但也不写入，是沉默失败。",
        "深层遍历的条数按扇出的幂次增长，扇出为 10 时第五跳就是十万条。控制深度是图查询的头号纪律。",
    ], ["l04"]),
    ("l06", "acme", "检索", "索引与全文检索", [
        "索引类型包括普通索引、唯一索引、复合索引与全文索引。建完索引必须用 EXPLAIN 确认查询真的走索引，看输出里是 IndexScan 还是 TableScan。",
        "全文索引从 3.0 起用 FULLTEXT ANALYZER 语法，旧的 SEARCH ANALYZER 已被移除，照抄老教程会直接报解析错误。",
        "BM25 打分通过 search::score 获取，编号与查询里的匹配表达式一一对应。高亮用 search::highlight。",
        "内置分析器不会切中文，直接建全文索引查中文一条都查不到。可行做法是在应用层把中文切成 bigram 存进冗余字段，再对这个字段建全文索引。",
    ], ["l04"]),
    ("l07", "acme", "检索", "向量与混合检索", [
        "向量字段用 array 类型配合 HNSW 索引，定义时要写对 DIMENSION，维数不匹配在插入时才报错。",
        "KNN 查询用尖括号算子写在 WHERE 里，形如 emb <|K,EF|> 查询向量。K 是要回几条，EF 是搜索时的候选规模，越大越准越慢。",
        "距离函数有两个：vector::distance::knn 只能配合 KNN 算子使用，单独调用会报找不到 KNN 算子；vector::similarity::cosine 是全表精算，不依赖索引但慢。",
        "混合检索用 search::rrf 把多路结果融合，签名是 search::rrf(结果数组, limit, k)。验证参数含义时候选数必须明显多于 limit，否则截断不触发会误判。",
    ], ["l06"]),
    ("l08", "acme", "实时", "实时：LIVE 与 EVENT", [
        "LIVE SELECT 建立实时订阅，数据变化时服务端主动推送。注意 HTTP 接口不支持 LIVE，要用 WebSocket 或 SDK。",
        "DEFINE EVENT 定义触发器，在数据变更时执行一段 SurrealQL。事件与主写入在同一个事务里，事件里 THROW 会把主写入一起回滚。",
        "订阅的 WHERE 过滤的是变更后的状态，不是跨越阈值才推送。价格从 80 涨到 85 照样会推送。",
        "扇出成本是实时能力的边界：订阅数乘以变更频率决定了推送量，必须提前估算。",
    ], ["l04"]),
    ("l09", "acme", "逻辑下推", "逻辑下推：函数、API 与视图", [
        "DEFINE FUNCTION 定义自定义函数，函数在调用者的权限下运行，不是创建者的权限。",
        "DEFINE API 用 SurrealQL 写 HTTP 端点。端点路径前缀是 /api/命名空间/数据库，端点体必须 RETURN 一个含 body 字段的对象，否则真实 HTTP 会返回 500。",
        "不要用 api::invoke 验证端点，它内部调用正常但真实 HTTP 可能 500，会把错误伪装成成功。",
        "COMPUTED 字段每次读取都会重算，不能用来维护更新时间这类需要持久化的值。VIEW 适合放固定查询逻辑。",
        "GraphQL 必须显式启用且带 AUTO 参数，只写 DEFINE CONFIG GRAPHQL 等于一张表都不暴露，且不报错。",
    ], ["l08"]),
    ("l10", "beta", "权限", "权限与多租户", [
        "DEFINE ACCESS 定义记录的访问方式，TYPE RECORD 让用户表里的记录可以登录。登录成功后拿到 token，后续请求带 Bearer。",
        "系统用户完全不受表级和字段级 PERMISSIONS 约束。用 root 跑应用，权限体系整体失效，这是多租户方案里最容易踩的坑。",
        "表级 PERMISSIONS 省略不写等于 NONE，字段级省略等于 FULL，两者默认值相反，最容易记反。",
        "即时吊销要把条件写成不等于 true，写成等于 false 在字段为 null 时会把存量用户全部误锁在外面。",
        "多租户隔离有两种方案：独立命名空间做强隔离，或同一库内按租户字段做行级过滤。后者省资源但依赖权限表达式正确。",
    ], ["l09"]),
    ("l11", "beta", "部署", "存储后端与部署", [
        "存储后端决定持久化与能力边界。RocksDB 支持持久化但不支持时间旅行，内存后端重启即丢。",
        "时间旅行查询可以读取历史时刻的数据，但需要后端支持版本化。删除也是状态的一种，删掉后查历史时刻返回的是截至该时刻的状态。",
        "部署模型有嵌入式、单节点、分布式与 Cloud 四种。嵌入式适合边缘与测试，分布式是生产高可用的选择。",
        "健康检查要小心：health 端点对不存在的服务也返回 200，不能作为依赖服务存活的判据。",
        "SurrealDB 暴露的监控指标数量很少，做可观测方案时不要指望它替代完整的监控体系。",
    ], ["l10"]),
    ("l12", "beta", "决策", "选型决策与收束", [
        "横向对比要在同一台机器上真跑，不要引用别人的跑分。跨系统跑分必须先测空操作基线，否则网络往返会淹没真实差异。",
        "性能对比的可信口径是服务端自报的 time 字段，客户端墙钟时间包含 HTTP 往返，噪声大于信号。",
        "适用边界有四个崩点：深图遍历的条数按扇出幂次爆炸、全表聚合近线性劣化、无索引大表过滤、逐行写入。逐行写与批量写的差距接近千倍。",
        "选 SurrealDB 的三个条件：痛点是跨形状而非单形状不够快、能接受单项慢一个常数级、数据量与图深度在崩点以内。",
        "写入性能是反转的：基于 LSM 的后端在批量灌数据上比传统关系库更快，因为顺序写占优。",
    ], ["l11"]),
]

USERS = [
    ("u_acme", "alice@acme.io", "acme", "Alice"),
    ("u_beta", "bob@beta.io", "beta", "Bob"),
]

DEFAULT_PASSWORD = "secret123"


def build_statements(include_users=True):
    """生成灌数据的 SurrealQL 语句列表。

    关键点（每条都对应一次实测，diag_insert.py 抓出）：

    1. 用 CREATE ... SET 逐条写，不用 INSERT INTO + JSON 数组。
       原因：JSON 里给 record 字段传字符串（"doc": "doc:l01"）**不会**被自动
       转换成 record，直接报 Expected `record<doc>` but found `'doc:l01'`。
       给 id 传字符串更隐蔽：不报错，但会生成嵌套 id chunk:`chunk:l01_0`，
       数据写进去了却按原 id 永远查不到。CREATE 用 SurrealQL 字面量，
       记录类型与 id 都是原生语法，不存在这两类问题。

    2. chunk 的 grams 字段由应用层生成（中文 bigram），不指望数据库切词。

    3. emb 由 embed() 生成 12 维主题向量，维数必须与 HNSW 索引的 DIMENSION 一致。

    4. 关系一律用 RELATE。在 TYPE RELATION 的表上用 INSERT INTO 不报错但也
       不写入（课 12 静默失败第十七次，本项目 cap-probe2 复现）。

    5. 灌数据走 root：表级 PERMISSIONS 的 create 是 NONE，记录用户写不进去；
       root 完全不受 PERMISSIONS 约束（课 10）。
    """
    stmts = []

    # 文档
    for did, tenant, cat, title, chunks, _refs in CORPUS:
        stmts.append(
            "CREATE doc:%s SET title=%s, tenant=%s, category=%s;"
            % (did, _q(title), _q(tenant), _q(cat)))

    # 切块：CREATE 逐条写，doc 字段用记录字面量 doc:xxx（不加引号）
    for did, tenant, _cat, _title, chunks, _refs in CORPUS:
        for i, text in enumerate(chunks):
            stmts.append(
                "CREATE chunk:%s_%d SET doc = doc:%s, tenant = %s, seq = %d, "
                "text = %s, grams = %s, emb = %s;"
                % (did, i, did, _q(tenant), i,
                   _q(text), _q(grams_field(text)),
                   _arr(embed(text))))

    # 倒排：term + hit
    # 先 UPSERT 全部 term（一批一次），再批量 RELATE 建边
    seen_terms = set()
    for did, _tenant, _cat, _title, chunks, _refs in CORPUS:
        for text in chunks:
            seen_terms.update(grams_field(text).split())
    for g in sorted(seen_terms):
        stmts.append("UPSERT term:[%s] SET w = %s;" % (_q(g), _q(g)))

    for did, _tenant, _cat, _title, chunks, _refs in CORPUS:
        for i, text in enumerate(chunks):
            cid = "chunk:%s_%d" % (did, i)
            for g in sorted(set(grams_field(text).split())):
                stmts.append("RELATE term:[%s]->hit->%s;" % (_q(g), cid))

    # 文档引用
    for did, _tenant, _cat, _title, _chunks, refs in CORPUS:
        for r in refs:
            stmts.append("RELATE doc:%s->refs->doc:%s SET kind = 'extends';" % (did, r))

    if include_users:
        for uid, email, tenant, name in USERS:
            stmts.append(
                "CREATE user:%s SET email=%s, password=crypto::argon2::generate(%s), "
                "tenant=%s, name=%s;"
                % (uid, _q(email), _q(DEFAULT_PASSWORD), _q(tenant), _q(name)))

    return stmts


def _q(s):
    """SurrealQL 字符串字面量：单引号 + 转义单引号与反斜杠。"""
    return "'" + str(s).replace("\\", "\\\\").replace("'", "\\'") + "'"


def _arr(nums):
    """SurrealQL 数组字面量：[0.1,0.2,...]，不留空格便于日志阅读。"""
    return "[" + ",".join(repr(float(n)) for n in nums) + "]"


if __name__ == "__main__":
    print("文档 %d 篇，切块 %d 条，用户 %d 个"
          % (len(CORPUS), sum(len(c[4]) for c in CORPUS), len(USERS)))
    st = build_statements()
    print("生成语句 %d 条" % len(st))
    print("示例 grams：", grams_field("索引能加速查询"))
    print("示例 emb 前 4 维：", [round(v, 3) for v in embed("索引能加速查询")[:4]])
