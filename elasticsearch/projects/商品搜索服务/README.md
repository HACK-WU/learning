# 综合实战项目：商品搜索服务

> **一句话需求**：给电商网站做一个商品搜索后端——支持中文全文检索、分面筛选、相关性调优、深分页导出，并且能在**不停服**的前提下重建索引。

## 🎯 目标与非功能约束

| 类别 | 要求 | 落到哪里 |
|------|------|---------|
| **功能** | 中文全文检索 + 高亮 | `search/query.js` / `search/search.js` |
| **功能** | 品牌 / 分类 / 价格段分面统计 | `search/facets.js` |
| **功能** | 深分页导出（不受 10000 限制） | `search/paging.js` |
| **功能** | 不停服重建索引 | `ops/reindex-switch.js` |
| ① **错误处理** | bulk 部分失败逐项检查，可重试的退避重试、不可重试的进死信；写入绝不静默 | `sync/sync.js` |
| ② **性能** | 批量写入、筛选不打分、深分页走游标 | `sync/sync.js` / `search/query.js` / `search/paging.js` |
| ③ **可维护性** | 组件模板 + 索引模板 + 别名，配置全部外置 | `es/schema.js` / `config/index.js` |
| ④ **安全** | 应用账号最小权限（只读 + 集群监控），不拿 superuser 跑服务 | `ops/security.js` |
| ⑤ **成本** | 单分片 + 日志自动滚动与过期删除 | `es/schema.js` 的 ILM 策略 |

**一句话架构**：MySQL（本项目用 `sync/products.js` 模拟）是**原始账本**，ES 是它的**索引副本**——ES 全删了，重跑一次 `npm run sync` 就能完整重建。

## 🗺️ 覆盖知识点地图（跨 5 个阶段）

| 阶段 | 知识点 | 本项目用在哪 | 回指课时 |
|------|--------|-------------|---------|
| **1 动机** | 数据库为什么搞不定搜索 | 需求起点：`LIKE '%手机%'` 全表扫 + 中文分词弱 | [课 1](../../stages/1-为什么需要ES/lessons/lesson-01-为什么数据库搞不定搜索.md) |
| **1 动机** | ES 是索引副本不是原始账本 | `sync/products.js` 定位为可重建的数据源 | [课 2](../../stages/1-为什么需要ES/lessons/lesson-02-ES是谁凭什么.md) / [课 14](../../stages/5-生产与选型/lessons/lesson-14-该不该用ES.md) |
| **2 原理** | 分词与分析器（IK） | 索引 `ik_max_word` + 搜索 `ik_smart` | [课 4](../../stages/2-核心原理与上手/lessons/lesson-04-倒排索引的秘密.md) |
| **2 原理** | 映射设计（`scaled_float` / `keyword` / `date`） | `es/schema.js` 的 mappings | [课 5](../../stages/2-核心原理与上手/lessons/lesson-05-映射给数据定规矩.md) |
| **2 原理** | multi-fields | `title.std`（兜底召回）+ `title.raw`（整句精确） | [课 5](../../stages/2-核心原理与上手/lessons/lesson-05-映射给数据定规矩.md) |
| **2 原理** | `dynamic: strict` | 生产不让 ES 猜类型 | [课 5](../../stages/2-核心原理与上手/lessons/lesson-05-映射给数据定规矩.md) |
| **3 检索** | Query DSL 结构与 `filter` 不打分 | 打分条件进 `must`，筛选条件进 `filter` | [课 6](../../stages/3-查询与聚合/lessons/lesson-06-QueryDSL问问题的语言.md) |
| **3 检索** | BM25 + `function_score` 调优 | `--boost-sales` 按销量加权（`multiply` 只放大不颠覆） | [课 7](../../stages/3-查询与聚合/lessons/lesson-07-为什么这条排在前面.md) |
| **3 检索** | 高亮与 XSS 防护 | 用默认 `encoder`，不改成 `html` | [课 7](../../stages/3-查询与聚合/lessons/lesson-07-为什么这条排在前面.md) |
| **3 检索** | 聚合分面 + `post_filter` | 选了品牌后，品牌分面仍显示其他品牌的件数 | [课 8](../../stages/3-查询与聚合/lessons/lesson-08-聚合不做搜索做统计.md) |
| **3 检索** | 深分页 `search_after` | 导出全部商品，不受 10000 限制 | [课 7](../../stages/3-查询与聚合/lessons/lesson-07-为什么这条排在前面.md) / [课 12](../../stages/4-分布式与工程实践/lessons/lesson-12-接入真实项目.md) |
| **4 分布式** | 分片与副本设计 | 1 主 1 副（数据量小，单分片避免聚合误差与长尾） | [课 9](../../stages/4-分布式与工程实践/lessons/lesson-09-分片分布式的基石.md) / [课 10](../../stages/4-分布式与工程实践/lessons/lesson-10-集群健康与排障.md) |
| **4 分布式** | 主副本绝不同节点 | `ops/health.js` 逐片校验 | [课 9](../../stages/4-分布式与工程实践/lessons/lesson-09-分片分布式的基石.md) |
| **4 分布式** | bulk 幂等 + 部分失败分类处置 | 业务主键当 `_id`；`errors=true` 时遍历 `items` | [课 12](../../stages/4-分布式与工程实践/lessons/lesson-12-接入真实项目.md) |
| **4 分布式** | 索引模板 / 组件模板 / `priority` | `es/schema.js` 三层模板体系 | [课 15](../../stages/4-分布式与工程实践/lessons/lesson-15-索引管理与生命周期策略.md) |
| **4 分布式** | 别名原子切换 + `is_write_index` | 切换在一个 `_aliases` 请求里完成 | [课 15](../../stages/4-分布式与工程实践/lessons/lesson-15-索引管理与生命周期策略.md) |
| **4 分布式** | ILM + Data Stream | 搜索日志自动滚动 / 合段 / 90 天删除 | [课 13](../../stages/5-生产与选型/lessons/lesson-13-三大主战场.md) / [课 15](../../stages/4-分布式与工程实践/lessons/lesson-15-索引管理与生命周期策略.md) |
| **4 分布式** | reindex 是改结构的唯一途径 | v1 → v2 全链路 | [课 11](../../stages/4-分布式与工程实践/lessons/lesson-11-数据管道与备份.md) |
| **4 分布式** | 客户端连接池与版本协商 | 显式列三节点，请求均摊 | [课 12](../../stages/4-分布式与工程实践/lessons/lesson-12-接入真实项目.md) |
| **4 分布式** | 报错看 `root_cause` | 所有异常统一走 `es/client.js` 的 `rootCause()` | [课 12](../../stages/4-分布式与工程实践/lessons/lesson-12-接入真实项目.md) |
| **5 选型** | RBAC 最小权限 | 只读角色 + 应用账号，验证 401 / 403 边界 | [课 13](../../stages/5-生产与选型/lessons/lesson-13-三大主战场.md) |
| **5 选型** | 该不该用 ES | 本项目是"该用"的典型；`README` 末尾给了不该用的信号 | [课 14](../../stages/5-生产与选型/lessons/lesson-14-该不该用ES.md) |

