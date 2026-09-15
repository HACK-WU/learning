# PostgreSQL 系统学习 · 课程手册

> **一句话定位**：这是一份 PostgreSQL 全课程汇总手册，把 17 课、53 个知识点、结课项目和 Phase 5 三件套压缩到一个可导航的入口。
>
> 正文课件负责五幕叙事、原理推导和完整实验；本手册负责“我学过什么、遇到问题去哪、面对新需求怎么选、最后如何验收”。

**规模**：5 阶段 / 17 课 / 53 个知识点 + 结课综合实战项目
**版本基线**：PostgreSQL 17.11；命令和系统视图以 PostgreSQL 17.x 为准
**实操环境**：macOS arm64 + Docker；结课项目使用 postgres:17，一主一备
**导航**：[学习档案](00-学习档案.md) ｜ [课程目录](02-课程目录.md) ｜ [评审清单](00-评审清单.md) ｜ [官方文档路由](web-index/postgresql-org/index.md)

## 📖 怎么用这本手册

| 你的状态 | 推荐入口 |
|---|---|
| 第一次通读 | 从“学习目标”开始，按阶段顺序看每课的三句话和决策卡 |
| 想回忆某个概念 | 用下方“阶段总览”定位课程，再进入原文的知识点标题 |
| 线上出问题 | 直接去 [09-排障速查手册](09-排障速查手册.md)，按症状先止血 |
| 想理解事故为什么发生 | 去 [08-实战经验](08-实战经验.md)，看症状—根因—诊断—修复—预防 |
| 有新需求要做设计 | 去 [10-场景解法库](10-场景解法库.md)，比较至少三条路线 |
| 想跑一条完整链路 | 去 [结课项目 README](<projects/订单系统的 PG 生产化手册/README.md>) |
| 想核对事实 | 先看课件中的官方文档链接，再看 [PostgreSQL 官方 web-index](web-index/postgresql-org/index.md) |

> 手册中的数字和实验结论只引用课程已核查内容或结课项目实测。重新运行实验时，耗时、LSN、行数等环境相关数字可能变化；不变量、判断方法和失败边界才是要带走的东西。

## 一、学习目标

| 目标 | 可观察的完成标准 |
|---|---|
| 理解原理 | 能解释一行订单从建模、查询、索引、事务、并发到备份恢复的完整生命周期 |
| 动手实操 | 能用 psql、Docker 和课程脚本建立实验环境，读懂 SQL 输出和系统视图 |
| 生产落地 | 能配置备份、WAL、流复制、监控、权限和连接管理，并用演练证明它们工作 |
| 决策参考 | 能根据 RPO/RTO、并发、一致性、隔离和团队能力选择方案，而不是背参数 |

## 二、故事主线：一行订单的一生

| 章节 | 订单经历的事情 | 课程解决的问题 |
|---|---|---|
| 阶段 1 | 它被放进数据库，开始被查询 | SQL 怎么写对，PG 的层级和数据类型是什么 |
| 阶段 2 | 它和用户、商品、明细、树形关系连接起来 | 模型怎么表达关系，复杂查询怎么保持清楚 |
| 阶段 3 | 订单越来越多，列表页开始变慢 | 索引、计划、统计信息和 SQL 重写怎样协作 |
| 阶段 4 | 多个请求同时改它，库存和金额不能出错 | 事务、MVCC、锁、死锁和隔离级别怎样守住不变量 |
| 阶段 5 | 主机故障、误删、升级和越权都可能发生 | 备份恢复、复制高可用、监控性能、扩展安全怎样落地 |
| 结课项目 | 一套订单系统要能运行、验证、恢复和答辩 | 把知识点焊成生产化手册 |

![PostgreSQL 学习路径总览](assets/01-学习路径总览.svg)

看图：左侧是从 SQL 基础向数据建模、查询优化和并发控制逐层深入；右侧是把这些能力汇入备份、复制、监控和安全，最后落到订单系统生产化项目。

## 三、阶段总览

| 阶段 | 课程 | 知识点 | 这一阶段回答的问题 | 状态 |
|---|---:|---:|---|---|
| [1 · SQL 与关系基础](stages/1-SQL与关系基础/overview.md) | 1–3 | 9 | 怎样把数据放进去、查出来、算清楚 | ✅ |
| [2 · 数据建模与 SQL 进阶](stages/2-数据建模与SQL进阶/overview.md) | 4–7 | 12 | 怎样表达关系、抽象查询、做分组内计算 | ✅ |
| [3 · 索引与查询优化](stages/3-索引与查询优化/overview.md) | 8–10 | 9 | 慢在哪里，索引和计划如何证明 | ✅ |
| [4 · 事务/锁与并发](stages/4-事务锁与并发/overview.md) | 11–13 | 10 | 多请求如何不互相踩数据 | ✅ |
| [5 · 运维与生产化](stages/5-运维与生产化/overview.md) | 14–17 | 13 | 出故障时如何恢复、接管、观测和隔离 | ✅ |

课程路径不是“先学完语法再背运维命令”，而是逐步把同一行订单放进更真实的压力中：

1. 先让 SQL 表达业务。
2. 再让模型承受关联和变化。
3. 再让查询承受规模。
4. 再让事务承受并发。
5. 最后让系统承受故障、升级和不可信调用者。

# 四、阶段 1：SQL 与关系基础

> **阶段目标**：会连接 PG、建出可靠的表、写出列表查询和报表聚合。这里的核心不是语法数量，而是形成“数据结构—查询语义—结果验证”的闭环。

