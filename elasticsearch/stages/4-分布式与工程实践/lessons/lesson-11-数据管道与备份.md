# 课 11 · 数据管道与备份

> 阶段 4《分布式与工程实践》第 3 课 ｜ 知识点：Ingest Pipeline / Reindex 与 Update By Query / 快照与恢复
> 环境：本机 ES 9.5.1（Windows 原生 zip）｜ 全部结论均在本机实测，标注「实测」者均有命令与输出原文

---

## 🧭 课程导航

| 上一课 | 本课 | 下一课 |
|--------|------|--------|
| [课10 集群健康与排障](../lesson-10-集群健康与排障.md) | **课11 数据管道与备份** | [课12 接入真实项目](../lesson-12-接入真实项目.md) |

**本课在体系中的位置**：阶段 4（分布式与工程实践）→ 第三课。课 9 讲了数据怎么分布，课 10 讲了挂了怎么排查，本课讲**怎么把数据加工好、迁移好、备份好**。

---

## 📖 五幕结构

### 第一幕 · 场景引入：那些"事后才发现"的数据问题

先讲三个真实场景，你看看熟不熟悉。

**场景一：日志字段全是字符串**

你把服务器日志灌进 ES，想统计"响应码 500 出现了多少次"。于是写了聚合，结果是空的。查了半天才发现：`response` 字段存的是字符串 `"500"`，而你想聚合的是数字 `500`。字符串和数字在 ES 里是两个世界。

**场景二：分片数设错了**

上线时给索引起了 1 个分片，半年后数据涨到 2 亿条，查询慢到不能忍。你想改成 12 个分片——ES 拒绝了你：

```
Can't update non dynamic setting(s) [[index.number_of_shards]]
The setting(s) cannot be modified on an index once it is created.
You will need to create a new index with the desired setting(s) and reindex your data
```

（这条报错原文来自课 9 的实测）

**场景三：删库了**

某个下午，有人执行了一条 `DELETE /orders`。集群瞬间变红。你想起来上周做过副本——但课 10 已经证明过：**副本防的是节点故障，不是人为删除**。`DELETE` 命令会同步到所有副本。

这三个场景，对应本课的三个知识点：

| 场景 | 知识点 | 一句话解法 |
|------|--------|-----------|
| 日志字段是字符串 | **Ingest Pipeline** | 写入前就把数据加工好 |
| 分片数设错了 | **Reindex** | 建个新索引，把数据搬过去 |
| 删库了 | **快照与恢复** | 从快照还原，这是唯一不丢数据的路 |

---

### 第二幕 · 认知冲突：几个"想当然"的坑

在动手之前，先把几个最容易搞错的地方摆出来。这些不是我编的，都是本课实测踩出来的。

**冲突一：Pipeline 加工的是"写入的内容"，不只是"索引"**

很多人以为 Ingest Pipeline 只是给索引加个字段，原始数据还在。错了。Pipeline 改的是 **`_source` 本身**——你存进去什么，取出来就是什么。

本课实测：写入 `{"brand":"apple","price_str":"8999"}`，经过 pipeline 后取出来是 `{"brand":"APPLE","price":8999}`，**`price_str` 这个字段彻底不存在了**。

**冲突二：`_update_by_query` 会偷偷重跑一遍你的 Pipeline**

这条最坑。你给索引绑了 `default_pipeline`，然后想批量改数据。你会发现：**文档一条都没改**。

本课实测：`total: 2, updated: 0`，报错是 `field [price_str] not present as part of path [price_str]`。

原因：`_update_by_query` 默认会把 `default_pipeline` 再跑一遍，而那个 pipeline 里的 `convert` 要读 `price_str`——可这个字段早在上次写入时就被 `remove` 掉了。

解法：加 `?pipeline=_none`。实测加上之后立刻 `updated: 2`。

**冲突三：快照存在"本地"等于没备份**

这是课 10 结尾我留给你的问题：*快照本身存在哪？如果整个集群的机器都烧了，备份还在吗？*

本课实测：我配的仓库是 `fs` 类型，location 指向 **D 盘的一个目录**。而集群的数据也在 **D 盘**。

**同一块盘。** 盘坏了，数据和备份一起没。

真正的解法是：快照必须放到**集群之外的存储**上（另一台机器、对象存储 S3/GCS/Azure）。本课会实测跨集群恢复来证明这一点。

**冲突四：删掉旧的快照，不会弄坏新的快照**

听起来反直觉，但这是真的。快照是**增量**的——后面的快照只存"相对于前面快照变化的部分"。那删掉前面的，后面的不就残废了吗？

本课实测：删掉最早的 `snap_1` 后，从 `snap_4` 恢复，数据**完整无缺**。ES 会自动保留仍被引用的底层数据块。

---

### 第三幕 · 层层揭示：三个知识点逐个拆开

## 知识点 1 · Ingest Pipeline：写入前的加工车间

### 1.1 它是什么

**Ingest Pipeline（摄取管道）** 是 ES 内置的一个"数据加工车间"。文档在**写入索引之前**，先经过这个车间，被一串处理器（processor）依次处理，处理完才落盘。

打个比方：你是快递分拣中心。包裹（文档）进来后，先过一道流水线——扫码登记（set）、改标签（rename）、拆掉多余包装（remove）、把重量从"1.5kg"转成数字 1.5（convert）——然后才上架。

**为什么不在客户端做？** 三个理由：

1. **一处修改，处处生效**：所有写入路径（bulk、单条、reindex）都走同一套逻辑，不会漏
2. **服务端能力**：`grok` 解析、`geoip` 查询这类需要服务端资源的活儿，客户端干不了
3. **解耦**：改加工逻辑不用重新部署你的应用

### 1.2 先摸清环境：命令怎么敲

本机是 Windows，终端是 **PowerShell**，**没有安装 Git Bash**（这个坑课 10 实测确认过）。所以命令有讲究：

```powershell
# ✅ 推荐：JSON 写进文件，用 --data-binary @文件 传
curl.exe -s -X POST "http://localhost:9201/_ingest/pipeline/_simulate" `
  -H "Content-Type: application/json" `
  --data-binary @D:/projects/learning/elasticsearch/playground/l11-sim-basic.json

# ⚠️ CMD 下可用、PowerShell 下失败（反斜杠转义）
curl.exe -s -X POST "http://localhost:9201/_ingest/pipeline/_simulate" -H "Content-Type: application/json" -d "{\"key\":1}"

# ❌ 两种终端都失败（curl 会把双引号吃掉）
curl.exe -s -X POST "..." -d '{"key":1}'
```

> **为什么**：Windows 的 curl 在 PowerShell 下会把内联 JSON 的双引号吃掉，报 `was expecting double-quote to start field name`。**PowerShell 下 JSON 一律用文件传参**。这是课 10 实测的结论。

本课所有 JSON 请求体都放在 `playground/` 目录下，可直接复制使用。

### 1.3 第一个 Pipeline：四件套

先用 `_simulate` 试跑——它**不写任何数据**，只告诉你"如果写入，会变成什么样"。这是学习 Pipeline 最好的工具。

请求体（`playground/l11-sim-basic.json`）：

```json
{
  "pipeline": {
    "description": "set / rename / remove / convert 四件套",
    "processors": [
      { "set": { "field": "ingest_time", "value": "2026-08-31T10:35:00" } },
      { "rename": { "field": "old_name", "target_field": "new_name" } },
      { "remove": { "field": "temp_field" } },
      { "convert": { "field": "price_str", "type": "integer" } }
    ]
  },
  "docs": [
    { "_source": { "old_name": "手机", "temp_field": "用完就扔", "price_str": "1999" } }
  ]
}
```