**覆盖 5 / 5 个阶段、22 个知识点**，每个都能在上面的课时里找到出处。

## 🚀 运行方式

### 环境要求

| 项 | 值 | 备注 |
|----|-----|------|
| Node.js | v22.14.0 | 本机实测版本 |
| ES | 9.5.1 | 三节点集群 `l9-cluster`（9201/9202/9203），**需装 IK 9.5.1** |
| 客户端 | `@elastic/elasticsearch@9.5.1` | 版本只能往下看一个大版本 |
| 可选 | 9200 单节点集群（开了安全） | 用来跑 `npm run security` |

```bash
cd elasticsearch/projects/商品搜索服务/实现

npm install          # 只装一个依赖：@elastic/elasticsearch@9.5.1

npm run init         # ① 建模板 / 索引 / 别名 / ILM
npm run sync         # ② 同步 38 条商品（跑两遍，第二遍验证幂等）
npm run search       # ③ 中文检索 + 高亮
npm run facets       # ④ 分面统计
npm run pages        # ⑤ 深分页导出
npm run health       # ⑥ 巡检
npm run switch       # ⑦ 零停机重建索引 v1 → v2

npm run demo         # 一次跑完上面 7 步（推荐第一次用这个）
```

其他入口：

```bash
npm run sync:dirty                    # 看 bulk 部分失败怎么分类处置（故意注入 2 条脏数据）
node ops/reindex-switch.js --to=v1    # 回滚到 v1
npm run reset                         # 清理全部 cap_* 索引 / 数据流 / 模板 / ILM

# 在 9200（开了安全）上演示 RBAC —— 注意 Windows 与 Linux 写法不同：
# Windows PowerShell（本机）：
$env:ES_PROFILE="secure"; npm run security
# Linux / macOS / Git Bash：
ES_PROFILE=secure npm run security
```

> ⚠️ `ES_PROFILE=secure npm run security` 这种内联写法**在 Windows PowerShell 下不生效**
> （那是 shell 的语法，不是 npm 的），必须先 `$env:ES_PROFILE="secure"`。

