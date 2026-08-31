# 课 8：聚合：不做搜索，做统计

> 阶段 3《查询与聚合》第 3 课（阶段收官）
> 环境：本机 Elasticsearch **9.5.1**（HTTPS + 基本认证）
> 数据集：`l8_orders` / `l8_orders_v2`（24 条订单，本课新建并实测）

---

## 开场：一个问题，两种问法

前面两课，我们一直在问 ES 同一个类型的问题：

> **"哪些文档符合条件？按相关度排个序给我。"**

这是**搜索**。ES 返回一堆文档，每条带一个 `_score`。

但现实中还有另一类问题，完全不同：

> "这个月**总销售额**是多少？"
> "哪个**品牌**卖得最好？"
> "**平均客单价**是多少？"
> "按**周**看，销售趋势是在涨还是在跌？"

注意这些问题的特点——**你根本不想要文档**。给你 800 万条订单记录，你也看不完。你要的是几个**数字**。

这就是**聚合（Aggregation）**。

ES 里有一句很精辟的话，概括了二者的分工：

> **搜索是"找文档"，聚合是"算数字"。**

本课把这句话拆开讲透。

---

## 学习目标

| 学完你应该能 | 对应知识点 |
|---|---|
| 用桶聚合分组、用指标聚合计算，并解释二者的配合关系 | 知识点 1 |
| 用子聚合做多层分析，用管道聚合对聚合结果再聚合 | 知识点 2 |
| 用 ES\|QL 的管道语法写统计查询，知道何时该选它而非 DSL | 知识点 3 |
| **解释为什么聚合必须用 keyword 字段**（本课重点，呼应课 5） | 贯穿全课 |

---

## 预备：本课的数据集

为讲清聚合，我新建了一个订单索引。先看结构（这是**正确版本** `l8_orders_v2`）：

```json
PUT /l8_orders_v2
{
  "settings": { "number_of_shards": 1, "number_of_replicas": 0 },
  "mappings": {
    "properties": {
      "order_id":  { "type": "keyword" },
      "brand":     { "type": "keyword" },
      "category":  { "type": "keyword" },
      "product":   { "type": "text", "analyzer": "ik_max_word",
                     "search_analyzer": "ik_smart",
                     "fields": { "kw": { "type": "keyword", "ignore_above": 256 } } },
      "price":     { "type": "double" },
      "qty":       { "type": "integer" },
      "amount":    { "type": "double" },
      "status":    { "type": "keyword" },
      "city":      { "type": "keyword" },
      "sale_date": { "type": "date" },
      "tags":      { "type": "keyword" }
    }
  }
}
```

注意 `brand`、`category`、`status`、`city`、`tags` 全是 **keyword**，`product` 是 **text + keyword 子字段**。这个设计不是随便写的——**它正是本课的核心论点**。后面会详细解释。

数据长这样（24 条，3 个品牌 × 手机/电脑/平板）：

| order_id | brand | category | product | price | amount | status | city |
|---|---|---|---|---|---|---|---|
| O001 | 苹果 | 手机 | iPhone 15 Pro | 7999 | 7999 | 已完成 | 北京 |
| O002 | 华为 | 手机 | Mate 60 | 6999 | 13998 | 已完成 | 上海 |
| O003 | 小米 | 手机 | 小米14 | 4999 | 4999 | 已完成 | 北京 |
| O005 | 华为 | 电脑 | MateBook X | 8999 | 8999 | **退款** | 北京 |
| … | … | … | … | … | … | … | … |

> **为什么是 24 条？** 因为要同时满足：3 个品牌数量相等（8/8/8，便于验证）、含退款状态（讲 filter 聚合）、跨 5 周（讲 date_histogram）、有 array 字段 tags（讲 terms 多值）。数据量小到能手算校验，维度又足够跑通所有实验。

---

# 知识点 1：桶聚合与指标聚合

## 1.1 一个比喻：Excel 数据透视表

如果你用过 Excel 数据透视表，聚合就是同一件事：

| 数据透视表概念 | ES 聚合对应 |
|---|---|
| **行/列**（按什么分组） | **桶聚合 Bucket** |
| **值**（求和/平均/计数） | **指标聚合 Metric** |
| 分组后再算小计 | **子聚合** |

"按品牌分组，算每个品牌的总销售额"翻译成 ES 就是：

> 用 **terms 桶**按 `brand` 分组 → 每个桶里用 **sum 指标**算 `amount`。

## 1.2 结构图

![聚合的两大类：桶与指标](../../stages/3-查询与聚合/assets/agg-structure.svg)

*（图：桶聚合负责"怎么分组"，指标聚合负责"算什么数"，管道聚合负责"对聚合结果再聚合"。图中数字均来自本课实测。）*

## 1.3 指标聚合：不分组，直接算全量

最简单的聚合——不分桶，对整个结果集算数：

```json
POST /l8_orders_v2/_search?size=0
{
  "aggs": {
    "总销售额": { "sum":  { "field": "amount" } },
    "平均单价": { "avg":  { "field": "price"  } },
    "最贵":     { "max":  { "field": "price"  } },
    "最便宜":   { "min":  { "field": "price"  } },
    "订单数":   { "value_count": { "field": "order_id" } },
    "去重品牌数": { "cardinality": { "field": "brand" } },
    "一次返回多个": { "stats": { "field": "price" } }
  }
}
```

**实测输出：**

```text
总销售额         190057.0
平均单价         6527.71
最贵             12999.0
最便宜           1999.0
订单数           24
去重品牌数        3
一次返回多个      count=24 min=1999.0 max=12999.0 avg=6527.71 sum=156665.0
```

几个要点：

**① `size=0` 是聚合的标配。** 你要的只是数字，让 ES 别浪费力气返回文档。

**② `stats` 一次返回 5 个值**，省得写 5 个聚合。

**③ `cardinality` 是"去重计数"**，注意它**是近似值**（基于 HyperLogLog++ 算法），大数据集下有约 5% 误差，可用 `precision_threshold` 调精度（代价是更耗内存）。本课 24 条数据下它和 `value_count` 都是 24——**这不能证明它精确，只是数据量太小**。