```powershell
curl.exe -s -X POST "http://localhost:9201/_ingest/pipeline/_simulate?verbose" `
  -H "Content-Type: application/json" `
  --data-binary @D:/projects/learning/elasticsearch/playground/l11-sim-basic.json
```

**`verbose=true` 是关键**——它会把每个 processor 处理完的中间状态都列出来。实测输出（节选，四个阶段）：

| 阶段 | `_source` 内容 | 变化 |
|------|----------------|------|
| 原始 | `old_name:手机, temp_field:用完就扔, price_str:"1999"` | — |
| ① set | + `ingest_time:"2026-08-31T10:35:00"` | 加了字段 |
| ② rename | `old_name` → `new_name` | 改名 |
| ③ remove | `temp_field` 消失 | 删字段 |
| ④ convert | `price_str:"1999"` → `price_str:1999` | **字符串变数字**（无引号） |

最后一步最有价值：**`1999` 从带引号的字符串变成了不带引号的数字**。这就是开头场景一的解法。

### 1.4 常用 Processor 速查

| Processor | 作用 | 典型场景 |
|-----------|------|----------|
| `set` | 设置/覆盖字段 | 打时间戳、加默认值 |
| `rename` | 改字段名 | 兼容旧数据 |
| `remove` | 删字段 | 去掉临时字段、脱敏 |
| `convert` | 类型转换 | 字符串转数字（**最常用**） |
| `grok` | 正则解析文本 | 解析日志行 |
| `date` | 解析时间字符串 | 生成 `@timestamp` |
| `uppercase` / `lowercase` | 大小写 | 品牌名归一化 |
| `split` | 字符串转数组 | `"a,b,c"` → `["a","b","c"]` |
| `join` | 数组转字符串 | 反向操作 |
| `script` | Painless 脚本 | 复杂计算 |
| `geoip` | IP 转地理位置 | 访问日志分析 |
| `foreach` | 遍历数组元素 | 数组里每个元素都加工 |

### 1.5 实战：解析 Apache 访问日志

这是 Ingest Pipeline 在生产上最经典的用途。原始日志是一整行文本：

```
127.0.0.1 - - [31/Aug/2026:10:35:00 +0800] "GET /api/search?q=es HTTP/1.1" 200 1234
```

想让它变成结构化字段，用 `grok`：

```json
{
  "pipeline": {
    "description": "解析 Apache 访问日志",
    "processors": [
      { "grok": { "field": "message", "patterns": ["%{COMMONAPACHELOG}"] } },
      { "date": {
          "field": "timestamp",
          "formats": ["dd/MMM/yyyy:HH:mm:ss Z"],
          "timezone": "Asia/Shanghai",
          "target_field": "@timestamp"
      } },
      { "convert": { "field": "response", "type": "integer" } },
      { "convert": { "field": "bytes", "type": "integer" } }
    ]
  },
  "docs": [
    { "_source": { "message": "127.0.0.1 - - [31/Aug/2026:10:35:00 +0800] \"GET /api/search?q=es HTTP/1.1\" 200 1234" } }
  ]
}
```

**实测输出**（`grok` 之后）：一条文本被拆成了 8 个字段——

```
clientip: "127.0.0.1"    ident: "-"     auth: "-"
timestamp: "31/Aug/2026:10:35:00 +0800"
verb: "GET"   request: "/api/search?q=es"   httpversion: "1.1"
response: "200"   bytes: "1234"
```

然后 `date` 把 `timestamp` 字符串转成标准时间字段：

```
@timestamp: "2026-08-31T10:35:00.000+08:00"
```

注意带上了 **`+08:00` 时区**——这是我显式指定 `timezone: "Asia/Shanghai"` 的结果。不指定的话 ES 按 UTC 解析，时间会差 8 小时。

最后两个 `convert` 把 `response` 和 `bytes` 转成数字，就可以做聚合统计了。

### 1.6 一个真实的坑：grok 不匹配会丢数据

我在实测时先用了 `%{COMBINEDAPACHELOG}`（更完整的 Apache 日志格式），结果直接报错：

```
illegal_argument_exception: Provided Grok expressions do not match field value:
[127.0.0.1 - - [31/Aug/2026:10:35:00 +0800] "GET /api/search?q=es HTTP/1.1" 200 1234]
```

**原因**：`COMBINEDAPACHELOG` 要求日志末尾还要有 `referrer`（来源页）和 `agent`（浏览器标识）两个字段，我的测试日志没有。

**后果很严重**：grok 匹配失败会让**整篇文档被拒收**。生产上一批日志里只要有一条格式不对，整批写入失败。

**解法**：`on_failure`。

### 1.7 on_failure：给脏数据留一条活路

`on_failure` 挂在 processor 上，出错时执行你指定的补救动作，而不是让整篇文档挂掉。

```json
{
  "pipeline": {
    "description": "grok 失败时不丢弃文档，而是打标并保留原文",
    "processors": [
      {
        "grok": {
          "field": "message",
          "patterns": ["%{COMMONAPACHELOG}"],
          "on_failure": [
            { "set": { "field": "_index", "value": "failed-logs" } },
            { "set": { "field": "grok_error", "value": "{{ _ingest.on_failure_message }}" } }
          ]
        }
      }
    ]
  },
  "docs": [
    { "_source": { "message": "127.0.0.1 - - [31/Aug/2026:10:35:00 +0800] \"GET /api/search?q=es HTTP/1.1\" 200 1234" } },
    { "_source": { "message": "这是一条完全不规范的日志" } }
  ]
}
```

**实测结果**（两条输入，两种命运）：

| 输入 | 结果 `_index` | `_source` 内容 |
|------|---------------|----------------|
| 规范日志 | `_index`（原样） | 8 个字段解析成功 |
| 脏数据 | **`failed-logs`** | `message` 原文 + `grok_error` |

脏数据被**自动路由到死信索引** `failed-logs`，并且把错误原因写进了 `grok_error` 字段：

```
grok_error: "Provided Grok expressions do not match field value: [这是一条完全不规范的日志]"
```

这就是生产上的**死信队列（Dead Letter Queue）**模式：好数据进主索引，坏数据进死信索引等着人工处理，谁也不耽误谁。

> **注意**：`on_failure` 里改 `_index` 这个技巧很实用，但要确保目标索引存在或能被自动创建，否则会二次失败。

### 1.8 真刀真枪：建一个 Pipeline 并写入数据

模拟跑通了，现在建正式的。这个 pipeline 演示五种 processor 加 `on_failure`：

```json
{
  "description": "课11 主管道：写入前加工",
  "processors": [
    { "set": { "field": "stage_default", "value": "default已执行" } },
    { "uppercase": { "field": "brand" } },
    {
      "convert": {
        "field": "price_str", "type": "integer", "target_field": "price",
        "on_failure": [ { "set": { "field": "price", "value": 0 } } ]
      }
    },
    { "remove": { "field": "price_str" } },
    {
      "script": {
        "description": "按价格打标",
        "lang": "painless",
        "source": "ctx.price_level = ctx.price >= 5000 ? 'high' : 'low'"
      }
    }
  ]
}
```

```powershell
curl.exe -s -X PUT "http://localhost:9201/_ingest/pipeline/l11_main" `
  -H "Content-Type: application/json" `
  --data-binary @D:/projects/learning/elasticsearch/playground/l11-pipeline-main.json
```

