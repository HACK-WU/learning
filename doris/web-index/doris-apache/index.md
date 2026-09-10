# Doris Docs 4.x 网页索引

> 起始 URL：https://doris.apache.org/docs/4.x/
> 生成日期：2026-09-10 · 范围（scope）：/docs/4.x（课程基线 Doris 4.1.3；已排除 tags 页 6 条、admin-manual/open-api 74 条、sql-functions/scalar-functions 513 条逐函数字典页、ai-functions 19 条） · 条目数：984 · 一次性快照
> 只索引不镜像：需要正文时用 web_fetch 打开对应 URL（带锚点直达）
> 课程对齐：Doris 课程 4 目标（概念/实操/认证/决策），实操以 all-in-one 容器 4.1.3 为准

## 怎么用

1. 按「我要…」列定位条目（不确定先看下方分区索引）
2. 用 web_fetch 打开该条 URL 取细节
3. 本表是快照，链接大面积失效时整站重跑重建（脚本与中间地图见仓库 `temp/`：`build_doris-apache_web_index.py` / `web-index-doris-apache-map-{core,functions}.md`）
4. 查某个标量函数（scalar function）语法时，直接 web_fetch `https://doris.apache.org/docs/4.x/sql-manual/sql-functions/scalar-functions/<函数名>/`（该族 513 页未入表）

## 高频直达

| 我要… | 去哪一页 | 分区 |
|-------|----------|------|
| 理解 Doris 整体架构（FE/BE 角色） | [features-architecture](https://doris.apache.org/docs/4.x/features-architecture/) | overview |
| 理解三种数据模型（Duplicate/Aggregate/Unique） | [table-design/data-model](https://doris.apache.org/docs/4.x/table-design/data-model/) | table-design |
| 设计分区与分桶（查询性能的根源） | [table-design/data-partitioning](https://doris.apache.org/docs/4.x/table-design/data-partitioning/) | table-design |
| 数据导入方式怎么选 | [data-operate/import](https://doris.apache.org/docs/4.x/data-operate/import/) | data-operate-load |
| 用 Stream Load 流式导入 | [data-operate/import/stream-load](https://doris.apache.org/docs/4.x/data-operate/import/stream-load/) | data-operate-load |
| 查询调优实操（执行计划分析） | [query-acceleration/tuning](https://doris.apache.org/docs/4.x/query-acceleration/tuning/) | query-acceleration |
| 用物化视图加速 | [query-acceleration/materialized-view](https://doris.apache.org/docs/4.x/query-acceleration/materialized-view/) | query-acceleration |
| 查 INSERT 语句语法 | [sql-statements/data-modification/DML/INSERT](https://doris.apache.org/docs/4.x/sql-manual/sql-statements/data-modification/DML/INSERT/) | sql-dml |
| 查索引体系（前缀/倒排/BloomFilter） | [table-design/index](https://doris.apache.org/docs/4.x/table-design/index/) | table-design |
| 上生产前的运维检查（负载管理/配置） | [admin-manual/workload-management](https://doris.apache.org/docs/4.x/admin-manual/workload-management/) | admin-ops |

## 分区索引

| 分区 | 文件 | 条数 | 覆盖内容 |
|------|------|------|----------|
| overview | [topics/overview.md](./topics/overview.md) | 18 | 快速上手、架构、FAQ（人工归并散页） |
| install | [topics/install.md](./topics/install.md) | 32 | 各环境部署（含 K8s） |
| table-design | [topics/table-design.md](./topics/table-design.md) | 45 | 数据模型/分区分桶/索引/分层存储 |
| key-features | [topics/key-features.md](./topics/key-features.md) | 46 | 各关键能力页 |
| query-acceleration | [topics/query-acceleration.md](./topics/query-acceleration.md) | 48 | 调优/物化视图/优化器原理 |
| lakehouse | [topics/lakehouse.md](./topics/lakehouse.md) | 72 | 外部 Catalog/存储/文件格式 |
| data-operate-load | [topics/data-operate-load.md](./topics/data-operate-load.md) | 61 | 全部导入方式（Stream/Broker/Routine…） |
| data-operate-misc | [topics/data-operate-misc.md](./topics/data-operate-misc.md) | 22 | UPDATE/DELETE/EXPORT |
| connection-integration | [topics/connection-integration.md](./topics/connection-integration.md) | 33 | BI/驱动/集成工具 |
| ops-observe | [topics/ops-observe.md](./topics/ops-observe.md) | 33 | UDF/监控/存算分离（小分区归并） |
| admin-system | [topics/admin-system.md](./topics/admin-system.md) | 50 | 系统表逐张参考 |
| admin-ops | [topics/admin-ops.md](./topics/admin-ops.md) | 72 | 故障排查/负载管理/配置/扩缩容 |
| sql-basics | [topics/sql-basics.md](./topics/sql-basics.md) | 67 | SQL 基础元素 |
| sql-ddl | [topics/sql-ddl.md](./topics/sql-ddl.md) | 71 | 表与视图逐语句参考 |
| sql-dml | [topics/sql-dml.md](./topics/sql-dml.md) | 38 | INSERT/UPDATE/DELETE 与操作符 |
| sql-cluster | [topics/sql-cluster.md](./topics/sql-cluster.md) | 44 | 集群管理 SQL |
| sql-security | [topics/sql-security.md](./topics/sql-security.md) | 23 | 账号与安全 SQL |
| sql-misc | [topics/sql-misc.md](./topics/sql-misc.md) | 70 | 会话/统计/作业/Catalog 等 |
| functions-aggregate | [topics/functions-aggregate.md](./topics/functions-aggregate.md) | 78 | 聚合函数逐个参考 |
| functions-tables | [topics/functions-tables.md](./topics/functions-tables.md) | 46 | 表函数/表值函数 |
| functions-window | [topics/functions-window.md](./topics/functions-window.md) | 15 | 窗口函数/组合器 |