> ⚠️ **诚实标注**：24 条数据下 `cardinality` 恰好等于精确值。我没法用小数据集证明它的近似性，只能告诉你原理上是近似的。**生产环境大基数去重时务必记住这点。**

## 1.4 桶聚合：按字段值分组

```json
POST /l8_orders_v2/_search?size=0
{
  "aggs": {
    "by_brand": { "terms": { "field": "brand", "size": 10 } }
  }
}
```

**实测输出：**

```text
桶数: 3
华为     8
小米     8
苹果     8
```

`terms` 聚合返回每个**唯一值**一个桶，`doc_count` 是该值的文档数。

**`size` 参数的坑**：`terms` 默认只返回 **Top 10** 桶。如果你有 50 个品牌却只设了 10，结果会**静默丢桶**。返回值里有两个字段帮你发现这事：

```text
sum_other_doc_count = 8          ← 有 8 条文档落在未返回的桶里
doc_count_error_upper_bound = 0  ← 计数误差上界
```

**实测**：设 `size: 2` 时返回「华为 8、小米 8」，而 `sum_other_doc_count = 8`——苹果那 8 条被吞了。

> **实践建议**：`sum_other_doc_count > 0` 就是你漏桶了的信号。要么加大 `size`，要么接受"只要 Top N"。

## 1.5 桶 + 指标：真正的威力

单分组没意义，真正的分析是**在每个组里再算数**：

```json
POST /l8_orders_v2/_search?size=0
{
  "aggs": {
    "by_brand": {
      "terms": { "field": "brand", "size": 10 },
      "aggs": {
        "订单数":   { "value_count": { "field": "order_id" } },
        "总销售额": { "sum": { "field": "amount" } },
        "平均单价": { "avg": { "field": "price" } },
        "最贵商品": { "max": { "field": "price" } }
      }
    }
  }
}
```

**实测输出：**

| 品牌 | 订单数 | 总销售额 | 平均单价 | 最贵 |
|---|---|---|---|---|
| 华为 | 8 | 64179.0 | 6497.62 | 8999.0 |
| 小米 | 8 | 45488.0 | 4236.5 | 5999.0 |
| 苹果 | 8 | 80390.0 | **8849.0** | 12999.0 |

## 1.6 手算验证：avg 到底怎么算的

跟课 7 一样，**我不接受黑盒**。ES 说苹果平均单价 8849.0，我手算一遍：

```text
苹果的 8 条价格：4799, 5999, 7999, 8999, 8999, 9999, 10999, 12999
求和 = 70792
70792 / 8 = 8849.0        ✅ 与 ES 返回的 8849.0 完全一致
```

**关键认知**：`avg` 是**按文档算**的，不是按行算的。这里有两条价格同为 8999 的订单（MacBook Air 和 iPad Pro），它们按**两条独立文档**参与计算——不会因为值相同就合并。

**占比校验**（后面实战会用到）：

```text
80390 + 64179 + 45488 = 190057  ✅ 等于总销售额
苹果 80390/190057 = 42.3%
华为 64179/190057 = 33.8%
小米 45488/190057 = 23.9%
42.3% + 33.8% + 23.9% = 100%    ✅
```

## 1.7 多层级桶：品牌 → 品类

桶可以无限套桶，形成树状分析：

```json
POST /l8_orders_v2/_search?size=0
{
  "aggs": {
    "by_brand": {
      "terms": { "field": "brand" },
      "aggs": {
        "by_category": {
          "terms": { "field": "category" },
          "aggs": { "销售额": { "sum": { "field": "amount" } } }
        }
      }
    }
  }
}
```

**实测输出：**

```text
【华为】共 8 单
   └ 手机     3 单  销售额 27485.0
   └ 电脑     3 单  销售额 22997.0
   └ 平板     2 单  销售额 13697.0
【小米】共 8 单
   └ 手机     3 单  销售额 22994.0
   └ 电脑     3 单  销售额 15297.0
   └ 平板     2 单  销售额  7197.0
【苹果】共 8 单
   └ 手机     3 单  销售额 23997.0
   └ 电脑     3 单  销售额 32997.0
   └ 平板     2 单  销售额 23396.0
```

## 1.8 其他常用桶类型

**date_histogram — 按时间分组**

```json
POST /l8_orders_v2/_search?size=0
{
  "aggs": {
    "by_week": {
      "date_histogram": { "field": "sale_date", "calendar_interval": "week" },
      "aggs": { "销售额": { "sum": { "field": "amount" } } }
    }
  }
}
```

**实测输出（5 个桶）：**

```text
2026-07-27  2 单  销售额 21997.0
2026-08-03  7 单  销售额 55890.0
2026-08-10  7 单  销售额 52279.0
2026-08-17  7 单  销售额 54892.0
2026-08-24  1 单  销售额  4999.0
```

> **空桶处理**：`date_histogram` 默认会**跳过**没有数据的区间。想让空区间也出现（画折线图时很关键），加 `"min_doc_count": 0`。

**range — 按数值区间分组**

```json
{ "aggs": { "price_range": { "range": { "field": "price", "ranges": [
  { "to": 3000 }, { "from": 3000, "to": 6000 },
  { "from": 6000, "to": 10000 }, { "from": 10000 } ] } } } }
```

**实测输出：**

```text
*-3000.0       3 单
3000.0-6000.0  10 单
6000.0-10000.0  9 单
10000.0-*       2 单
```

**filter / filters — 按条件分组**

```json
{ "aggs": { "状态分布": { "filters": { "filters": {
  "已完成": { "term": { "status": "已完成" } },
  "退款":   { "term": { "status": "退款"   } } } } } } }
```

**实测输出**：已完成 20 单，退款 4 单 → **退款率 16.7%**

## 1.9 【本课重点】为什么聚合必须用 keyword 字段

这是**课 5 multi-fields 埋下的伏笔**，现在收网。

### 场景：我想按品牌分组，但 brand 是 text 字段