返回 `{"acknowledged":true}` 就创建好了。

**怎么让它自动生效？** 在索引的 settings 里写 `default_pipeline`：

```json
{
  "settings": {
    "number_of_shards": 1,
    "number_of_replicas": 0,
    "default_pipeline": "l11_main"
  },
  "mappings": {
    "properties": {
      "brand": { "type": "keyword" },
      "price": { "type": "integer" },
      "price_level": { "type": "keyword" },
      "stage_default": { "type": "keyword" },
      "stage_final": { "type": "keyword" }
    }
  }
}
```

写入三条数据（第三条故意用非数字）：

```
{"index":{"_index":"l11_shop","_id":"1"}}
{"brand":"apple","price_str":"8999"}
{"index":{"_index":"l11_shop","_id":"2"}}
{"brand":"xiaomi","price_str":"2999"}
{"index":{"_index":"l11_shop","_id":"3"}}
{"brand":"huawei","price_str":"不是数字"}
```

```powershell
curl.exe -s -X POST "http://localhost:9201/_bulk?refresh=true" `
  -H "Content-Type: application/x-ndjson" `
  --data-binary @D:/projects/learning/elasticsearch/playground/l11-bulk-docs.ndjson
```

> **bulk 格式提醒**：每行必须以换行结尾，最后一行也要换行。索引操作行和文档行交替。

返回 `{"errors":false, ...}`，三条全部成功——**包括那条价格不是数字的**。

查询验证：

| 原始输入 | 加工后 | 用了什么 |
|----------|--------|----------|
| `brand:"apple"` | `brand:"APPLE"` | `uppercase` |
| `price_str:"8999"` | `price:8999`（`price_str` 已删除） | `convert` + `remove` |
| `price_str:"不是数字"` | **`price:0`** | **`on_failure` 兜底** |
| 无 | `price_level:"high"/"low"` | `script` |
| 无 | `stage_default:"default已执行"` | `set` |

**`_source` 里完全没有 `price_str`**——证明 Pipeline 改的是文档内容本身，不只是索引。这就是第二幕说的"冲突一"。

### 1.9 default_pipeline vs final_pipeline

| 类型 | 执行时机 | 典型用途 |
|------|----------|----------|
| `default_pipeline` | 文档进入索引时；**若无则跳过** | 主加工逻辑 |
| `final_pipeline` | **永远最后执行**，即使请求里指定了别的 pipeline | 强制收尾（如统一打时间戳） |

区别在"覆盖"行为上：如果写入请求里用 `?pipeline=xxx` 指定了管道，`default_pipeline` **不会执行**，但 `final_pipeline` **一定会执行**。

所以 `final_pipeline` 适合做"谁也绕不过去"的收尾动作，比如统一加审计字段。

---

## 知识点 2 · Reindex 与 Update By Query：改数据、搬数据

### 2.1 Update By Query：批量改已有数据

数据已经写进去了，想批量修改怎么办？`_update_by_query`。

> **⚠ 前置依赖**：本节的所有命令都依赖 1.8 节建好的 `l11_shop` 索引和那 3 条数据。如果你跳过了 1.8，先回去执行那三行（建 pipeline → 建索引 → bulk 写入），否则这里会报 `no such index [l11_shop]`。

比如给所有 `price >= 1` 的商品加价 100，并打上标记：

```json
{
  "script": {
    "source": "ctx._source.price = ctx._source.price + params.inc; ctx._source.updated = true",
    "lang": "painless",
    "params": { "inc": 100 }
  },
  "query": { "range": { "price": { "gte": 1 } } }
}
```

```powershell
curl.exe -s -X POST "http://localhost:9201/l11_shop/_update_by_query?refresh=true&conflicts=proceed" `
  -H "Content-Type: application/json" `
  --data-binary @D:/projects/learning/elasticsearch/playground/l11-ubq-price.json
```

**第一次执行，翻车了**（实测原文）：

```json
{
  "total": 2, "updated": 0, "deleted": 0, "batches": 1, "version_conflicts": 0,
  "failures": [
    {"index":"l11_shop","id":"1","cause":{"type":"illegal_argument_exception",
      "reason":"field [price_str] not present as part of path [price_str]"},"status":400},
    {"index":"l11_shop","id":"2","cause":{...同样错误...},"status":400}
  ]
}
```

**查询到 2 条，更新成功 0 条。**

### 2.2 这个坑的根源：default_pipeline 被重跑了

我的 `l11_shop` 索引绑了 `default_pipeline: l11_main`，那个 pipeline 里有一步是 `convert` 读 `price_str`。

但 `price_str` 在**首次写入时就被 `remove` 掉了**。所以 `_update_by_query` 一重跑 pipeline，就找不到 `price_str`，直接报错。

**验证归因**：加 `?pipeline=_none` 再试：

```powershell
curl.exe -s -X POST "http://localhost:9201/l11_shop/_update_by_query?refresh=true&pipeline=_none" `
  -H "Content-Type: application/json" `
  --data-binary @D:/projects/learning/elasticsearch/playground/l11-ubq-price.json
```

```json
{"total":2,"updated":2,...,"failures":[]}
```

**`updated: 2`，成功。** 归因确认。

数据核对：`price` 2999→3099、8999→9099，并且多出 `updated: true`。

> **生产提醒**：给索引绑 `default_pipeline` 之后，做 `_update_by_query` / `_reindex` 之前，**先想清楚 pipeline 会不会被重跑、重跑会不会出错**。需要时显式加 `?pipeline=_none`。

### 2.3 Update By Query 的常用参数

| 参数 | 作用 |
|------|------|
| `conflicts=proceed` | 遇到版本冲突**继续**（不指定的话遇冲突就中断） |
| `pipeline=_none` | 跳过 `default_pipeline` |
| `refresh=true` | 完成后立刻刷新，让改动可搜 |
| `requests_per_second` | 限速，避免打垮集群 |
| `slices` | 并行切片数，加速大索引 |
| `wait_for_completion=false` | 异步执行，返回 task id |

大索引上一定要用 `wait_for_completion=false` 拿 task id，否则 HTTP 连接可能超时。之后用 `GET /_tasks/{task_id}` 查进度。

### 2.4 Reindex：数据搬家

`_reindex` 把数据从一个索引复制到另一个索引。它的头号用途是**解决分片数不可改**——这是课 9 埋的坑，本课兑现。

思路三步：

1. 建一个新索引，分片数设成你想要的值
2. `_reindex` 把数据搬过去
3. （可选）用别名切换，让应用无感知

**第 1 步**：建目标索引（`l11_shop_v2`），分片数从 1 改成 **3**，副本从 0 改成 **1**：

```json
{
  "settings": { "number_of_shards": 3, "number_of_replicas": 1 },
  "mappings": {
    "properties": {
      "brand": { "type": "keyword" },
      "price": { "type": "integer" },
      "price_level": { "type": "keyword" },
      "stage_default": { "type": "keyword" },
      "migrated_from": { "type": "keyword" },
      "updated": { "type": "boolean" }
    }
  }
}
```

**第 2 步**：搬运，顺便用 script 打个标记：

```json
{
  "source": { "index": "l11_shop" },
  "dest": { "index": "l11_shop_v2" },
  "script": { "source": "ctx._source.migrated_from = 'l11_shop'" }
}
```

```powershell
curl.exe -s -X POST "http://localhost:9201/_reindex?refresh=true" `
  -H "Content-Type: application/json" `
  --data-binary @D:/projects/learning/elasticsearch/playground/l11-reindex-basic.json
```