| 课 | 原文 | 知识点 |
|---|---|---|
| 课 1 | [认识 PostgreSQL](stages/1-SQL与关系基础/lessons/lesson-01-认识PostgreSQL.md) | 1.1 PG 是什么 · 1.2 安装与工具链 · 1.3 数据库与模式层级 |
| 课 2 | [表与数据类型](stages/1-SQL与关系基础/lessons/lesson-02-表与数据类型.md) | 2.1 常用数据类型 · 2.2 建表语法与约束 · 2.3 CRUD 基础 |
| 课 3 | [查询基础](stages/1-SQL与关系基础/lessons/lesson-03-查询基础.md) | 3.1 WHERE/ORDER BY/LIMIT · 3.2 JOIN 家族 · 3.3 聚合与 GROUP BY |

## 课 1：认识 PostgreSQL

**本课三句话**

1. PostgreSQL 的组织层级是 cluster → database → schema → table；schema 不是 MySQL 意义上的 database。
2. psql 是基础客户端，pgcli 是更友好的交互客户端；连接字符串比一串散落参数更适合排查。
3. search_path 决定未限定对象名去哪里找；生产 SQL 和迁移脚本应对关键对象使用 schema-qualified 名称。

| 你要会做 | 判断标准 |
|---|---|
| 起一个实验实例 | 版本、数据库名、端口和健康状态都能验证 |
| 解释层级 | 能说明跨 database 不是普通 JOIN，schema 才是数据库内部命名空间 |
| 排查“关系不存在” | 先看 current_database、current_schema、search_path，再看对象是否在其他 schema |

~~~bash
docker run --name pg17 -e POSTGRES_PASSWORD=<demo-only> \
  -e POSTGRES_DB=order_service -p 5433:5432 -d postgres:17
psql "postgresql://postgres:<demo-only>@localhost:5433/order_service"
~~~

**最容易错的地方**：把容器 localhost 当成宿主机；把 search_path 当成权限；把 cluster 当成 Kubernetes cluster；用 latest 代替明确版本。