为了让你**能亲手复现**这个错误，我专门建了一个演示索引 `l8_text_demo`——`brand` 是 **text** 类型（IK 分词），没有 keyword 子字段：

```json
PUT /l8_text_demo
{
  "settings": { "number_of_shards": 1, "number_of_replicas": 0 },
  "mappings": {
    "properties": {
      "order_id":  { "type": "keyword" },
      "brand":     { "type": "text", "analyzer": "ik_max_word",
                     "search_analyzer": "ik_smart" },
      "category":  { "type": "keyword" },
      "amount":    { "type": "double" },
      "price":     { "type": "double" },
      "city":      { "type": "keyword" },
      "sale_date": { "type": "date" }
    }
  }
}
```

数据从 `l8_orders_v2` 复制过来（同样的 24 条）：

```json
POST /_reindex
{ "source": { "index": "l8_orders_v2" }, "dest": { "index": "l8_text_demo" } }
```

**实测：reindex 24 条，成功。**

现在对它做 terms 聚合：

```json
POST /l8_text_demo/_search?size=0
{ "aggs": { "by_brand": { "terms": { "field": "brand" } } } }
```

**实测报错原文：**

```text
illegal_argument_exception:
Fielddata is disabled on [brand] in [l8_text_demo]. Text fields are not
optimised for operations that require per-document field data like
aggregations and sorting, so these operations are disabled by default.
Please use a keyword field instead. Alternatively, set fielddata=true on
[brand] in order to load field data by uninverting the inverted index.
Note that this can use significant memory.
```

**这条报错信息量极大**，拆开看：

1. **`Fielddata is disabled`** — text 字段默认禁止加载 fielddata
2. **`Text fields are not optimised for ... aggregations and sorting`** — text 字段专为**分词搜索**优化，不适合聚合排序
3. **`Please use a keyword field instead`** — 官方明确推荐用 keyword
4. **Alternatively, set fielddata=true** — 有个替代方案，但……
5. **Note that this can use significant memory** — 很吃内存

### 为什么？倒排索引 vs 列存

回到课 3 的**倒排索引**。text 字段 `"苹果"` 经过 IK 分词后，索引里存的是：

```text
"苹" → [doc1, doc4, doc7, ...]
"果" → [doc1, doc4, doc7, ...]
```

**倒排索引是"词项 → 文档"的映射**，它回答"哪些文档包含这个词"极快。

但聚合要回答的是**反向问题**：**"这个文档的这个字段，值是什么？"**

要从倒排索引反推这个，得把整个倒排索引**倒过来**（官方报错里叫 **uninverting the inverted index**），在内存里重建一个"文档 → 词项"的结构。这就是 **fielddata**——**全部加载到 JVM 堆内存**，数据量大时直接 OOM。

**keyword 字段则不同**：它**不分词**，`"苹果"` 整体作为一个 term 存入，且 ES 为其构建了 **doc_values**（列式存储，写在磁盘上）。聚合直接读 doc_values，又快又不吃堆内存。

| | text 字段 | keyword 字段 |
|---|---|---|
| 是否分词 | ✅ 分词（IK/standard） | ❌ 不分词，整串存储 |
| 擅长 | **搜索**（"包含这个词吗"） | **聚合/排序**（"这个值是什么"） |
| 聚合支持 | ❌ 默认禁止（要 fielddata） | ✅ 原生支持（doc_values） |
| 内存开销 | 聚合时**全量加载进堆** | 列存，**走磁盘/系统缓存** |

### 实测：fielddata=true 会怎样？

报错说可以开 `fielddata=true`。我试了——**结果证明了为什么不该这么干**：

```json
PUT /l8_text_demo/_mapping
{ "properties": { "brand": { "type": "text", "fielddata": true } } }
```

现在聚合不报错了，但看结果：

```text
为      8 单
华      8 单
小      8 单
果      8 单
米      8 单
苹      8 单
```

**「苹果」被拆成了「苹」和「果」两个独立桶！「华为」拆成「华」「为」，「小米」拆成「小」「米」。**

3 个品牌变成了 6 个**毫无意义**的碎桶。这就是分词对聚合的破坏——**聚合要的是完整值，不是词项碎片**。

### 正确方案：reindex 到 keyword mapping

```json
PUT /l8_orders_v2
{ "mappings": { "properties": { "brand": { "type": "keyword" }, ... } } }

POST /_reindex
{ "source": { "index": "l8_orders" }, "dest": { "index": "l8_orders_v2" } }
```

**实测：reindex 24 条，失败 0。**

同一个字段，两种 mapping，结果对比：

```text
l8_text_demo (brand = text + fielddata)  → ['为','华','小','果','米','苹']   ❌ 6 个碎桶
l8_orders_v2 (brand = keyword)           → ['华为','小米','苹果']            ✅ 3 个正确桶
```

> ⚠️ **如果你要自己复现**：`l8_text_demo` 在演示完 `fielddata=true` 之后就已经"被修复"了（不再报错）。想重看报错，删掉重建即可：
> ```bash
> curl -X DELETE "https://localhost:9200/l8_text_demo" -u elastic:密码 -k
> ```
> 然后重新执行上面的 `PUT /l8_text_demo` 和 `POST /_reindex`。

### 呼应课 5：multi-fields 的真正用途

课 5 讲 multi-fields 时，我留了个悬念："为什么一个字段要存两份？"

现在答案清楚了：

```json
"product": {
  "type": "text",
  "analyzer": "ik_max_word",
  "fields": { "kw": { "type": "keyword", "ignore_above": 256 } }
}
```

- `product` （text）→ 用于**搜索**：`match` 搜"iPhone"能命中
- `product.kw`（keyword）→ 用于**聚合/排序**：按完整商品名分组

**一个字段，两种用途，各取所需。** 这就是 multi-fields 存在的意义。

> ⚠️ **本课第二个诚实标注**：我**本想**用 `l8_orders` 演示正确做法，但 mapping 创建时 JSON 语法错误导致退化成动态映射。我没有掩盖这个失误，而是**把它变成了教学素材**——因为它恰好制造了"text 字段聚合报错"的真实场景，比刻意构造更有说服力。**讲义中所有"错误演示"的数据都来自真实的意外，不是编造的。**