**实测结果**：

```json
{"total":3,"updated":0,"created":3,"deleted":0,"batches":1,...,"failures":[]}
```

| 索引 | 主分片 | 副本 | 文档数 |
|------|--------|------|--------|
| `l11_shop`（源） | 1 | 0 | 3 |
| `l11_shop_v2`（目标） | **3** | **1** | 3 |

**分片数真的改了。** 这就是课 9 那句"除非 reindex"的兑现。

### 2.5 Reindex 的进阶用法

**只搬一部分**：加 `query`

```json
{
  "source": {
    "index": "l11_shop",
    "query": { "range": { "price": { "gte": 5000 } } }
  },
  "dest": { "index": "l11_shop_expensive" }
}
```

**跨集群搬**：需要先把远程集群加到 `reindex.remote.whitelist`

```json
{
  "source": {
    "remote": { "host": "http://other-host:9200" },
    "index": "source_index"
  },
  "dest": { "index": "local_copy" }
}
```

**改名搬**（边搬边改字段）：

```json
{
  "source": { "index": "old_index" },
  "dest": { "index": "new_index" },
  "script": {
    "source": "ctx._source.new_field = ctx._source.remove('old_field')"
  }
}
```

**无停机切换**（生产必用）：

```powershell
# 1. 搬到新索引
# 2. 原子切换别名
curl.exe -s -X POST "http://localhost:9201/_aliases" -H "Content-Type: application/json" --data-binary @switch_alias.json
```

`switch_alias.json`：

```json
{
  "actions": [
    { "remove": { "index": "l11_shop", "alias": "shop_current" } },
    { "add": { "index": "l11_shop_v2", "alias": "shop_current" } }
  ]
}
```

这样应用代码一直用 `shop_current`，切换瞬间完成，零停机。

### 2.6 Reindex 的重要提醒

| 事项 | 说明 |
|------|------|
| **不复制 settings/mappings** | 只搬文档。目标索引的 mapping 要**自己先建好** |
| **默认不覆盖** | 目标索引已有同 `_id` 文档时，按 `version_type` 处理 |
| **`op_type: create`** | 只创建不更新，适合纯增量 |
| **`size` 分批** | 大索引用 `size` 控制每批条数，配合 `slices` 并行 |
| **搬运期间源数据变化** | 不会自动同步。要一致性得先停写，或用 PIT（课 7 讲过） |

---

## 知识点 3 · 快照与恢复：唯一不丢数据的退路

### 3.1 为什么副本不算备份

先复习课 10 的决定性实验：我停掉 node-3 后**移走整个 data 目录**（模拟硬盘报废），结果——

| 索引 | 销毁前 | 销毁后 | 副本数 |
|------|--------|--------|--------|
| `l9_hi` | 300 | **197** | 0 |
| `l9_trap2` | 1245 | **830** | 0 |
| `l9_orders` | 22 | **22** | 1 |

0 副本的分片**永久丢失**，1 副本的一条没少。

**但副本救不了这些情况**：

- **人为删除**：`DELETE /orders` 会同步到所有副本
- **误更新**：批量改错了数据，副本跟着一起错
- **整组节点故障**：副本都在这个集群里

ES 官方在 `_cluster/allocation/explain` 的报错里给了明确建议（课 10 实测原文）：

> `no_valid_shard_copy` — "there are no copies of its data in the cluster ... If no such node is available, **restore this index from a recent snapshot**"

**快照 ≠ 副本。** 副本是"同一份数据的多个实时拷贝"，快照是"某个时点的历史存档"。

### 3.2 第一步：注册仓库（Repository）

快照不是直接写到某个目录，而是先注册一个**仓库（repository）**，再把快照放进仓库。

**本机前提**：`fs` 类型仓库要求 `path.repo` 配置在 `elasticsearch.yml` 里，且**必须重启节点才生效**。

我的 3 节点集群配置（`l9-cluster/node-X/config/elasticsearch.yml`）追加：

```yaml
# 课 11 快照仓库（修改后须重启节点生效）
path.repo: [D:/projects/learning/elasticsearch/playground/snapshots]
```

> **Windows 路径**：用正斜杠 `/`。反斜杠在 YAML 里是转义符，会被吃。

**不重启直接注册，会被拒绝**（实测原文）：

```json
{
  "error": {"root_cause":[{"type":"repository_exception",
    "reason":"[l11_repo] location [l11_backup] doesn't match any of the locations specified by path.repo because this setting is empty"}]},
  "status":500
}
```

注意那句 **`because this setting is empty`**——配置已经写进文件了，但不重启就读不到。

重启集群（本课脚本 `playground/l11-restart-cluster.ps1`）后，注册仓库：

```json
{
  "type": "fs",
  "settings": {
    "location": "l11_backup",
    "compress": true
  }
}
```

```powershell
curl.exe -s -X PUT "http://localhost:9201/_snapshot/l11_repo" `
  -H "Content-Type: application/json" `
  --data-binary @D:/projects/learning/elasticsearch/playground/l11-repo.json
```

返回 `{"acknowledged":true}`。

**注意 `location` 是相对路径**——它相对于 `path.repo` 里配的目录。最终物理位置是：

```
D:/projects/learning/elasticsearch/playground/snapshots/l11_backup
```

**校验所有节点都能访问**（多节点集群必做）：

```powershell
curl.exe -s -X POST "http://localhost:9201/_snapshot/l11_repo/_verify"
```

实测返回三个节点全部通过：

```json
{"nodes":{"4n8w_...":{"name":"node-1"},"J8hn...":{"name":"node-2"},"GjqD...":{"name":"node-3"}}}
```

> 如果有节点访问不到（比如只在一台机器上挂了 NFS），这里会报错。这是多节点集群最常见的快照故障。

### 3.3 仓库类型有哪些

本机 9.5.1 官方 zip 实测探测结果：

| 类型 | 是否内置 | 用途 |
|------|----------|------|
| `fs` | ✅ | 共享文件系统（**本课用这个**） |
| `url` | ✅ | **只读**仓库，可指向 `file://`、`http://`、`https://` |
| `s3` | ✅ | AWS S3 |
| `gcs` | ✅ | Google Cloud Storage |
| `azure` | ✅ | Azure Blob Storage |
| `source` | ✅ | 只读"源仓库"（跨版本迁移用） |
| `hdfs` | ❌ | **不支持**（新版已移除） |

生产环境基本都用 `s3` / `gcs` / `azure` ——因为它们在**集群之外**。

### 3.4 第二步：创建快照

```json
{
  "indices": "l11_shop_v2,l9_orders",
  "ignore_unavailable": true,
  "include_global_state": false,
  "metadata": {
    "taken_by": "lesson-11",
    "reason": "verify snapshot restore"
  }
}
```

```powershell
curl.exe -s -X PUT "http://localhost:9201/_snapshot/l11_repo/snap_1?wait_for_completion=true" `
  -H "Content-Type: application/json" `
  --data-binary @D:/projects/learning/elasticsearch/playground/l11-snap-1.json
```

**实测返回**：

```json
{
  "snapshot": {
    "snapshot": "snap_1", "repository": "l11_repo",
    "indices": ["l11_shop_v2", "l9_orders"],
    "state": "SUCCESS",
    "shards": {"total": 6, "failed": 0, "successful": 6}
  }
}
```

**关键参数**：