### ⚠️ Windows 上的两个环境坑（本机实测）

1. **别把中文关键词写在命令行里**。PowerShell 5.1 会把 UTF-8 中文按 GBK 解析，
   `node search/search.js 苹果手机` 传到程序里变成 `鑻规灉鎓嬫`，查出来必然 0 条。
   脚本已内置示例查询，直接 `npm run search` 即可；要自定义请用 `--keyword-file=xxx.txt`（UTF-8）。
2. **别用管道截断输出**。`node demo.js | Select-Object -First 60` 会在取够行数后**直接杀掉进程**，
   导致后面的步骤根本没执行（本项目调试时踩过两次，表现为"别名还在 v1"）。
   要保存输出请重定向到文件：`node demo.js > demo.log 2>&1`。

## 📁 目录说明

```
实现/
├── config/index.js        连接档位、索引命名、批量与分页参数（配置外置）
├── es/
│   ├── client.js          客户端单例 + 连接池 + root_cause 提取 + 错误分类
│   ├── cli.js             入口判断工具（防止模块被 import 时执行 main）
│   ├── schema.js          组件模板 / 索引模板 / 索引 / 别名 / ILM / 数据流
│   └── logging.js         写搜索日志到数据流（演示 Data Stream + ILM）
├── sync/
│   ├── products.js        原始账本：38 条商品（确定性生成）+ 2 条脏数据
│   └── sync.js            bulk 幂等同步 + 部分失败分类处置 + 退避重试
├── search/
│   ├── query.js           Query DSL 构造（must 打分 / filter 筛选 / function_score）
│   ├── search.js          检索 CLI（含高亮、排序、写日志）
│   ├── facets.js          分面统计（post_filter + 桶/指标/管道聚合）
│   ├── paging.js          search_after 深分页 + from/size 撞墙对照
│   └── keywords.js        关键词输入（绕开 Windows 中文参数失真）
├── ops/
│   ├── reindex-switch.js  零停机重建索引：建 v2 → reindex → 对比 → 原子切换 → 可回滚
│   ├── health.js          巡检：健康 / 分片 / 段 / ILM / 别名
│   └── security.js        RBAC：只读角色 + 应用账号 + 401/403 边界验证
└── demo.js                一键跑通 7 步
```

## 📊 关键实测数字（本机 ES 9.5.1 三节点集群，2026-09-02）

| 环节 | 实测结果 |
|------|---------|
| 同步 | 38 条商品，分 2 批 bulk；第二遍重写后文档数仍为 38（`_id` 幂等成立） |
| 脏数据 | 40 条里 2 条失败，`errors=true` 但另外 38 条**已落库** |
| 死信 1 | `document_parsing_exception: failed to parse field [price] of type [scaled_float]... 'abc'` |
| 死信 2 | `strict_dynamic_mapping_exception: mapping set to strict, dynamic introduction of [color]... is not allowed` |
| 检索 | 「苹果手机」命中 19 条，top1 = 7.8949，高亮正常 |
| 分面 | 「手机」：苹果 5 / 华为 4 / 小米 4 件，均价 ¥7919 / ¥5299 / ¥3974 |
| 深分页 | 4 页共导出 38 条，排序单调性校验通过 |
| from/size | `from=9995,size=10` → `Result window is too large ... [10000] but was [10005]` |
| 重建索引 | v1 命中 23 → v2 命中 19；v1 独有的 4 条**全是配件**（碎片词「本」命中"本商品…"） |
| 巡检 | 集群 GREEN，`cap_products_v1` 主@node-2 副@node-3（主副本不同节点 ✅） |
| RBAC | 只读账号读成功；写入被拒 **403**（报错列出所需权限名）；错密码 **401** |

## 🚫 什么时候别这么设计

| 信号 | 说明 |
|------|------|
| 数据是**唯一数据源**、丢了重建不了 | 违反"ES 是索引副本"铁律，先补源头 |
| 需要**多文档事务** | ES 只有单文档乐观锁 |
| 数据量 < 百万级且只有简单查询 | PostgreSQL 全文检索就够，运维成本更低 |
| 需要**强一致读**（写完立刻查到） | 近实时，默认 1 秒延迟 |
| 日志不需要留存分析 | 那 Data Stream + ILM 这一层就是纯负担 |

---

**下一步**：[设计决策.md](设计决策.md)（5 个权衡点）｜[反例对照.md](反例对照.md)（能跑但很糟的版本）｜[验收清单.md](验收清单.md)（逐项自测）