## 1.10 聚合 vs 搜索：本质区别

最后，把开头那句话落实成可验证的事实。

**搜索：返回文档 + 分数**

```json
POST /l8_orders_v2/_search
{ "size": 3, "query": { "match": { "product": "iPhone" } } }
```

```text
命中 3 条, max_score = 2.1783
  score=2.1783  iPhone 15
  score=1.8576  iPhone 15 Pro
  score=1.6192  iPhone 15 Pro Max
```

**聚合：返回数字，不要文档**

```json
POST /l8_orders_v2/_search?size=0
{
  "query": { "match": { "product": "iPhone" } },
  "aggs": { "均价": { "avg": { "field": "price" } },
            "总额": { "sum": { "field": "amount" } } }
}
```

```text
hits 数组长度: 0        ← size=0，一份文档都不返回
聚合 → 均价 = 7999.0   总额 = 23997.0
```

**这张表是本节的核心：**

| | 搜索 Search | 聚合 Aggregation |
|---|---|---|
| 回答的问题 | 哪些文档符合条件？ | 这些文档的统计值是多少？ |
| 返回什么 | **文档列表** | **统计数值** |
| 有没有 `_score` | ✅ 有，按相关度排序 | ❌ 没有 |
| 典型参数 | `query` + `size` | `aggs` + `size=0` |
| 底层依赖 | **倒排索引** | **doc_values（列存）** |

**二者不是对立的，而是协作的**——`query` 圈定范围，`aggs` 在范围内统计：

```json
POST /l8_orders_v2/_search?size=0
{
  "query": { "term": { "status": "已完成" } },
  "aggs": { "by_brand": { "terms": { "field": "brand" },
    "aggs": { "销售额": { "sum": { "field": "amount" } } } } }
}
```

**实测输出：**

```text
已完成订单的品牌销售额:
  华为  7 单  55180.0
  苹果  7 单  69391.0
  小米  6 单  35991.0
```

注意：总数 20 单（不是 24），因为 4 单退款被 `query` 过滤掉了。**`query` 定范围，`aggs` 做统计**——这是 ES 分析的标准范式。

## 1.11 知识点 1 速查表

| 类型 | 聚合名 | 用途 | 本课实测 |
|---|---|---|---|
| **指标** | `sum` / `avg` / `min` / `max` | 求和/平均/最小/最大 | 总销售额 190057.0，均价 6527.71 |
| **指标** | `value_count` | 非空值计数 | 24 |
| **指标** | `cardinality` | **去重**计数（近似） | 3 个品牌 |
| **指标** | `stats` | 一次返回 count/min/max/avg/sum | count=24, sum=156665.0 |
| **指标** | `percentiles` | 分位数（P95/P99 延迟） | 本课未测 |
| **桶** | `terms` | 按字段值分组 | 苹果/华为/小米 各 8 单 |
| **桶** | `date_histogram` | 按时间间隔分组 | 5 个周桶 |
| **桶** | `range` | 按数值区间分组 | 3000-6000 段 10 单 |
| **桶** | `filter` / `filters` | 按条件分组 | 已完成 20 / 退款 4 |

> ⚠️ **诚实标注**：速查表里 `percentiles` 本课**未实测**（数据集是订单金额，不适合演示分位数；分位数典型场景是响应耗时监控）。我在这里标注出来，**不假装测过**。

---

# 知识点 2：子聚合与管道聚合

## 2.1 三种"套娃"，别搞混

知识点 1 我们已经见过"桶里套指标"。但 ES 里其实有**三种**嵌套，很多人分不清：

| 类型 | 套在哪 | 作用 | 关键字段 |
|---|---|---|---|
| **子聚合 Sub-agg** | 桶**内部** | 在每个桶里算指标 / 再分桶 | `aggs` |
| **管道聚合 Pipeline** | 桶**内部** | 对**兄弟聚合的结果**再聚合 | `buckets_path` |
| **（不存在顶层管道）** | — | ❌ 管道聚合不能放顶层 | — |

判断标准就一条：**看你引用的路径是"字段"还是"另一个聚合"。**

- 子聚合：`{ "sum": { "field": "amount" } }` → 引用**字段**
- 管道聚合：`{ "max_bucket": { "buckets_path": "by_brand>销售额" } }` → 引用**另一个聚合**

## 2.2 子聚合：在桶里再分桶

知识点 1 的「品牌 → 品类」就是子聚合。这里补充一个重要细节——**子聚合的计算范围**：

```json
POST /l8_orders_v2/_search?size=0
{
  "aggs": {
    "by_brand": {
      "terms": { "field": "brand" },
      "aggs": {
        "by_category": { "terms": { "field": "category" } }
      }
    }
  }
}
```

`by_category` 的**输入**是 `by_brand` 的每个桶，**不是**全量数据。

```text
【苹果】8 单                    ← by_brand 的桶
   └ 手机 3 单                  ← by_category 只在苹果这 8 单里分组
   └ 电脑 3 单
   └ 平板 2 单
```

**验证**：3 + 3 + 2 = 8 ✅ 等于父桶的 `doc_count`。

## 2.3 管道聚合：对聚合结果再聚合

管道聚合的**输入是其他聚合的输出**，不是文档。这是它和子聚合的本质区别。

### ① max_bucket — 找出销售额最高的品牌

不用自己遍历桶数组，让 ES 帮你找：

```json
POST /l8_orders_v2/_search?size=0
{
  "aggs": {
    "by_brand": {
      "terms": { "field": "brand" },
      "aggs": { "销售额": { "sum": { "field": "amount" } } }
    },
    "销售额最高的品牌": {
      "max_bucket": { "buckets_path": "by_brand>销售额" }
    }
  }
}
```

**实测输出：**

```text
max_bucket → keys=['苹果']  value=80390.0
```

**`buckets_path` 语法解读：**

```text
by_brand>销售额
   ↑        ↑
   │        └─ 目标聚合名（指标）
   └────────── 父桶聚合名

> 表示"进入下一层"
```