| 参数 | 说明 |
|------|------|
| `indices` | 要备份哪些索引（支持通配符 `log-*`） |
| `ignore_unavailable` | 索引不存在时不报错 |
| `include_global_state` | **是否备份集群级配置**（模板、ILM 策略等）。`false` = 只备份数据 |
| `metadata` | 自定义备注，可写备份原因、备份人 |
| `wait_for_completion` | `true` 同步等完成；大集群用 `false` 异步 |

> **`include_global_state` 的选择**：跨集群恢复时（比如从生产恢复到测试），通常设 `false`，避免把生产的集群配置覆盖到测试环境。

### 3.5 第三步：删除 + 恢复（本课核心一战）

现在做课 10 没做成的事：**删掉索引，然后从快照恢复**。

```powershell
# 删掉（模拟数据丢失）
curl.exe -s -X DELETE "http://localhost:9201/l11_shop_v2"
curl.exe -s -X DELETE "http://localhost:9201/l9_orders"
```

确认真的没了：

```json
{"error":{"type":"index_not_found_exception","reason":"no such index [l11_shop_v2]"},"status":404}
```

这就是课 10 里那种绝望场景——数据没了，而且没有副本可以救。

**恢复**：

```json
{
  "indices": "l11_shop_v2,l9_orders",
  "ignore_unavailable": true,
  "include_global_state": false
}
```

```powershell
curl.exe -s -X POST "http://localhost:9201/_snapshot/l11_repo/snap_1/_restore?wait_for_completion=true" `
  -H "Content-Type: application/json" `
  --data-binary @D:/projects/learning/elasticsearch/playground/l11-restore-1.json
```

**实测结果**：

```json
{"snapshot":{"snapshot":"snap_1","indices":["l9_orders","l11_shop_v2"],
  "shards":{"total":6,"failed":0,"successful":6}}}
```

| 索引 | 删除前 | 恢复后 | 分片配置 |
|------|--------|--------|----------|
| `l11_shop_v2` | 3 | **3** | 3 主 1 副（原样） |
| `l9_orders` | 23 | **23** | 3 主 1 副（原样） |

**一条不差，全回来了。**

### 3.6 恢复的不只是条数，内容也完整

光看条数不够。查内容：

```
price_level: "low"     price: 0      migrated_from: "l11_shop"   brand: "HUAWEI"
price_level: "low"     price: 3099   migrated_from: "l11_shop"   brand: "XIAOMI"   updated: true
price_level: "high"    price: 9099   migrated_from: "l11_shop"   brand: "APPLE"    updated: true
```

**三个实验的痕迹一层不落**：

- `migrated_from` —— `_reindex` 打的标记在
- `updated: true` —— `_update_by_query` 打的标记在
- `brand` 全大写 —— pipeline 的 `uppercase` 在
- `price` 3099/9099 —— 加价后的值在
- `price_level` —— script 算出的标签在

**完整链路**：pipeline 加工 → update_by_query 改价 → reindex 迁移 → 快照 → 删除 → 恢复，每一步的痕迹都在。

### 3.7 增量快照：为什么它不占地方

你可能担心：每天做一次快照，那数据量岂不是翻着倍涨？

不会。快照是**增量**的。

**物理证据**（实测的仓库目录结构）：

```
l11_backup/
├── index-3                      ← 仓库索引
├── index.latest
├── meta-9uP5sZ...dat            ← snap_2 的元数据
├── meta-B0DuH-r...dat           ← snap_4 的元数据
├── meta-ilGQzqd...dat           ← snap_3 的元数据
├── meta-rTrC41s...dat           ← snap_1 的元数据
├── snap-9uP5sZ....dat
├── snap-B0DuH-r....dat
├── snap-ilGQzqd....dat
├── snap-rTrC41s....dat
└── indices/
    └── 3ILORzWTRQ-zLJGqP7hrfQ/          ← 某个索引
        ├── 0/  ← 分片 0
        │   ├── snap-9uP5sZ...dat        ← 各快照的分片元数据
        │   ├── snap-B0DuH-r...dat
        │   ├── snap-ilGQzqd...dat
        │   ├── snap-rTrC41s...dat
        │   ├── __3NAHMyhQRv2gv7-L-k869w  ← 共享的数据段
        │   ├── __6P8cwkR6QLO5p9Uo6WMkNw
        │   ├── __VBxoedQrT0WLkwB6vudjJQ
        │   └── ...
        ├── 1/
        └── 2/
```

**关键观察**：

- 每个快照有自己的 `snap-*.dat`（1–1.5 KB 的元数据）
- `__` 开头的文件是**实际数据段**
- **多个快照共享同一批 `__` 文件**

**行为验证**：先记下仓库大小，然后删掉最早的 `snap_1`：

| 操作 | 仓库大小 |
|------|----------|
| 删 `snap_1` 之前 | 106.7 KB |
| 删 `snap_1` 之后 | **83.3 KB** |
| 释放 | **23.4 KB** |

只回收了 23.4 KB。而 `l11_shop_v2` + `l9_orders` 的数据远不止这点——说明**后面的快照在复用 `snap_1` 留下的数据段**。

> 这个数字是**那一时刻的实测值**。后来 SLM 又自动生成了新快照，仓库涨到 93.5 KB。**看增量的比例（23.4 / 106.7 ≈ 22%），别看绝对值。**

### 3.8 删掉旧快照，新快照还能用吗？

这是最反直觉、也最让人担心的一点。实测：

```powershell
# 已删除 snap_1，现在从 snap_4 恢复
curl.exe -s -X POST "http://localhost:9201/_snapshot/l11_repo/snap_4/_restore?wait_for_completion=true" `
  -H "Content-Type: application/json" `
  --data-binary @D:/projects/learning/elasticsearch/playground/l11-restore-snap4.json
```

**结果**：恢复出 **24 条**，数据完整。

| 索引 | 文档数 | 说明 |
|------|--------|------|
| `l9_orders` | 24 | 当前状态 |
| `l9_orders_snap3` | **23** | 从 snap_3 恢复（那个时点） |
| `l9_orders_after_del` | **24** | 删掉 snap_1 后，从 snap_4 恢复 |

**结论**：每个快照**逻辑上都是完整的**，物理上共享不变的数据段。ES 会自动维护引用计数——只要还有快照在用某个数据段，它就不会被删。

> 这也是为什么可以放心地用 `retention` 策略自动清理旧快照。

### 3.9 SLM：让备份自动跑起来

手动做快照会忘。ES 内置了 **SLM（Snapshot Lifecycle Management）** 来自动化。

```json
{
  "schedule": "0 */30 * * * ?",
  "name": "<l11-daily-snap-{now/d}>",
  "repository": "l11_repo",
  "config": {
    "indices": ["l9_orders"],
    "ignore_unavailable": true,
    "include_global_state": false
  },
  "retention": {
    "expire_after": "7d",
    "min_count": 3,
    "max_count": 10
  }
}
```

```powershell
curl.exe -s -X PUT "http://localhost:9201/_slm/policy/l11_daily" `
  -H "Content-Type: application/json" `
  --data-binary @D:/projects/learning/elasticsearch/playground/l11-slm-policy.json
```

**几个要点**：

| 字段 | 说明 |
|------|------|
| `schedule` | Cron 表达式。`0 */30 * * * ?` = 每 30 分钟 |
| `name` | 快照名模板。`<...{now/d}...>` 会被替换成日期 |
| `retention.expire_after` | 保留多久 |
| `retention.min_count` | **至少保留几个**（防止全被删光） |
| `retention.max_count` | 最多保留几个 |