官方入口：[安装与运行](https://www.postgresql.org/docs/17/tutorial-install.html) · [数据库集群](https://www.postgresql.org/docs/17/managing-resources.html) · [Schemas](https://www.postgresql.org/docs/17/ddl-schemas.html)

## 课 2：表与数据类型

**本课三句话**

1. 数据类型不是装饰：金额用 NUMERIC，时间先确认时区语义，标识列优先考虑 identity。
2. 约束是数据库里的业务护栏：PRIMARY KEY、FOREIGN KEY、UNIQUE、NOT NULL、CHECK 各自守不同不变量。
3. CRUD 的安全心法是 INSERT 看 RETURNING、SELECT 写显式列、UPDATE/DELETE 带可验证的 WHERE，危险清空才使用 TRUNCATE。

| 需求 | 默认起点 | 需要追问 |
|---|---|---|
| 金额 | NUMERIC(p,s) | 精度、舍入、币种是否分列 |
| 标识 | GENERATED ... AS IDENTITY | 是否需要跨系统导入、是否暴露给用户 |
| 状态 | text/varchar + CHECK 或 enum | 状态是否经常扩展、是否需跨服务共享 |
| 时间 | timestamptz 或明确的 timestamp 语义 | 谁产生时间、展示时区、排序边界 |

~~~sql
CREATE TABLE orders (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  tenant_id text NOT NULL,
  status text NOT NULL CHECK (status IN ('pending', 'paid', 'cancelled')),
  total_amount numeric(12, 2) NOT NULL CHECK (total_amount >= 0),
  created_at timestamptz NOT NULL DEFAULT now()
);
~~~

**最容易错的地方**：用浮点数存钱；以为 varchar(255) 自动带来性能优势；UPDATE 不写 WHERE；用应用代码代替数据库约束。

官方入口：[数据类型](https://www.postgresql.org/docs/17/datatype.html) · [约束](https://www.postgresql.org/docs/17/ddl-constraints.html) · [CREATE TABLE](https://www.postgresql.org/docs/17/sql-createtable.html)

## 课 3：查询基础

**本课三句话**

1. WHERE、ORDER BY、LIMIT 是列表查询三件套，但稳定分页还需要唯一的排序边界。
2. JOIN 决定“哪些行能拼起来”；INNER/LEFT/FULL 的差别是结果集合语义，不是写法偏好。
3. GROUP BY 把行压成组，窗口函数则保留行；聚合报表必须明确 NULL、重复行和时间边界。

| 场景 | 推荐模式 | 反例 |
|---|---|---|
| 首屏列表 | 唯一排序 + LIMIT | 只按 created_at 排，时间相同的行顺序漂移 |
| 深分页 | 键集分页 (created_at, id) < (...) | OFFSET 越深，扫描和稳定性代价越大 |
| 月报 | 明确半开区间 + GROUP BY | 用字符串拼日期或把非聚合列漏出 GROUP BY |
| 可选关联 | LEFT JOIN | 把过滤条件误放 WHERE，意外把 LEFT JOIN 变成 INNER JOIN |

~~~sql
SELECT id, status, total_amount, created_at
FROM orders
WHERE tenant_id = $1
  AND (created_at, id) < ($2, $3)
ORDER BY created_at DESC, id DESC
LIMIT 50;
~~~

**最容易错的地方**：把 NULL 当普通值排序；把 COUNT(*) 与 COUNT(column) 混用；用 OFFSET 解决无限深分页；以为 FULL JOIN 可以随意重排。

官方入口：[表表达式](https://www.postgresql.org/docs/17/queries-table-expressions.html) · [聚合](https://www.postgresql.org/docs/17/functions-aggregate.html) · [LIMIT/OFFSET](https://www.postgresql.org/docs/17/queries-limit.html)

**阶段 1 收束**：你已经能建立一张有约束的订单表，并从中读出列表和报表。下一阶段要解决的是：当订单不再是一张表，模型和查询如何保持可维护。

# 五、阶段 2：数据建模与 SQL 进阶

> **阶段目标**：把“几张表能查”提升为“关系说得清、复杂查询可演进、计算不丢语义”。

| 课 | 原文 | 知识点 |
|---|---|---|
| 课 4 | [关系建模](stages/2-数据建模与SQL进阶/lessons/lesson-04-关系建模.md) | 4.1 主键/外键/唯一约束 · 4.2 一对多/多对多/自引用 · 4.3 范式与反范式 |
| 课 5 | [视图与函数](stages/2-数据建模与SQL进阶/lessons/lesson-05-视图与函数.md) | 5.1 普通/可更新/物化视图 · 5.2 函数与存储过程 · 5.3 触发器 |
| 课 6 | [CTE 与子查询](stages/2-数据建模与SQL进阶/lessons/lesson-06-CTE与子查询.md) | 6.1 WITH · 6.2 递归 CTE · 6.3 相关子查询 vs JOIN |
| 课 7 | [窗口函数](stages/2-数据建模与SQL进阶/lessons/lesson-07-窗口函数.md) | 7.1 OVER/PARTITION BY/ORDER BY · 7.2 排名 · 7.3 聚合窗口与滑动 |

## 课 4：关系建模

**本课三句话**

1. 主键回答“这一行是谁”，外键回答“它指向谁”，唯一约束回答“哪些组合不能重复”。
2. 一对多、多对多、自引用是关系形态；表结构应先表达业务不变量，再考虑查询便利。
3. 3NF 是默认起点，反范式是有测量依据的交换；PG 不会自动为外键引用侧创建索引。

| 决策 | 默认选择 | 何时偏离 |
|---|---|---|
| 多对多 | 中间表 + 两侧外键 + 合适的唯一约束 | 读模型确实需要冗余且有一致性维护方案 |
| 树 | 递归 CTE | 读多写少、层级查询频繁且愿意维护 ltree 路径 |
| 灵活属性 | JSONB 作为扩展字段 | 核心查询、约束和统计字段仍应回到正式列 |
| 外键索引 | 按删除、更新、反向查找压力显式建立 | 不要因为“有外键”就假设已有索引 |

**最容易错的地方**：把反范式当性能万能药；只给主键建索引、不看引用侧；用 JSONB 逃避建模；自引用树没有终止和防环策略。

官方入口：[约束](https://www.postgresql.org/docs/17/ddl-constraints.html) · [索引与外键](https://www.postgresql.org/docs/17/ddl-constraints.html#DDL-CONSTRAINTS-FK) · [JSON 类型](https://www.postgresql.org/docs/17/datatype-json.html)

## 课 5：视图与函数

**本课三句话**

1. 普通视图是查询抽象，不自动加速；物化视图把结果存下来，换取刷新成本和陈旧窗口。
2. 函数适合表达可复用计算，过程适合需要事务控制的操作；两者的权限和调用语义要分开设计。
3. 触发器能把约束维护放到数据库，但也会隐藏副作用；NEW/OLD、递归和执行顺序必须可见。

| 需求 | 选择 | 代价 |
|---|---|---|
| 统一查询接口 | 普通视图 | 每次仍执行底层查询，不能把它当缓存 |
| 报表快照 | 物化视图 | 刷新和陈旧性；并发刷新需要满足额外条件 |
| 业务计算 | 函数 | 事务、权限和返回类型要明确 |
| 事务内控制流程 | 存储过程 | 调用方要理解事务边界 |
| 自动维护派生值 | 触发器 | 调试不直观，必须防止递归和隐式写放大 |

**最容易错的地方**：给普通视图“建索引”；以为物化视图自动更新；把触发器当作无成本的业务编排；让 SECURITY DEFINER 函数使用不安全的 search_path。

官方入口：[视图](https://www.postgresql.org/docs/17/tutorial-views.html) · [CREATE MATERIALIZED VIEW](https://www.postgresql.org/docs/17/sql-creatematerializedview.html) · [函数](https://www.postgresql.org/docs/17/xfunc.html) · [触发器](https://www.postgresql.org/docs/17/trigger-definition.html)

## 课 6：CTE 与子查询

**本课三句话**

1. CTE 先解决可读性和分层问题；PG 12+ 会在条件允许时内联，不能把 WITH 一律当优化屏障。
2. 递归 CTE 必须有终止条件，树和图的防环策略不同于普通层级查询。
3. 相关子查询、JOIN、EXISTS 常常可以互相转换，但 NULL 语义和执行计划必须用 EXPLAIN 验证。

| 问题 | 先问什么 |
|---|---|
| CTE 变慢 | 是否被多次引用、是否需要 MATERIALIZED、是否扩大了中间结果 |
| 递归不返回 | 是否有环、终止条件是否收敛、UNION ALL 是否无界 |
| NOT IN 结果为 0 | 子查询是否可能产生 NULL，是否应改成 NOT EXISTS |
| 子查询 vs JOIN | 语义是否等价，计划是否发生去关联或半连接转换 |

**最容易错的地方**：把 CTE 当永久优化屏障；递归图查询没有 visited 集合；看到 NOT IN 就机械改 NOT EXISTS 而不理解 NULL。

官方入口：[WITH 查询](https://www.postgresql.org/docs/17/queries-with.html) · [子查询](https://www.postgresql.org/docs/17/functions-subquery.html)

## 课 7：窗口函数

**本课三句话**

1. 窗口函数在保留原行的前提下做分区内计算，不等同于 GROUP BY。
2. row_number、rank、dense_rank 对并列值的处理不同；选择前先说清业务排名语义。
3. 默认窗口帧会让 SUM 变成累计、LAST_VALUE 可能只看到当前帧；窗口函数不能直接写进 WHERE。

| 需求 | 选择 |
|---|---|
| 分组内连续编号 | row_number |
| 并列占同名次且跳号 | rank |
| 并列占同名次但不跳号 | dense_rank |
| 分组内累计/滑动 | 明确 ROWS、RANGE 或 GROUPS |
| 每组最新一行 | 比较 DISTINCT ON 与 ROW_NUMBER 的语义和实测计划 |

**最容易错的地方**：以为窗口会合并行；把 SUM() OVER (ORDER BY x) 当总和；忘记显式窗口帧；在同一层 WHERE 引用尚未计算的窗口别名。

官方入口：[窗口函数](https://www.postgresql.org/docs/17/tutorial-window.html) · [窗口函数定义](https://www.postgresql.org/docs/17/functions-window.html)

**阶段 2 收束**：你现在能把关系、抽象、递归和分组内计算组合起来。下一阶段不再问“结果对不对”，而要问“为什么这次查询需要这么久”。

# 六、阶段 3：索引与查询优化

> **阶段目标**：建立证据驱动的性能方法：先定位瓶颈，再看计划和统计信息，最后用最小改动验证收益。

| 课 | 原文 | 知识点 |
|---|---|---|
| 课 8 | [索引原理](stages/3-索引与查询优化/lessons/lesson-08-索引原理.md) | 8.1 B-Tree · 8.2 Hash/GiST/GIN/BRIN · 8.3 组合索引 |
| 课 9 | [执行计划](stages/3-索引与查询优化/lessons/lesson-09-执行计划.md) | 9.1 EXPLAIN · 9.2 常见算子 · 9.3 统计信息与 ANALYZE |
| 课 10 | [慢查询优化实战](stages/3-索引与查询优化/lessons/lesson-10-慢查询优化实战.md) | 10.1 慢查询日志 · 10.2 索引陷阱 · 10.3 SQL 重写 |

## 课 8：索引原理

**本课三句话**

1. 索引是访问路径，不是“加了就快”；不同访问模式对应 B-Tree、Hash、GIN、GiST、BRIN 的不同取舍。
2. 组合索引的列顺序服务于等值、范围和排序；缺少最左列不等于完全失效，但代价可能很大。
3. INCLUDE、可见性地图和 Index Only Scan 共同决定能否少回表；索引越多，写入和维护成本越高。

| 现象 | 先检查 |
|---|---|
| 等值/范围查询 | B-Tree 列顺序与选择性 |
| 包含查询、全文、数组 | GIN/GiST 的操作符类和写入代价 |
| 按物理顺序追加的大表 | BRIN 与列值和页面的相关性 |
| 想覆盖 SELECT 列 | INCLUDE、可见性地图、Heap Fetches |
| 索引长期不用 | pg_stat_user_indexes、查询形状和删除风险 |

**最容易错的地方**：把 PG B-Tree 和其他数据库的聚簇索引混为一谈；以为 Index Only Scan 永远不回表；只看单次查询不算写放大。

官方入口：[索引总论](https://www.postgresql.org/docs/17/indexes.html) · [多列索引](https://www.postgresql.org/docs/17/indexes-multicolumn.html) · [索引类型](https://www.postgresql.org/docs/17/indexes-types.html)

## 课 9：执行计划

**本课三句话**

1. cost 是优化器的相对代价单位，不是毫秒；actual time、loops 和 buffers 才能把计划和真实运行联系起来。
2. Join 算子要看谁建 hash、谁被扫描、是否溢出；“cost 更低”不是脱离环境的速度保证。
3. 估算行数错误会把计划带偏；ANALYZE、统计目标和列相关性比盲目加索引更优先。

| 看什么 | 回答什么 |
|---|---|
| estimated rows vs actual rows | 优化器对数据分布的判断是否偏了 |
| loops × actual time | 节点总成本是否被平均时间掩盖 |
| Buffers | 慢在缓存命中、物理读还是临时文件 |
| Batches / temp written | Hash 或聚合是否溢出 work_mem |
| 计划前后对照 | 改动是否真的改变了瓶颈 |

~~~sql
EXPLAIN (ANALYZE, BUFFERS, VERBOSE)
SELECT id, status, total_amount
FROM orders
WHERE tenant_id = 'tenant-a'
ORDER BY created_at DESC, id DESC
LIMIT 50;
~~~

**最容易错的地方**：把 cost 当时间；只看最外层 actual time；把 Hash Join 机械解释为“小表建 hash”；统计信息过期却先加索引。

官方入口：[EXPLAIN](https://www.postgresql.org/docs/17/using-explain.html) · [优化器统计](https://www.postgresql.org/docs/17/planner-stats.html) · [ANALYZE](https://www.postgresql.org/docs/17/sql-analyze.html)

## 课 10：慢查询优化实战

**本课三句话**

1. 慢查询优化是工作流：确认症状 → 获取 SQL → 看等待与计划 → 提出最小改动 → 对照验证。
2. 函数、类型转换、LIKE、OR、否定条件和深分页是否伤害索引，不能靠口号判断，要看实际计划。
3. 大事务、锁等待、连接排队和坏计划都可能表现为“接口慢”，先区分等待与执行。

| 优化动作 | 必须先证明 |
|---|---|
| 加索引 | 查询谓词、排序、选择性和写入成本值得 |
| 建表达式索引 | 表达式稳定且满足 IMMUTABLE 要求 |
| 改写 OR | 两个分支真的可分离，且 UNION/Bitmap 代价更好 |
| IN 改 EXISTS | 语义和 NULL 行为一致，计划确实改善 |
| 深分页改键集 | 排序边界唯一且客户端能携带游标 |
| 调参数 | 已知瓶颈与参数作用域，不把会话参数当全局药方 |

**最容易错的地方**：把“有函数”直接等同“无索引”；把 IN/EXISTS 当固定快慢关系；直接调 random_page_cost/work_mem；不看 wait_event 就只看 EXPLAIN。

官方入口：[性能提示](https://www.postgresql.org/docs/17/performance-tips.html) · [运行时配置](https://www.postgresql.org/docs/17/runtime-config.html) · [pg_stat_statements](https://www.postgresql.org/docs/17/pgstatstatements.html)

**阶段 3 收束**：性能问题的答案不是“再加一点配置”，而是把访问路径、数据分布、等待状态和业务边界放在同一张证据表里。

# 七、阶段 4：事务、锁与并发

> **阶段目标**：把“看起来正确”的单请求代码，提升为并发下仍能守住不变量的数据库操作。

| 课 | 原文 | 知识点 |
|---|---|---|
| 课 11 | [事务与隔离级别](stages/4-事务锁与并发/lessons/lesson-11-事务与隔离级别.md) | 11.1 ACID · 11.2 四种隔离级别 · 11.3 脏读/不可重复读/幻读 |
| 课 12 | [MVCC 与并发控制](stages/4-事务锁与并发/lessons/lesson-12-MVCC与并发控制.md) | 12.1 MVCC · 12.2 可见性与死元组 · 12.3 autovacuum |
| 课 13 | [锁机制与死锁](stages/4-事务锁与并发/lessons/lesson-13-锁机制与死锁.md) | 13.1 表锁/行锁 · 13.2 显式锁/咨询锁 · 13.3 死锁排查 · 13.4 事务陷阱 |

## 课 11：事务与隔离级别

**本课三句话**

1. ACID 是业务不变量的基础：原子性、持久性、隔离性和一致性必须一起理解。
2. PG 接受四种隔离级别名称，但内部只有三种不同的行为；默认是 READ COMMITTED。
3. 丢失更新通常靠改写 UPDATE、行锁或乐观锁解决；SERIALIZABLE 发现冲突后会给出 40001，应用必须重试。

| 需求 | 起点 | 代价或补充 |
|---|---|---|
| 单行库存扣减 | READ COMMITTED + 条件 UPDATE | 用影响行数表达成功/失败，配幂等键 |
| 需要先读后改 | SELECT FOR UPDATE | 缩短事务，事务内不要调用外部服务 |
| 跨行不变量 | SERIALIZABLE | 处理 40001 重试，不等于自动修正业务 |
| 长时间只读报表 | SERIALIZABLE READ ONLY DEFERRABLE | 获取快照可能等待，换取更稳定的只读执行 |

**最容易错的地方**：认为隔离级别会自动解决所有业务竞态；把 SERIALIZABLE 当作“更强的锁”；忽略事务 abort 后必须回滚；误读 PG 对幻读的实现语义。

官方入口：[事务隔离](https://www.postgresql.org/docs/17/transaction-iso.html) · [事务管理](https://www.postgresql.org/docs/17/tutorial-transactions.html)

## 课 12：MVCC 与并发控制

**本课三句话**

1. UPDATE/DELETE 不是擦改原行，而是产生新的 tuple version；旧版本在仍被需要时不能立刻消失。
2. VACUUM 主要把空间标记为可复用，VACUUM FULL 才会重写表并回收文件空间，但锁和代价更大。
3. autovacuum 是后台清洁工，不是魔法；大表、长事务、冻结和统计信息都需要可观测。

| 现象 | 解释 |
|---|---|
| 死元组变多 | 更新/删除生成的旧版本尚未被清理 |
| 表膨胀 | 可复用空间、长事务或清理速度跟不上写入 |
| n_dead_tup 读到 0 | 可能是 autovacuum 已先清理，也可能是统计尚未刷新 |
| HOT 更新比例低 | 更新列、页面空间或索引依赖不满足 |
| XID 接近回卷 | 这是数据安全事件，不是普通性能调优 |

**最容易错的地方**：以为 DELETE 后磁盘立刻变小；以为 autovacuum 开着就无需监控；把 xmax 非零直接解释成“已删除”；在长事务期间做空间判断。

官方入口：[MVCC](https://www.postgresql.org/docs/17/mvcc.html) · [日常 VACUUM](https://www.postgresql.org/docs/17/routine-vacuuming.html) · [autovacuum](https://www.postgresql.org/docs/17/runtime-config-autovacuum.html)

## 课 13：锁机制与死锁

**本课三句话**

1. 表锁、行锁、咨询锁和谓词锁解决的层次不同；“加锁”不是一个单一动作。
2. 死锁的核心是等待环，正确排查要看阻塞链、持锁者、事务时间和业务调用路径。
3. 40P01、40001、55P03 分别对应不同失败语义；lock_timeout 不是死锁修复，咨询锁也不自动遵守事务边界。

| 现象 | 第一镜头 |
|---|---|
| 请求长时间不返回 | pg_stat_activity 的 state、wait_event_type、wait_event |
| UPDATE 卡住 | blocker、blocked、事务开始时间和业务操作 |
| 死锁日志 | SQLSTATE 40P01、锁顺序和重试策略 |
| 大批量任务拖慢全站 | 长事务、DDL、锁持有时间和连接池 |
| advisory lock 不释放 | 它是 session 级还是 transaction 级，持有连接是否复用 |

**最容易错的地方**：只看 pg_locks 不看 pg_blocking_pids；把行锁误当成普通表级锁；在事务内等待外部服务；终止会话前不记录回滚代价。

官方入口：[显式锁](https://www.postgresql.org/docs/17/explicit-locking.html) · [监控会话](https://www.postgresql.org/docs/17/monitoring-stats.html#MONITORING-PG-STAT-ACTIVITY)

**阶段 4 收束**：并发正确性首先是写法和不变量，其次才是隔离级别和锁参数。先把“谁能改、改什么、改失败如何重试”写清楚。

# 八、阶段 5：运维与生产化

> **阶段目标**：让数据库不只是“能用”，而是能恢复、能接管、能观测、能隔离、能升级。

| 课 | 原文 | 知识点 |
|---|---|---|
| 课 14 | [备份与恢复](stages/5-运维与生产化/lessons/lesson-14-备份与恢复.md) | 14.1 逻辑备份 · 14.2 物理备份 · 14.3 PITR |
| 课 15 | [复制与高可用](stages/5-运维与生产化/lessons/lesson-15-复制与高可用.md) | 15.1 流复制 · 15.2 切换与复制槽 · 15.3 HA 方案 |
| 课 16 | [监控与性能](stages/5-运维与生产化/lessons/lesson-16-监控与性能.md) | 16.1 指标 · 16.2 pg_stat_* · 16.3 监控工具 |
| 课 17 | [扩展与安全](stages/5-运维与生产化/lessons/lesson-17-扩展与安全.md) | 17.1 扩展 · 17.2 权限/RLS · 17.3 连接池 · 17.4 升级迁移 |

## 课 14：备份与恢复

**本课三句话**

1. 逻辑备份适合对象级恢复和迁移；角色、表空间等全局对象要单独考虑。
2. 物理 base backup 是数据目录级基线；连续 WAL 归档把它升级为可做 PITR 的恢复链。
3. “备份文件存在”不是验收标准；必须在隔离实例恢复，并用业务断言证明目标时间点正确。

| 目标 | 组合 |
|---|---|
| 单表/对象恢复 | custom 或 directory dump + globals + 依赖清单 |
| 整库快速恢复 | physical base backup + 校验和/manifest |
| 误删回到某时刻 | base backup + 连续 WAL + recovery target |
| 证明真的可用 | 临时实例恢复 + 角色登录 + 关键业务旅程 |

**最容易错的地方**：只备数据库不备 globals；只看 pg_dump 退出码；PITR 在原主库上做；archive_command 成功却没有真实归档；误把 recovery.signal 和 standby.signal 混用。

官方入口：[备份总论](https://www.postgresql.org/docs/17/backup.html) · [连续归档与 PITR](https://www.postgresql.org/docs/17/continuous-archiving.html) · [pg_dump](https://www.postgresql.org/docs/17/app-pgdump.html)

## 课 15：复制与高可用

**本课三句话**

1. 物理流复制传送 WAL 变化；主库发送端和备库接收端要分别监控，LSN 的 write/flush/replay 不是同一个延迟。
2. 复制槽解决下游不丢 WAL 的需要，却可能把主库磁盘撑满；slot 必须有 owner、容量阈值和清理条件。
3. HA = 复制 + 选主 + fencing + 接入路由；promote 不会自动阻止旧主继续写。

| 方案 | 适用边界 | 核心代价 |
|---|---|---|
| 异步复制 + 人工切换 | 小团队、RTO 可接受分钟级 | 复制延迟和人工误操作 |
| 同步复制 + 人工切换 | RPO 要求严格 | 备库失联会让提交等待 |
| HA 编排器 + fencing | RTO 严格、节点和路由复杂 | 仲裁、脑裂、演练和工具链成本 |

**最容易错的地方**：standby running 就认为复制健康；promote 后不做旧主隔离；同步复制可以替代 fencing；slot 没有下游 owner；把 PgBouncer/HAProxy 当成选主器。

官方入口：[热备与流复制](https://www.postgresql.org/docs/17/warm-standby.html) · [同步复制](https://www.postgresql.org/docs/17/warm-standby.html#SYNCHRONOUS-REPLICATION) · [高可用](https://www.postgresql.org/docs/17/high-availability.html)

## 课 16：监控与性能

**本课三句话**

1. 监控要覆盖连接、吞吐、缓存/IO、复制、锁/长事务、日志和磁盘，而不是只画 CPU。
2. pg_stat_activity 先判断会话在执行、排队还是等待；pg_stat_replication 和 pg_stat_wal_receiver 要从两端看。
3. PG 大版本会改变统计视图和字段；PG 17 的检查点统计拆分说明监控 SQL 也必须版本化测试。

| 问题 | 先查 |
|---|---|
| 请求慢 | pg_stat_activity、wait_event、锁链，再看 EXPLAIN |
| 主备落后 | sent/write/flush/replay LSN 和 WAL 保留 |
| 检查点异常 | pg_stat_checkpointer、pg_stat_bgwriter、pg_stat_wal |
| VACUUM 太慢 | pg_stat_progress_vacuum、阻塞、IO 和表规模 |
| 面板无数据 | exporter 日志、SQL 字段、权限、指标更新时间 |

**最容易错的地方**：把 No data 当作零；只看主库不看 standby；把系统视图当稳定业务表；用经验阈值代替故障证据；看到慢排行榜就断言是计划问题。

官方入口：[监控](https://www.postgresql.org/docs/17/monitoring.html) · [统计视图](https://www.postgresql.org/docs/17/monitoring-stats.html) · [进度报告](https://www.postgresql.org/docs/17/progress-reporting.html)

## 课 17：扩展与安全

**本课三句话**

1. 扩展是数据库内能力的安装和升级单元；trusted 只表示普通角色在特定条件下可安装，不等于所有扩展都无需管理员。
2. 权限是多道门：能否连接、能否使用 schema、能否访问表、RLS 能看哪几行；RLS 不能替代最小权限。
3. 连接池和升级路径都是生产设计的一部分；pg_upgrade 不转移统计信息，升级后仍需重建和回归。

| 需求 | 起点 |
|---|---|
| 常用能力 | 先查 contrib 和扩展版本兼容性 |
| 多租户隔离 | 最小权限 + RLS + USING/WITH CHECK + 真实角色负向测试 |
| 连接过多 | 应用池、PgBouncer 模式、max_connections 和会话状态一起评估 |
| 大版本升级 | pg_upgrade、逻辑复制、dump/restore 按停机和回滚要求选 |

**最容易错的地方**：只 GRANT 表不 GRANT schema USAGE；用超级用户证明 RLS；SECURITY DEFINER 不固定 search_path；事务池承载依赖 session 状态的应用；升级后跳过 ANALYZE。

官方入口：[权限](https://www.postgresql.org/docs/17/ddl-priv.html) · [RLS](https://www.postgresql.org/docs/17/ddl-rowsecurity.html) · [连接参数](https://www.postgresql.org/docs/17/runtime-config-connection.html) · [pg_upgrade](https://www.postgresql.org/docs/17/pgupgrade.html)

**阶段 5 收束**：生产化不是给数据库套一层“高可用”标签，而是为每个失败写出可观测证据、止血动作、修复路径、恢复验收和升级出口。

# 九、结课综合实战：订单系统的 PG 生产化手册

> 项目把 53 个知识点串成一条可运行链路：订单表从建模开始，经过查询和并发扣库存，进入租户隔离、主备复制、备份恢复和监控验收。

**项目入口**：[README](<projects/订单系统的 PG 生产化手册/README.md>) ｜ [设计决策](<projects/订单系统的 PG 生产化手册/设计决策.md>) ｜ [反例对照](<projects/订单系统的 PG 生产化手册/反例对照.md>) ｜ [验收清单](<projects/订单系统的 PG 生产化手册/验收清单.md>)

![订单系统 PG 生产化全链路](<projects/订单系统的 PG 生产化手册/assets/order-system-pg-production-flow.svg>)

看图：左侧是应用请求和数据库约束，中间是主库、备库、WAL 与备份链，右侧是监控、报表和恢复验收；项目刻意把“能写入”和“出故障后还能证明”放在同一张图里。

## 项目做什么

| 目标 | 项目实现 |
|---|---|
| 业务正确性 | 订单、明细、事件、库存和状态约束 |
| 并发安全 | 两个并发扣库存请求只有一个成功，最终库存为 0 |
| 租户隔离 | tenant-a 与 tenant-b 通过角色和 RLS 隔离 |
| 可恢复性 | custom dump、globals、physical base backup、WAL/PITR |
| 可观测性 | 复制状态、检查点、慢查询和报表 SQL |
| 可复现性 | Docker Compose、幂初始化脚本、验证脚本和清理边界 |

## 运行与验收

~~~bash
cd "postgresql/projects/订单系统的 PG 生产化手册/实现"
bash scripts/up.sh
bash scripts/verify.sh
bash scripts/concurrency.sh
bash scripts/backup.sh
bash scripts/restore-logical.sh
bash scripts/pitr.sh
~~~

本机已完成的基线结果：

- PostgreSQL 17.11 on aarch64；primary 15432，standby 15434。
- 复制检查为 1；初始 orders/items/events 均为 12002，幂等操作后 orders 为 12003。
- tenant-a / tenant-b 行数为 6002 / 6001。
- 并发结果 A=true、B=false、final_stock=0。
- 逻辑恢复订单行数为 12003；PITR 恢复点前 3 行，事故点之后的第 4 行不存在。
- 物理 base backup 为 11 MB；报表、监控和 Index Only Scan 验证通过。

> 这些是本次环境的实测证据，不是所有机器、数据量和云环境的性能承诺。重新运行时应以验收不变量为准。

## 项目五个关键决策

| 决策 | 推荐理解 |
|---|---|
| 逻辑备份还是 PITR | 不是二选一：对象级恢复和时间点恢复解决不同问题，组合更完整 |
| 异步、同步还是自动 HA | 先写 RPO/RTO，再决定是否用提交等待换数据保护，再补 fencing 和路由 |
| 如何扣库存 | 单行约束优先条件 UPDATE；复杂跨行不变量再评估行锁或 SERIALIZABLE |
| 应用过滤还是 RLS | 应用过滤便于业务体验，RLS 提供数据库兜底；强隔离再评估独立 schema/数据库 |
| pg_upgrade、逻辑复制还是 dump/restore | 停机窗口、扩展兼容、回滚路径和数据规模共同决定 |

## 项目反例

1. 只保存 dump，不保存 globals。
2. 只解压 base backup，不保留连续 WAL。
3. standby 容器 running 就宣布复制健康。
4. promote 后不隔离旧主。
5. 所有写入强制同步复制，却没有降级策略。
6. 看到慢就建索引，不判断锁等待。
7. 只测超级用户，不测真实租户角色。
8. 直接提高 max_connections 掩盖连接泄漏。
9. 监控查询不随 PG 大版本回归。

完整反例证据见 [反例对照.md](<projects/订单系统的 PG 生产化手册/反例对照.md>)；逐条验收见 [验收清单.md](<projects/订单系统的 PG 生产化手册/验收清单.md>)。

# 十、跨课方法论：以后遇到新问题怎么想

| 方法 | 具体动作 |
|---|---|
| 1. 先写不变量 | “库存不能小于 0”“租户不能看彼此数据”“恢复点之前的数据必须存在”先于 SQL |
| 2. 先看行为证据 | 会话状态、等待事件、LSN、rowcount、恢复结果比配置截图更可靠 |
| 3. 用最小机制守住目标 | 单行扣减先用条件 UPDATE，不为简单问题引入全局锁 |
| 4. 把读写分开判断 | 查询快不等于写入快；读副本不等于强一致；备库不等于接管 |
| 5. 把时间纳入设计 | 事务时间、归档时间、复制延迟、恢复目标和升级窗口都要写清 |
| 6. 先止血再优化 | 先隔离旧主、暂停危险清理、摘除陈旧读副本，再做根因分析 |
| 7. 所有能力都要演练 | backup 要 restore，replication 要 promote/fencing，RLS 要负向测试，监控要制造可控事件 |

## 五张决策速查表

### 1. 我要备份

| 先问 | 如果答案是 |
|---|---|
| 要单表恢复吗 | 保留逻辑 dump |
| 要指定时间点吗 | 配 base backup + 连续 WAL |
| 能接受多长停机 | 决定逻辑恢复、物理恢复或托管服务 |
| 最近恢复演练是什么时候 | 没有日期就先补演练，不先谈参数 |

### 2. 我要高可用

| 先问 | 如果答案是 |
|---|---|
| RPO 是 0 吗 | 评估同步复制及其写入等待 |
| 旧主如何停止写 | 没有 fencing 就不能宣布自动切换 |
| 谁修改写入口 | 把连接池、服务发现和负载均衡写入 runbook |
| 备库落后多少 | 以 replay LSN 和业务阈值验收 |

### 3. 接口变慢

| 先问 | 下一步 |
|---|---|
| 会话在等什么 | 看 wait_event_type 和 blocker |
| 估算行数准吗 | 比较 estimated rows / actual rows，必要时 ANALYZE |
| IO 还是 CPU | 看 buffers、pg_stat_io、系统资源 |
| 改动有效吗 | 同一 SQL、同一数据量、同一指标对照 |

### 4. 我要做多租户

| 先问 | 验收 |
|---|---|
| 信任边界在哪里 | 应用、数据库、独立数据库分别写清 |
| schema 是否可见 | 真实租户角色验证 USAGE |
| 行能否跨租户读 | tenant-a / tenant-b 双向负向查询 |
| 行能否跨租户写 | WITH CHECK、UPDATE tenant_id、函数入口一起测 |

### 5. 我要升级

| 先问 | 影响路线 |
|---|---|
| 停机窗口多长 | 短窗口偏 pg_upgrade/逻辑复制，长窗口可 dump/restore |
| 扩展兼容吗 | 先做扩展清单和目标版本验证 |
| 能否回滚 | 保留旧环境和备份，不把回滚理解成直接双主 |
| 统计信息怎么办 | pg_upgrade 后安排 ANALYZE 和计划回归 |

# 十一、Phase 5 三件套：从课件进入工作状态

| 文档 | 用途 | 入口 |
|---|---|---|
| 实战经验 | 学习态：把事故整理成可迁移经验 | [08-实战经验.md](08-实战经验.md) |
| 排障速查手册 | 使用态：按症状先止血，再分支定位 | [09-排障速查手册.md](09-排障速查手册.md) |
| 场景解法库 | 设计态：比较多条路线和真实代价 | [10-场景解法库.md](10-场景解法库.md) |

三份文档共享同一素材源，但职责不同：

1. 08 解释“为什么会坏”。
2. 09 解释“现在先做什么”。
3. 10 解释“下次设计怎么选”。

不要把 09 当原理课，也不要把 10 的候选方案当无条件标准答案。

# 十二、课程完成检查

- [x] 能建立 PostgreSQL 17.x 实验实例并用 psql 验证连接。
- [x] 能设计订单表、关系、约束、索引和稳定分页。
- [x] 能读 EXPLAIN、区分估算错误、执行慢和等待慢。
- [x] 能解释 MVCC、autovacuum、锁等待、死锁和 40001。
- [x] 能完成逻辑备份、物理备份和 PITR 恢复演练。
- [x] 能从主库和备库两侧判断复制是否健康。
- [x] 能把 fencing、路由和回切纳入 HA，而不是只执行 promote。
- [x] 能用 pg_stat_*、日志和计划建立可复核的监控诊断链。
- [x] 能用最小权限、RLS、函数安全和连接池边界保护生产系统。
- [x] 能完成结课项目的运行、设计答辩和验收清单。

## 🚀 接下来可以做什么

- **复盘**：复制“考我一下 PostgreSQL，重点考事务并发、PITR、HA、监控和 RLS”，进入 Phase 6 知识点对齐。
- **排障**：复制“我遇到了一个 PostgreSQL 生产故障：{症状}”，按 09 的先止血流程开始。
- **设计**：复制“我有一个 PostgreSQL 场景：{约束}，请按 10 的格式给出至少三条方案并比较代价”。
- **进阶**：告诉我想深入的方向，我会基于当前学习档案继续拆分专题。