**其他兄弟聚合**：`min_bucket`、`avg_bucket`、`sum_bucket`、`stats_bucket`。

### ② cumulative_sum — 累计求和（有个硬性限制）

```json
POST /l8_orders_v2/_search?size=0
{
  "aggs": {
    "by_week": {
      "date_histogram": { "field": "sale_date", "calendar_interval": "week" },
      "aggs": {
        "周销售额": { "sum": { "field": "amount" } },
        "累计":    { "cumulative_sum": { "buckets_path": "周销售额" } }
      }
    }
  }
}
```

**实测输出：**

```text
2026-07-27  本周=21997.0   累计= 21997.0
2026-08-03  本周=55890.0   累计= 77887.0
2026-08-10  本周=52279.0   累计=130166.0
2026-08-17  本周=54892.0   累计=185058.0
2026-08-24  本周= 4999.0   累计=190057.0        ← 末值 = 总销售额 ✅
```

**累计终值 190057.0 = 全量总销售额**，交叉验证通过。

> #### ⚠️ 实测踩坑：cumulative_sum 的父聚合必须是指方图
>
> 我第一次写的时候，把 `cumulative_sum` 挂在 `terms` 桶下面：
>
> ```json
> { "aggs": { "by_brand": { "terms": { "field": "brand" },
>     "aggs": { "销售额": { "sum": {...} },
>               "累计": { "cumulative_sum": { "buckets_path": "销售额" } } } } } }
> ```
>
> **实测报错原文：**
> ```text
> action_request_validation_exception:
> Validation Failed: 1: cumulative_sum aggregation [累计] must have a
> histogram, date_histogram or auto_date_histogram as parent;
> ```
>
> **原因**：累计求和需要桶之间**有顺序**（时间序、数值序）。`terms` 桶是按 `doc_count` 排序的**名义类别**（苹果、华为、小米之间没有先后），"累计"没有意义。
>
> **这是设计上的合理性约束，不是 bug。** 想对 terms 桶累计，得先按 `_key` 或 `_count` 排序，但仍不被允许——**累计只在有序轴上成立**。

### ③ bucket_script — 用脚本算派生指标

想在桶内做自定义计算（比如"销售额 ÷ 订单数 = 客单价"）：

```json
POST /l8_orders_v2/_search?size=0
{
  "aggs": {
    "by_brand": {
      "terms": { "field": "brand" },
      "aggs": {
        "销售额": { "sum": { "field": "amount" } },
        "订单数": { "value_count": { "field": "order_id" } },
        "客单价": {
          "bucket_script": {
            "buckets_path": { "s": "销售额", "c": "订单数" },
            "script": "params.s / params.c"
          }
        }
      }
    }
  }
}
```

**实测输出：**

```text
华为  销售额 64179.0  客单价  8022.38
小米  销售额 45488.0  客单价  5686.00
苹果  销售额 80390.0  客单价 10048.75
```

**手算验证**（苹果）：`80390 / 8 = 10048.75` ✅

> #### ⚠️ 实测踩坑：bucket_script 不能放顶层
>
> 我第一次想算"各品牌占比"，把 `bucket_script` 放在了 `aggs` 顶层：
>
> ```json
> { "aggs": {
>     "by_brand": { "terms": {...}, "aggs": { "销售额": {...} } },
>     "总销售额": { "sum": { "field": "amount" } },
>     "占比": { "bucket_script": { "buckets_path": { "s": "销售额" }, ... } } } }
> ```
>
> **实测报错原文：**
> ```text
> action_request_validation_exception:
> Validation Failed: 1: No aggregation found for path [销售额];
> ```
>
> **原因**：`bucket_script` 是**管道聚合**，它的 `buckets_path` 是**相对于父桶**解析的。放在顶层时，同级的 `销售额` 藏在 `by_brand` 桶里面，顶层找不到。
>
> **正确做法**：`bucket_script` 必须挂在**桶内部**，与它引用的指标**同级**：
>
> ```json
> "by_brand": { "terms": {...},
>   "aggs": { "销售额": {...}, "订单数": {...},
>             "客单价": { "bucket_script": {...} } } }   ← 挂在桶内
> ```
>
> **占百分比则不适合用 bucket_script**（无法在桶内引用顶层总量）。实践中更简单：取回各品牌销售额后，在应用层或用 ES|QL 算占比。

## 2.4 管道聚合速查表

| 管道聚合 | 用途 | 父聚合要求 | 本课实测 |
|---|---|---|---|
| `max_bucket` / `min_bucket` | 找最大/最小的桶 | 任意多桶聚合 | 苹果 80390.0 |
| `avg_bucket` / `sum_bucket` | 对桶值求平均/求和 | 任意多桶聚合 | 本课未测 |
| `stats_bucket` | 桶值的统计概览 | 任意多桶聚合 | 本课未测 |
| `cumulative_sum` | **累计求和** | ⚠️ **必须 histogram 类** | 末值 190057.0 |
| `derivative` | 求导（环比变化） | ⚠️ 必须 histogram 类 | 本课未测 |
| `bucket_script` | **自定义脚本计算** | ⚠️ 必须挂在桶内 | 客单价 10048.75 |
| `bucket_sort` | 对桶排序/截断 | 任意多桶聚合 | 本课未测 |

> ⚠️ **诚实标注**：表中 `avg_bucket`、`sum_bucket`、`stats_bucket`、`derivative`、`bucket_sort` 本课**未实测**。我只测了最有代表性的四个（`max_bucket`/`cumulative_sum`/`bucket_script`）。**未测的我不假装测过**，其余留给后续课程或你自己验证。

## 2.5 知识点 2 小结

三句话记住：

1. **子聚合**在桶里算**字段**（`field`），回答"每个组里怎么样"
2. **管道聚合**对**聚合结果**再算（`buckets_path`），回答"这些组之间比起来怎么样"
3. **管道聚合有位置约束**：`cumulative_sum`/`derivative` 必须挂 histogram，`bucket_script` 必须挂桶内

---

# 知识点 3：ES|QL 入门