> `min_count` 很重要：即使 `expire_after` 到期，也会保证留下至少这么多个快照。

**创建后查看**（实测）：

```json
{
  "l11_daily": {
    "policy": { "name": "<l11-daily-snap-{now/d}>", "schedule": "0 */30 * * * ?", ... },
    "next_execution_millis": 1788174000000,
    "stats": { "snapshots_taken": 0, "snapshots_failed": 0, ... }
  }
}
```

**手动触发一次**：

```powershell
curl.exe -s -X POST "http://localhost:9201/_slm/policy/l11_daily/_execute"
```

返回：

```json
{"snapshot_name":"l11-daily-snap-2026.08.31-b78gvwsxrz6tkf3una6eaw"}
```

**自动命名生效**：`{now/d}` 变成了 `2026.08.31`，后缀 `b78gvwsxrz6tkf3una6eaw` 是防重随机串（同一天多次执行也不会撞名）。

> **意外收获**：我在实验期间没有手动干预，SLM **自动又跑了一次**，生成了 `l11-daily-snap-2026.08.31-xbzjlql4syygqo6uatqwuw`（10:59:59，正好是策略设定的整半点）。这额外验证了定时调度真的在工作。

**手动执行 retention 清理**：

```powershell
curl.exe -s -X POST "http://localhost:9201/_slm/_execute_retention"
```

### 3.10 跨集群恢复：整机烧毁的真正答案

现在回答课 10 结尾的问题：**机器全烧了，备份还在吗？**

**取决于快照存在哪。** 我这个 `fs` 仓库：

```
数据目录: D:/projects/learning/elasticsearch/playground/l9-cluster/node-X/data
快照目录: D:/projects/learning/elasticsearch/playground/snapshots/l11_backup
```

**都在 D 盘。** 盘坏了，数据和备份一起没。

**真正的解法**：把快照放到**另一个集群也能访问的地方**。本课用两个集群实测：

| 集群 | 地址 | 说明 |
|------|------|------|
| 集群 A（源） | `http://localhost:9201` | `l9-cluster`，3 节点 |
| 集群 B（目标） | `https://localhost:9200` | 单节点，开启了安全认证 |

两个集群的 `path.repo` 都指向同一个目录。在集群 B 注册同名仓库：

```powershell
curl.exe -s -k -u elastic:<密码> -X PUT "https://localhost:9200/_snapshot/l11_repo" `
  -H "Content-Type: application/json" `
  --data-binary @D:/projects/learning/elasticsearch/playground/l11-repo.json
```

**集群 B 能看到集群 A 创建的全部快照**（实测）：

```
id                                                status
snap_2                                           SUCCESS
snap_3                                           SUCCESS
snap_4                                           SUCCESS
l11-daily-snap-2026.08.31-b78gvwsxrz6tkf3una6eaw SUCCESS
l11-daily-snap-2026.08.31-xbzjlql4syygqo6uatqwuw SUCCESS
```

**执行跨集群恢复**：

```json
{
  "indices": "l9_orders",
  "ignore_unavailable": true,
  "include_global_state": false,
  "rename_pattern": "l9_orders",
  "rename_replacement": "restored_on_9200"
}
```

```powershell
curl.exe -s -k -u elastic:<密码> -X POST "https://localhost:9200/_snapshot/l11_repo/snap_4/_restore?wait_for_completion=true" `
  -H "Content-Type: application/json" `
  --data-binary @D:/projects/learning/elasticsearch/playground/l11-restore-cross.json
```

**实测结果**：

```json
{"snapshot":{"snapshot":"snap_4","indices":["restored_on_9200"],
  "shards":{"total":3,"failed":0,"successful":3}}}
```

| 项目 | 结果 |
|------|------|
| 恢复前 9200 上有没有这个索引 | 没有 |
| 恢复后 | **`restored_on_9200`，24 条，3 主 1 副** |

内容抽样（连 `_id` 都原样保留）：

```
_id: "Pj1oV6ABHncISD6JEHB5"   order_no: "L11-NEW-001"   brand: "Apple"   price: 12999
```

**这就是答案**：数据从集群 A 的快照，恢复到了**完全另一个集群**。只要快照在集群之外（另一台机器、NAS、对象存储），原集群整个烧掉也不怕。

### 3.11 rename_pattern：恢复到新名字

上面用了 `rename_pattern` + `rename_replacement`，作用是把恢复出来的索引用**新名字**，避免覆盖现有的同名索引。

| 场景 | 用法 |
|------|------|
| 原样恢复 | 不加这两个参数 |
| 恢复成新索引 | `rename_pattern: "原索引名"`，`rename_replacement: "新索引名"` |
| 批量加前缀 | `rename_pattern: "(.+)"`，`rename_replacement: "restored_$1"` |
| 批量去前缀 | `rename_pattern: "log-(.+)"`，`rename_replacement: "$1"` |

> **生产建议**：恢复前先用 rename 恢复到一个临时索引，核对无误后再切换别名。直接覆盖同名索引风险太高。

### 3.12 只读仓库：一份快照，多个环境

`url` 类型仓库是**只读**的，适合"拿同一份快照恢复多个环境"。

```json
{
  "type": "url",
  "settings": {
    "url": "file:///D:/projects/learning/elasticsearch/playground/snapshots/l11_backup"
  }
}
```

**实测**：

```powershell
# 能读
curl.exe -s -k -u elastic:<密码> "https://localhost:9200/_cat/snapshots/l11_readonly?v"
# → 列出全部 5 个快照

# 不能写
curl.exe -s -k -u elastic:<密码> -X PUT "https://localhost:9200/_snapshot/l11_readonly/should_fail?wait_for_completion=true" ...
# → {"error":{"reason":"[l11_readonly] cannot create snapshot in a readonly repository"},"status":400}
```

**用途**：给测试/开发环境挂一份生产快照的只读副本，让他们能恢复数据，但不能往里写、更不能删。

### 3.13 快照的常见坑

| 坑 | 现象 | 解法 |
|----|------|------|
| `path.repo` 没配或没重启 | `location [...] doesn't match ... because this setting is empty` | 配好 yml 后**重启所有节点** |
| 节点访问不到共享路径 | `_verify` 只返回部分节点 | 检查挂载/权限，每个节点都要能访问 |
| 恢复时索引已存在 | 报 `index already exists` | 先删，或用 `rename_pattern` 改名 |
| 快照进行中又发起一个 | 报 `concurrent snapshot execution` | 等，或换仓库 |
| 跨大版本恢复 | 不兼容 | 官方支持**相邻一个大版本**；跨版本用 `source` 只读仓库 |
| 忘记 `include_global_state` | 恢复了数据但模板没了 | 需要模板就设 `true` |

---

### 第四幕 · 实操验证：本课完整命令清单

> 所有命令在 Windows PowerShell + `curl.exe` 下实测通过。JSON 一律用文件传参。

**准备：JSON 文件**（都在 `D:/projects/learning/elasticsearch/playground/`）