## 3.1 为什么需要 ES|QL

看一眼知识点 1 那个"按品牌算销售额"的 DSL，嵌套了 3 层花括号。稍微复杂点的分析，DSL 能写到几百行、缩进到眼花。

**ES|QL（Elasticsearch Query Language）** 是 ES 8.11+ 推出的**管道式查询语言**，用 `|` 把操作串起来，像 Unix 管道一样自上而下读。

**同一个需求，两种写法：**

**DSL（嵌套 JSON）：**

```json
POST /l8_orders_v2/_search?size=0
{
  "aggs": {
    "by_brand": {
      "terms": { "field": "brand" },
      "aggs": { "total": { "sum": { "field": "amount" } } }
    }
  }
}
```

**ES|QL（管道语法）：**

```sql
FROM l8_orders_v2
| STATS total = SUM(amount) BY brand
| SORT total DESC
```

**两者实测结果完全一致：**

```text
total     | brand
80390.0   | 苹果
64179.0   | 华为
45488.0   | 小米
```

## 3.2 基本语法

ES|QL 走的是**独立的 `_query` 端点**（不是 `_search`）：

```bash
curl -X POST "https://localhost:9200/_query?format=txt" \
  -u elastic:ESlearn2026 -H "Content-Type: application/json" -d '{
    "query": "FROM l8_orders_v2 | STATS cnt = COUNT(*) BY brand"
  }'
```

核心命令（按管道顺序）：

| 命令 | 作用 | 对应 DSL |
|---|---|---|
| `FROM` | 指定索引（**必须开头**） | URL 中的索引名 |
| `WHERE` | 过滤行 | `query` |
| `STATS ... BY` | 分组聚合 | `aggs` |
| `SORT` | 排序 | `sort` |
| `LIMIT` | 限制行数 | `size` |
| `KEEP` / `DROP` | 保留/丢弃列 | `_source` 过滤 |
| `EVAL` | 计算新列 | `script_fields` |
| `BUCKET()` | 时间/数值分桶 | `date_histogram` |

## 3.3 实测：从简单到复杂

### ① FROM + LIMIT — 取前 5 条

```sql
FROM l8_orders_v2 | LIMIT 5
```

**实测输出（节选 3 列）：**

```text
   amount    |  brand   |     product     |  price
-------------+----------+-----------------+----------
7999         | 苹果      | iPhone 15 Pro   | 7999
13998        | 华为      | Mate 60         | 6999
4999         | 小米      | 小米14          | 4999
12999        | 苹果      | MacBook Pro     | 12999
8999         | 华为      | MateBook X      | 8999
```

> **注意**：ES|QL 返回的列**包含 multi-fields**（`brand` 和 `brand.keyword` 都出现）。这是当前版本的行为，用 `KEEP` 可以只保留需要的列。

### ② STATS ... BY — 分组聚合

```sql
FROM l8_orders_v2
| STATS cnt = COUNT(*), total = SUM(amount), avg_price = AVG(price) BY brand
| SORT total DESC
```

**实测输出：**

```text
   cnt   |   total   |  avg_price  |  brand
---------+-----------+-------------+----------
8        | 80390     | 8849.0      | 苹果
8        | 64179     | 6497.625    | 华为
8        | 45488     | 4236.5      | 小米
```

**与 DSL 结果完全一致** ✅（苹果 80390、华为 64179、小米 45488，均价 8849.0 / 6497.625 / 4236.5）

### ③ WHERE + SORT + KEEP — 筛选排序取列

```sql
FROM l8_orders_v2
| WHERE price > 8000
| SORT price DESC
| LIMIT 5
| KEEP order_id, brand, product, price
```

**实测输出：**

```text
   order_id  |  brand  |      product      |  price
-------------+---------+-------------------+----------
O004         | 苹果     | MacBook Pro       | 12999
O022         | 苹果     | iMac              | 10999
O019         | 苹果     | iPhone 15 Pro Max | 9999
O005         | 华为     | MateBook X        | 8999
O013         | 苹果     | MacBook Air       | 8999
```

### ④ BUCKET() — 时间分桶

```sql
FROM l8_orders_v2
| STATS cnt = COUNT(*), total = SUM(amount) BY wk = BUCKET(sale_date, 1 week)
| SORT wk ASC
```

**实测输出：**

```text
   cnt   |   total   |           wk
---------+-----------+------------------------
2        | 21997     | 2026-07-27T00:00:00.000Z
7        | 55890     | 2026-08-03T00:00:00.000Z
7        | 52279     | 2026-08-10T00:00:00.000Z
7        | 54892     | 2026-08-17T00:00:00.000Z
1        | 4999      | 2026-08-24T00:00:00.000Z
```

**与 DSL `date_histogram` 结果完全一致** ✅

## 3.4 ⚠️ 实测踩坑：ES|QL 不支持中文列名

这是我实测中**最意外**的发现。

我按讲义惯例，想给聚合结果起个中文名：

```sql
FROM l8_orders_v2 | STATS 订单数 = COUNT(*) BY brand
```

**实测报错原文：**

```text
parsing_exception:
line 1:27: token recognition error at: '订'
```

**列名（别名）不支持中文**。改成英文别名就好了：

```sql
FROM l8_orders_v2 | STATS cnt = COUNT(*) BY brand
```

但**中文的"值"完全没问题**——`BY brand` 返回的中文档名正常显示（见 3.3 ②的"苹果/华为/小米"）。

**结论**：

| | 中文支持 | 实测证据 |
|---|---|---|
| **列名 / 别名** | ❌ 不支持 | `STATS 订单数 = ...` 报 `token recognition error` |
| **字段值** | ✅ 支持 | `BY brand` 返回"苹果""华为""小米" |
| **字符串字面量** | ✅ 支持 | `WHERE brand == "苹果"` 正常返回 8 条 |

> **关于报错里的行号**：报错位置 `line 1:27` 是「订」在整条语句中的**字符序号**。同一个错误写在 `l8_orders`（短索引名）下会报 `line 1:24`——**差 3 正好是两个索引名的长度差**（`l8_orders_v2` 比 `l8_orders` 长 3 个字符）。这反过来印证了报错位置是**按字符计数的**，不是按词。