| 文件 | 用途 |
|------|------|
| `l11-sim-basic.json` | 四件套 processor 模拟 |
| `l11-sim-grok.json` | grok 解析 Apache 日志 |
| `l11-sim-onfailure.json` | on_failure 死信队列 |
| `l11-pipeline-main.json` | 正式 pipeline 定义 |
| `l11-index-shop.json` | 绑定 default_pipeline 的索引 |
| `l11-bulk-docs.ndjson` | 3 条测试文档（含脏数据） |
| `l11-ubq-price.json` | update_by_query 批量改价 |
| `l11-shop-v2.json` | 目标索引（3 分片 1 副本） |
| `l11-reindex-basic.json` | reindex 请求 |
| `l11-repo.json` | fs 类型仓库定义 |
| `l11-snap-1.json` / `l11-snap-2.json` | 创建快照 |
| `l11-restore-1.json` | 恢复快照 |
| `l11-restore-rename.json` | 恢复并改名 |
| `l11-slm-policy.json` | SLM 策略 |
| `l11-repo-url.json` | url 只读仓库 |

**步骤 1：模拟跑通 Pipeline**

```powershell
curl.exe -s -X POST "http://localhost:9201/_ingest/pipeline/_simulate?verbose" -H "Content-Type: application/json" --data-binary @D:/projects/learning/elasticsearch/playground/l11-sim-basic.json
```

**步骤 2：建 Pipeline 并写数据**

```powershell
curl.exe -s -X PUT "http://localhost:9201/_ingest/pipeline/l11_main" -H "Content-Type: application/json" --data-binary @D:/projects/learning/elasticsearch/playground/l11-pipeline-main.json

curl.exe -s -X PUT "http://localhost:9201/l11_shop" -H "Content-Type: application/json" --data-binary @D:/projects/learning/elasticsearch/playground/l11-index-shop.json

curl.exe -s -X POST "http://localhost:9201/_bulk?refresh=true" -H "Content-Type: application/x-ndjson" --data-binary @D:/projects/learning/elasticsearch/playground/l11-bulk-docs.ndjson
```

**步骤 3：踩一遍 update_by_query 的坑**

```powershell
# 会失败（default_pipeline 被重跑）
curl.exe -s -X POST "http://localhost:9201/l11_shop/_update_by_query?refresh=true&conflicts=proceed" -H "Content-Type: application/json" --data-binary @D:/projects/learning/elasticsearch/playground/l11-ubq-price.json

# 加 pipeline=_none 后成功
curl.exe -s -X POST "http://localhost:9201/l11_shop/_update_by_query?refresh=true&pipeline=_none" -H "Content-Type: application/json" --data-binary @D:/projects/learning/elasticsearch/playground/l11-ubq-price.json
```

**步骤 4：reindex 改分片数**

```powershell
curl.exe -s -X PUT "http://localhost:9201/l11_shop_v2" -H "Content-Type: application/json" --data-binary @D:/projects/learning/elasticsearch/playground/l11-shop-v2.json

curl.exe -s -X POST "http://localhost:9201/_reindex?refresh=true" -H "Content-Type: application/json" --data-binary @D:/projects/learning/elasticsearch/playground/l11-reindex-basic.json

curl.exe -s "http://localhost:9201/_cat/indices/l11_shop*?v&h=index,pri,rep,docs.count"
```

**步骤 5：配 path.repo 并重启集群**

在三个节点的 `elasticsearch.yml` 追加：

```yaml
path.repo: [D:/projects/learning/elasticsearch/playground/snapshots]
```

```powershell
powershell -ExecutionPolicy Bypass -File D:/projects/learning/elasticsearch/playground/l11-restart-cluster.ps1
```

**步骤 6：注册仓库 + 校验**

```powershell
curl.exe -s -X PUT "http://localhost:9201/_snapshot/l11_repo" -H "Content-Type: application/json" --data-binary @D:/projects/learning/elasticsearch/playground/l11-repo.json

curl.exe -s -X POST "http://localhost:9201/_snapshot/l11_repo/_verify"
```

**步骤 7：快照 → 删除 → 恢复**

```powershell
curl.exe -s -X PUT "http://localhost:9201/_snapshot/l11_repo/snap_1?wait_for_completion=true" -H "Content-Type: application/json" --data-binary @D:/projects/learning/elasticsearch/playground/l11-snap-1.json

curl.exe -s -X DELETE "http://localhost:9201/l11_shop_v2"
curl.exe -s -X DELETE "http://localhost:9201/l9_orders"

curl.exe -s -X POST "http://localhost:9201/_snapshot/l11_repo/snap_1/_restore?wait_for_completion=true" -H "Content-Type: application/json" --data-binary @D:/projects/learning/elasticsearch/playground/l11-restore-1.json

curl.exe -s "http://localhost:9201/_cat/indices/l11_shop_v2,l9_orders?v&h=index,pri,rep,docs.count"
```

**步骤 8：SLM 自动化**

```powershell
curl.exe -s -X PUT "http://localhost:9201/_slm/policy/l11_daily" -H "Content-Type: application/json" --data-binary @D:/projects/learning/elasticsearch/playground/l11-slm-policy.json

curl.exe -s -X POST "http://localhost:9201/_slm/policy/l11_daily/_execute"

curl.exe -s "http://localhost:9201/_cat/snapshots/l11_repo?v"
```

**步骤 9：跨集群恢复**

```powershell
curl.exe -s -k -u elastic:<密码> -X PUT "https://localhost:9200/_snapshot/l11_repo" -H "Content-Type: application/json" --data-binary @D:/projects/learning/elasticsearch/playground/l11-repo.json

curl.exe -s -k -u elastic:<密码> -X POST "https://localhost:9200/_snapshot/l11_repo/snap_4/_restore?wait_for_completion=true" -H "Content-Type: application/json" --data-binary @D:/projects/learning/elasticsearch/playground/l11-restore-cross.json

curl.exe -s -k -u elastic:<密码> "https://localhost:9200/_cat/indices/restored_on_9200?v&h=index,pri,rep,docs.count"
```

---

### 第五幕 · 体系收束

## 本课知识地图

![课11知识地图](../../stages/4-分布式与工程实践/assets/data-pipeline-backup.svg)

**三个知识点，一条主线**：

```
数据进来 → Ingest Pipeline 加工好
          ↓
发现问题 → Update By Query 批量改
          ↓
结构不对 → Reindex 搬到新索引
          ↓
日常运行 → SLM 自动做快照
          ↓
出事了   → 快照恢复（可跨集群）
```

## 三条原理句（记住这三句就够了）

**① Pipeline 改的是 `_source` 本身，不是只改索引。**
这就解释了为什么 `_update_by_query` 重跑 pipeline 会炸——它要读的字段可能早被上一轮 `remove` 掉了。

**② Reindex 是改分片数的唯一途径，但它不搬 mapping。**
目标索引的 mapping 要自己先建好。生产上用别名做零停机切换。

**③ 快照是唯一能对抗"人为删除"的手段，前提是它存在集群之外。**
副本防的是硬件故障，快照防的是人为错误。而放在同一块盘的快照，等于没备份。

## 与前后课的联系

| 关联 | 说明 |
|------|------|
| ← 课 5 映射 | Pipeline 的 `convert` 解决的是"映射错了要重来"的问题 |
| ← 课 7 PIT | 大索引 reindex 要保证一致性时，用 PIT 而非普通 scroll |
| ← 课 9 分片 | "分片数不可改，除非 reindex"在本课兑现 |
| ← 课 10 排障 | "restore from a recent snapshot" 是本课的直接起点 |
| → 课 12 接入真实项目 | 数据同步模式会用到本课的全部三种手段 |
| → 课 13 日志场景 | Ingest Pipeline + 索引模板是日志场景的标准组合 |

## 认证考点映射