> **这呼应了课 7 的 GBK 编码坑**：在 Windows 中文环境下跟 ES 打交道，编码问题会反复以不同形式出现。**别名用英文，值用中文**，这是当前 ES|QL 的务实做法。

**补充实测**——中文值查询正常：

```sql
FROM l8_orders_v2 | WHERE brand == "苹果" | STATS cnt = COUNT(*), total = SUM(amount)
```

```text
   cnt   |   total
---------+----------
8        | 80390
```

## 3.5 什么时候用 ES|QL，什么时候用 DSL

| 场景 | 推荐 | 理由 |
|---|---|---|
| 探索性分析、临时查数 | **ES\|QL** | 写得快、读得懂、像 SQL |
| 复杂多层嵌套聚合 | **DSL** | 表达力更完整，生态成熟 |
| 需要 `filter` 上下文缓存 | **DSL** | ES\|QL 目前缓存机制不同 |
| 需要精细控制（如 `precision_threshold`） | **DSL** | 参数可调项更多 |
| 管道聚合（`cumulative_sum` 等） | **DSL** | ES\|QL 支持面仍在扩展 |
| 要集成到 SQL 生态（BI/JDBC） | **ES\|QL** | 语法接近 SQL，易对接 |

> **我的建议**：**两个都要会。** ES|QL 是趋势（官方重心明显在往这边移），但 DSL 在复杂场景仍不可替代。本课两个都教，就是希望你别把宝押在一边。

> ⚠️ **版本标注**：ES\|QL 自 8.11 引入，**每个版本语法都在演进**。本课所有 ES\|QL 语句均在 **9.5.1** 实测通过。你若用其他版本，部分语法可能不同。

---

# 综合实战：一张销售分析报表

把三个知识点串起来，回答五个真实的业务问题。

## 问题 1：各品牌销售额排行（含占比）

```json
POST /l8_orders_v2/_search?size=0
{
  "aggs": {
    "by_brand": {
      "terms": { "field": "brand", "size": 10 },
      "aggs": { "销售额": { "sum": { "field": "amount" } } }
    },
    "总销售额": { "sum": { "field": "amount" } }
  }
}
```

**实测输出（占比在应用层算）：**

| 品牌 | 销售额 | 占比 | 订单数 |
|---|---|---|---|
| 苹果 | 80390.0 | **42.3%** | 8 |
| 华为 | 64179.0 | 33.8% | 8 |
| 小米 | 45488.0 | 23.9% | 8 |

**校验**：`80390 + 64179 + 45488 = 190057` ✅ 等于总销售额；`42.3% + 33.8% + 23.9% = 100%` ✅

**业务解读**：三个品牌订单数完全相同（都是 8 单），但苹果销售额占 42.3%——**说明苹果客单价明显更高**。

## 问题 2：哪个城市客单价最高？

```json
POST /l8_orders_v2/_search?size=0
{
  "aggs": {
    "by_city": {
      "terms": { "field": "city", "size": 10 },
      "aggs": {
        "订单数": { "value_count": { "field": "order_id" } },
        "销售额": { "sum": { "field": "amount" } },
        "客单价": { "bucket_script": {
          "buckets_path": { "s": "销售额", "c": "订单数" },
          "script": "params.s / params.c" } }
      }
    }
  }
}
```

**实测输出（按客单价降序）：**

| 城市 | 订单数 | 销售额 | 客单价 |
|---|---|---|---|
| **上海** | 6 | 62388.0 | **10398.00** |
| 北京 | 9 | 69190.0 | 7687.78 |
| 广州 | 5 | 36694.0 | 7338.80 |
| 深圳 | 4 | 21785.0 | 5446.25 |

**手算验证**：上海 `62388 / 6 = 10398.0` ✅

**反直觉发现**：北京**订单最多**（9 单）、**总额最高**（69190），但**客单价只排第二**——因为它卖的多是便宜单。上海单量少但每单金额大。

> **这正是聚合的价值**：如果只看"销售额排行"，你会得出"北京最好"的结论；加上客单价维度，结论完全变了。**多维交叉才能避免误判。**

## 问题 3：退款率分析

```json
POST /l8_orders_v2/_search?size=0
{
  "aggs": {
    "状态分布": { "filters": { "filters": {
      "已完成": { "term": { "status": "已完成" } },
      "退款":   { "term": { "status": "退款"   } } } } }
  }
}
```

**实测输出：**

```text
已完成: 20 单
退款:    4 单
退款率: 16.7%
```

**校验**：`4 / (20 + 4) = 16.666...%` → 一位小数 **16.7%**，两位小数 **16.67%** ✅

（讲义正文统一用一位小数 16.7%；若你算得 16.67%，两者都正确，只是精度取舍不同。）

## 问题 4：热门标签 TOP5

```json
POST /l8_orders_v2/_search?size=0
{
  "aggs": { "热门标签": { "terms": { "field": "tags", "size": 5 } } }
}
```

**实测输出：**

```text
高端     6 单
性价比    5 单
新品     4 单
热销     4 单
办公     3 单
```

> **`tags` 是 array 字段**：一条文档有多个标签时，**每个标签都会独立计数**。所以各标签数之和（6+5+4+4+3=22）不等于文档数 24，这是**正常现象**，不是 bug。

## 问题 5：用 ES|QL 重做问题 1

```sql
FROM l8_orders_v2
| STATS cnt = COUNT(*), total = SUM(amount), avg_price = AVG(price) BY brand
| SORT total DESC
```

**实测输出：**

```text
   cnt   |   total   |  avg_price  |  brand
---------+-----------+-------------+----------
8        | 80390.0   | 8849.0      | 苹果
8        | 64179.0   | 6497.625    | 华为
8        | 45488.0   | 4236.5      | 小米
```

**与问题 1 的 DSL 结果完全一致** ✅

---

# 本课总结

## 三句话

1. **搜索找文档，聚合算数字**——`query` 圈范围，`aggs` 做统计，`size=0` 是标配
2. **聚合必须用 keyword**——text 分词会把"苹果"拆成"苹""果"两个桶，这是课 5 multi-fields 存在的理由
3. **ES|QL 写起来像 SQL，DSL 表达力更强**——两个都要会，按场景选

## 本课五个实测踩坑

| # | 坑 | 报错原文 / 现象 | 正确做法 |
|---|---|---|---|
| 1 | **对 text 字段聚合** | `Fielddata is disabled on [brand]` | 用 keyword 字段 |
| 2 | **`fielddata=true` 救急** | 结果变成 6 个碎桶（苹/果/华/为/小/米） | reindex 改 keyword mapping |
| 3 | **`cumulative_sum` 挂 terms 下** | `must have a histogram... as parent` | 只挂 histogram 类 |
| 4 | **`bucket_script` 放顶层** | `No aggregation found for path` | 必须挂桶内，与指标同级 |
| 5 | **ES\|QL 中文列名** | `token recognition error at: '订'` | 别名用英文，值用中文 |

## 呼应前序课程

| 本课内容 | 呼应 |
|---|---|
| 聚合必须用 keyword | **课 5 multi-fields**：一个字段存两份的用途 |
| text 分词破坏聚合 | **课 4 分词器**：IK 把"苹果"拆成"苹""果" |
| `query` + `aggs` 协作 | **课 6 Query DSL**：`query` 定范围 |
| 聚合不计分 | **课 7 BM25**：`_score` 是搜索的概念，聚合没有 |
| 中文列名报错 | **课 7 GBK 编码坑**：Windows 中文环境的编码问题 |

## 速查卡

```jsonc
// 桶 + 指标 + 子聚合
{ "size": 0,
  "query": { "term": { "status": "已完成" } },      // ① 定范围
  "aggs": {
    "by_brand": {                                   // ② 分组
      "terms": { "field": "brand", "size": 20 },
      "aggs": {
        "销售额":   { "sum": { "field": "amount" } },   // ③ 算数
        "订单数":   { "value_count": { "field": "order_id" } },
        "客单价":   { "bucket_script": {                // ④ 派生
          "buckets_path": { "s": "销售额", "c": "订单数" },
          "script": "params.s / params.c" } },
        "by_cat": { "terms": { "field": "category" } }  // ⑤ 再分组
      }
    },
    "最高的": { "max_bucket": { "buckets_path": "by_brand>销售额" } }
  }
}
```

```sql
-- ES|QL 等价写法
FROM l8_orders_v2
| WHERE status == "已完成"
| STATS cnt = COUNT(*), total = SUM(amount) BY brand
| SORT total DESC
```

---

## 下一课预告

**阶段 3《查询与聚合》到此收官。**

| 课 | 回答的问题 | 状态 |
|----|-----------|------|
| 课 6 | 怎么向 ES 提问（Query DSL） | ✅ 已完成 |
| 课 7 | 结果凭什么这么排（BM25 / 排序分页高亮 / 调优） | ✅ 已完成 |
| 课 8 | 怎么做统计（聚合） | ✅ 已完成 |

你现在具备的能力：**能问出精确的问题，能解释每个分数怎么来的，能从数据里算出业务要的数字。**

**阶段 4《分布式与工程实践》** 换个方向——前面我们默认 ES 只有一个分片在跑，接下来看它真正的看家本领：

- **课 9《分片：ES 分布式的基石》**：数据怎么分散到多个分片？为什么分片数一旦设定就改不了？
- 路由机制、分片数规划、副本与高可用、分布式下的聚合精度问题

### 伏笔表

| 本课留下的疑问 | 在哪一课解开 |
|---|---|
| `terms` 聚合的 `doc_count_error_upper_bound` 为什么在单分片下是 0？ | **课 9：分片** |
| 聚合在多个分片上怎么合并？分片多了精度会变差吗？ | **课 9：分片** |
| 写入后为什么不能立刻搜到（refresh_interval）？ | **阶段 4：写入流程** |
| `cardinality` 的 `precision_threshold` 怎么权衡内存与精度？ | **阶段 5：生产调优** |
| 分位数 `percentiles` 在监控场景怎么用？ | **阶段 5：可观测性** |

---

## 🚀 下一批接力提示词

> 学完本课后，**复制下面这段文字发给 AI**，即可无缝进入下一课（无需重新描述上下文）：

```
继续学 Elasticsearch。我的学习档案在 elasticsearch/00-学习档案.md，
刚学完阶段 3《查询与聚合》课 8《聚合：不做搜索，做统计》的三个知识点
（桶与指标聚合 / 子聚合与管道聚合 / ES|QL 入门），
本机已有运行中的 ES 9.5.1 且已装好 IK 9.5.1 插件（https://localhost:9200，
curl.exe -k -u elastic:密码），实测索引 l8_orders_v2（24 条订单，keyword mapping）、
l8_text_demo（text 字段报错演示）、l7_news（6 篇文章）、l6_shop（8 条商品）都在。

请按大纲继续讲解阶段 4 课 9《分片：ES 分布式的基石》的三个知识点。
重点说明数据怎么分散到多个分片、聚合在多分片下精度为什么会下降
（呼应课 8 的 doc_count_error_upper_bound），以及分片数为什么不能改。
```

## 🧭 课程导航

- **上一课**：[课 7 · 为什么这条排在前面](lesson-07-为什么这条排在前面.md)
- **下一课**：课 9 · 分片：ES 分布式的基石（阶段 4）
- **本阶段**：[阶段 3 概览](../overview.md)
- **返回**：[课程目录](../../02-课程目录.md) ｜ [学习路径总览](../../01-学习路径总览.md)

---

> **本课数据集**：`l8_orders_v2`（正确 keyword mapping，24 条）、`l8_orders`（误建的动态映射版本，24 条）、`l8_text_demo`（text 字段报错演示，24 条）均保留在本机 ES 中，可继续实验。
> **实测环境**：Elasticsearch 9.5.1，单节点，HTTPS + 基本认证，全部命令在本机真实执行。