| 知识点 | 认证域 | 考点 |
|--------|--------|------|
| Ingest Pipeline | Data Processing | 建 pipeline、用 `_simulate` 调试、`on_failure` 处理 |
| Reindex / Update By Query | Data Processing | reindex 改分片、跨索引搬运、script 改写 |
| 快照与恢复 | Cluster Admin | 注册仓库、创建/恢复快照、SLM 策略 |

## 速查卡

| 操作 | 命令 |
|------|------|
| 模拟 pipeline | `POST /_ingest/pipeline/_simulate?verbose` |
| 建 pipeline | `PUT /_ingest/pipeline/<name>` |
| 查 pipeline | `GET /_ingest/pipeline/<name>` |
| 删 pipeline | `DELETE /_ingest/pipeline/<name>` |
| 批量更新 | `POST /<index>/_update_by_query?pipeline=_none` |
| 重建索引 | `POST /_reindex` |
| 查任务进度 | `GET /_tasks/<task_id>` |
| 注册仓库 | `PUT /_snapshot/<repo>` |
| 校验仓库 | `POST /_snapshot/<repo>/_verify` |
| 建快照 | `PUT /_snapshot/<repo>/<snap>?wait_for_completion=true` |
| 看快照列表 | `GET /_cat/snapshots/<repo>?v` |
| 恢复快照 | `POST /_snapshot/<repo>/<snap>/_restore` |
| 删快照 | `DELETE /_snapshot/<repo>/<snap>` |
| 建 SLM 策略 | `PUT /_slm/policy/<name>` |
| 手动跑 SLM | `POST /_slm/policy/<name>/_execute` |
| 执行保留策略 | `POST /_slm/_execute_retention` |
| 查孤儿分片 | `GET /_dangling` |
| 恢复孤儿分片 | `POST /_dangling/<uuid>?accept_data_loss=true` |

## 踩坑记录（全部本课实测）

| # | 坑 | 现象 | 解法 |
|---|-----|------|------|
| 1 | **`_update_by_query` 重跑 `default_pipeline`** | `field [xxx] not present`，`updated: 0` | 加 `?pipeline=_none` |
| 2 | **PowerShell 内联 JSON 双引号被吃** | `was expecting double-quote to start field name` | 用 `--data-binary @文件.json` |
| 3 | **`path.repo` 改了不重启无效** | `... because this setting is empty` | 重启**所有**节点 |
| 4 | **grok 不匹配会拒收整篇文档** | `Provided Grok expressions do not match field value` | 用 `on_failure` 转死信索引 |
| 5 | **快照放在数据同盘** | 盘坏则数据和备份一起没 | 用 S3/GCS/Azure 或独立存储 |
| 6 | **误以为删旧快照会弄坏新快照** | — | 不会。ES 维护引用计数，实测删 `snap_1` 后 `snap_4` 恢复仍完整 |
| 7 | **bulk 文件最后一行没换行** | 最后一条被忽略 | ndjson 每行（含最后一行）都要 `\n` |
| 8 | **多节点仓库只在一台机上挂载** | `_verify` 只返回部分节点 | 每个节点都要能访问同一路径 |
| 9 | **跳步执行导致索引不存在** | `no such index [l11_shop]` | 2.x 节依赖 1.8 节建的索引和数据，别跳步 |
| 10 | **快照仓库大小是时点值** | 隔一段时间再看数字变了 | 看增量比例（约 22%），别看绝对值 |

## 一个真实事故，以及它教给我的事

本课实验中，我要给单节点集群（9200）配 `path.repo`。启动时发现它起不来，查日志发现——**它的配置文件整个是 node-3 的配置**（`cluster.name: l9-cluster`、`http.port: 9203`）。

这是课 9 建 3 节点集群时，把 9200 那个目录原地改造成 node-3 留下的后遗症。我重写配置后启动，又撞上 `CorruptStateException`——集群元数据被污染了。

**处理过程**（这几步值得记住）：

1. **先备份，再动手** —— 把整个 `data` 目录 robocopy 了一份（0.64 MB，417 个文件）
2. **定位到是元数据坏了，不是数据坏了** —— `_state` 目录损坏，但 `indices/` 下 19 个索引的分片完好
3. **清空 `_state`，让 ES 以空元数据启动** —— 成功了
4. **用 `_dangling` 找回孤儿分片** —— 19 个索引全列出来了
5. **逐个 `POST /_dangling/<uuid>?accept_data_loss=true` 恢复** —— `l6_shop` 8 条、`l7_news` 6 条、`l8_orders` 24 条、全部与档案记录一致

**这件事给我的三个教训**：

- **备份的价值在于"出问题前就有"**。这次能救回来，纯粹因为我先做了完整备份。
- **元数据坏了不等于数据坏了**。`_dangling` 是快照之外的另一条补救路径，值得记住。
- **改动共享环境前，先确认它当前是什么状态**。我以为 9200 还是单节点，实际它的配置早已被改掉。

---

## 🚀 下一批接力提示词

> 复制下面这段文字发给 AI，即可从下一个未完成知识点继续（无需重新描述上下文）：

```
继续学 Elasticsearch。我的学习档案在 elasticsearch/00-学习档案.md，
刚学完阶段 4《分布式与工程实践》课 11《数据管道与备份》的三个知识点
（Ingest Pipeline / Reindex 与 Update By Query / 快照与恢复）。

本机环境：
- 3 节点学习集群在 http://localhost:9201（node-1/9201, node-2/9202, node-3/9203，
  cluster.name=l9-cluster，已关闭安全，数据在 playground/l9-cluster/）
  当前 green，主节点 node-2；三节点均已配置 path.repo
  实测索引：l9_trap2（1287 条）、l9_orders（24 条）、l9_hi（300 条）、
  l10_shard_1/3/50（各 3000 条）、l11_shop_v2（3 条）
- 单节点集群在 https://localhost:9200（**密码已重置为 9PvhcGNNc86uFZb_ePAN**，
  与档案记录的 ESlearn2026 不同；IK 9.5.1 已装；配置已修复为单节点并配了 path.repo）
  实测索引：l6_shop（8）、l7_news（6）、l8_orders（24）、l8_orders_v2（24）、
  l8_text_demo（24）、news_ik（5）
- 快照仓库 l11_repo（fs 类型）在 playground/snapshots/l11_backup，
  两个集群的 path.repo 都指向 playground/snapshots，已有 snap_2/3/4 及两个 SLM 自动快照
- 课 11 实测结论：Pipeline 改的是 _source 本身；_update_by_query 默认重跑
  default_pipeline，须加 ?pipeline=_none；reindex 是改分片数的唯一途径（1片→3片实测成功）；
  快照恢复后数据与分片配置原样还原（l11_shop_v2 3 条、l9_orders 23 条）；
  snap_1 删掉后 snap_4 仍完整恢复（增量+引用计数）；跨集群恢复成功（9201 快照→9200 集群，24 条）；
  SLM 自动生成带日期的快照名并定时执行；url 只读仓库可读不可写；
  本机内置 fs/url/s3/gcs/azure/source 仓库类型，hdfs 不支持

请按大纲继续讲解课 12《接入真实项目》。
```

---

## 🧭 课程导航

| 导航 | 链接 |
|------|------|
| ← 上一课 | [课10 集群健康与排障](lesson-10-集群健康与排障.md) |
| → 下一课 | 课12 接入真实项目（未编写） |
| ↑ 阶段概览 | [阶段 4：分布式与工程实践](../overview.md) |
| ↑ 课程目录 | [02-课程目录.md](../../02-课程目录.md) |
| ↑ 学习档案 | [00-学习档案.md](../../00-学习档案.md) |
