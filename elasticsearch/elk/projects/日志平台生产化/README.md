# 结课综合实战 · 日志平台生产化

> ELK 教程（4 阶段 / 12 课 / 36 知识点）的**跨阶段整合**验收项目。
> 版本基线 **Elastic Stack 9.5.3** ｜ 环境 **macOS arm64 + Docker Compose** ｜ 全部结论均来自**真跑实测**

---

## 一句话需求

把一台"跑着两个不同版本服务的机器"上的日志，做成一条**从文件到图表、从图表到告警、从告警到可恢复**的完整流水线——并且**这套流水线自己得能被重建**。

具体要满足：

| # | 要求 | 为什么这条要求"真" |
|---|------|------------------|
| R1 | 同一台机器上的 **app 日志有两种格式**（新版本 JSON / 老版本半结构化文本），都要能正确解析 | 真实系统的灰度期就是这样，不存在"停机改造格式" |
| R2 | **另有一路 nginx 访问日志**，格式与业务日志完全不同，不能互相污染 | 检验"多输入隔离"不是空话 |
| R3 | 日志按 **data stream + ILM** 自动滚动与过期删除，不手工算日期后缀 | 课 10 的核心能力 |
| R4 | Kibana 上能按主机下钻、看错误率；**错误激增能自动告警并落盘** | 课 11 / 课 12 的核心能力 |
| R5 | **能备份、能恢复**：既要有数据快照，也要有配置资产的重建手段 | 课 12 的生产落地 |
| R6 | 整套环境一条 `docker compose up -d` 起得来，配置是**代码**不是"点出来的" | 工程约束，也是可复现性的前提 |

---

## 覆盖知识点地图

> 这张表是"整合"的证据，不是装饰——每个知识点都能在 `实现/` 里找到**具体落点**。

### 阶段 1：全景与起步

| 知识点 | 课 | 在本项目里的落点 |
|--------|-----|-----------------|
| 日志为什么难查 | 课 1 | 造数据时刻意混杂 **70% JSON / 30% 文本**、三台"主机"加权分布（web-03 故障率翻倍），复现"同一系统里格式不统一、来源不统一"的现实 |
| ELK 四个组件各管什么 | 课 1 | `实现/docker-compose.yml` 四件套 + `实现/setup` 初始化容器，每个组件职责与端口在文件里逐条注明 |
| Component 间契约 | 课 3 | Filebeat → Logstash 走 **Lumberjack 协议 :5044**；Logstash → ES 走 **HTTP :9200**；Kibana 用 `kibana_system` 账号连 ES |
| 容器环境的观测与重建 | 课 2 | `docker compose ps` / `docker logs` / `_cat/indices` 三条观测路径贯穿全程；`docker compose down` 后命名卷保留，重建不丢数据 |

### 阶段 2：采集层 Beats

| 知识点 | 课 | 在本项目里的落点 |
|--------|-----|-----------------|
| harvester 与 input 机制 | 课 4 | `实现/filebeat.yml` 两个 `filestream` input（`shop-api-app` / `shop-api-nginx`），各自独立 id、独立路径、独立 `fields.log_type` |
| registry 与 at-least-once | 课 4 | ⚠️ 本项目**差点栽在这里**：registry 默认只在容器可写层，容器 `recreate` 后整个文件被重读 → 1000 条变 2420 条。修法见 `实现/docker-compose.yml` 的 `filebeat-registry` 命名卷 |
| 多行合并 | 课 4 | multiline pattern 写成 `^([0-9]{4}-[0-9]{2}-[0-9]{2}|\{)`——**必须同时认日期行与 JSON 行**，否则 70% 的 JSON 日志会被吞进前一条 |
| processors 轻量加工 | 课 5 | `add_fields` 打 `env` / `lesson` 两枚环境标；`drop_fields` 丢掉 `agent.ephemeral_id`、`ecs.version` 省存储 |
| 输出与背压 | 课 5 | Filebeat 输出指向 Logstash 而非直连 ES；实测中 `Failed to publish events ... connection reset by peer` 是 Logstash 重启时的正常重试，队列最终 ACK |

### 阶段 3：处理层 Logstash

| 知识点 | 课 | 在本项目里的落点 |
|--------|-----|-----------------|
| 管道结构与事件模型 | 课 7 | `实现/logstash/pipeline/shop-api.conf` 单管道 `shop-api`，`input → filter → output` 三段；`pipelines.yml` 显式声明管道 id |
| grok 解析 | 课 7 | 两条 grok：nginx 用 `%{COMMONAPACHELOG}`（ECS 模式下输出 `source.address` 等）、老版本 app 用自定义半结构化 pattern |
| date 与 mutate | 课 7 | date 把**事件时间**写进 `@timestamp`（不是采集时间）；mutate 拆两块做 add_field → convert，避免 `BigDecimal` 报错 |
| 持久化队列与 at-least-once | 课 8 | `queue.type=persisted`（经环境变量注入，不挂载 logstash.yml）——实测 Logstash 重启期间 Filebeat 报错重试、事件不丢 |
| 背压与吞吐调优 | 课 8 | `pipeline.workers=2` / `batch.size=125` / `batch.delay=50` 三兄弟写进 compose |
| 多管道与隔离 | 课 8 | 用 `pipelines.yml` 声明管道 id（本项目单管道，但保留声明以便将来拆 nginx 独立管道） |
| 该在哪处理（决策） | 课 9 | **决策点 1**（见 `设计决策.md`）：解析放在 Filebeat / Logstash / ES Ingest Pipeline 三选一，本项目选 Logstash 并说明代价 |
| ECS 字段规范 | 课 9 | 一律写 ECS 字段名：`log.level` / `host.name` / `url.path` / `http.response.status_code` / `source.address` |

### 阶段 4：存储可视化与落地

| 知识点 | 课 | 在本项目里的落点 |
|--------|-----|-----------------|
| data stream 日志配法 | 课 10 | Logstash 输出用 `data_stream => "true"` + dataset/namespace，ES 自动拼出 `logs-shopapi-default`，由 **两个 backing index 组成分代** |
| ILM 滚动与冷热 | 课 10 | 自定义策略 `shopapi-7d`：hot `rollover(1gb,1d)` → warm `forcemerge` → delete `7d`；实测 rollover 后 gen2 新数据独立成代 |
| 模板在日志场景的配法 | 课 10 | ⚠️ **本项目最凶险的坑**：自定义模板 priority=200 会顶掉内置 `logs` 模板，必须 `composed_of: [logs@mappings, logs@settings, ecs@mappings]`，否则 `log.level` 退化成 `text` → **告警永远查不到数据** |
| Data View 与 Discover | 课 11 | `实现/scripts/bootstrap.py` 用 API 建 Data View `logs-shopapi-*`（时间字段 `@timestamp`） |
| KQL 与查询过滤 | 课 11 | 所有验证查询用 KQL 等价的 bool filter：`log.level:"ERROR" and @timestamp>=now-5m` |
| Lens 与 Dashboard | 课 11 | Data View 已就绪，可在 Kibana 直接拉 4 个面板：错误率趋势 / 按主机下钻 / nginx 状态码分布 / P95 耗时 |
| 告警规则与连接器 | 课 12 | `.es-query` 规则「shopapi ERROR 激增」+ `.index` 连接器 `capstone-index`，basic 许可下唯一可用的落盘类连接器 |
| 容量、权限与备份 | 课 12 | fs 快照仓库 `capstone-fs` + 快照含 `.kibana*` 功能状态；Saved Objects 导出 / 导入演练验证"规则恢复后 `enabled=false`" |
| 该不该上 ELK（决策） | 课 12 | **决策点 2**（见 `设计决策.md`）：单机 Docker Compose vs 托管云服务 vs 换 ClickHouse/Loki，说明本项目为何这么选 |

---

## 运行方式

```bash
cd 实现

# ⓪ 首次运行：创建 .env（本目录名是中文，Compose 默认拿目录名当项目名会报
#    "project name must not be empty"，必须显式指定；.env 被全局 .gitignore 忽略，故需自建）
printf 'COMPOSE_PROJECT_NAME=elk-capstone\n' > .env

# ① 起全栈（含一次性 setup 容器：设置 kibana_system 密码）
docker compose up -d

# ② 第一次起来要等 Kibana 就绪，用这条确认（available 才行）
curl -s -u elastic:ELKlearn2026 localhost:5601/api/status | python3 -m json.tool

# ③ 造日志（600 条应用 + 400 条 nginx 访问，铺在最近 180 分钟）
python3 scripts/gen-logs.py 600 180 --nginx 400

# ④ 建 ES/Kibana 侧全部资产（ILM 策略 / 索引模板 / Data View / 连接器 / 告警规则）
python3 scripts/bootstrap.py

# ⑤ 跑通告警闭环：灌一批"此刻"的 ERROR，等 1~2 分钟
python3 scripts/gen-logs.py 40 1 --burst
curl -s -u elastic:ELKlearn2026 'localhost:9200/shopapi-alerts/_search?pretty'
```

**前提**：本机 `9200 / 5601 / 5044` 端口空着。同一教程的 `playground/07-reliability`、`playground/08-where-to-process` 会占这些端口，先 `docker compose down`（**不加 `-v`**，数据卷保留）。

**观测入口**：

| 想看什么 | 命令 / 地址 |
|---------|------------|
| 栈是否健康 | `docker compose ps` |
| 集群与分代 | `curl -s -u elastic:ELKlearn2026 'localhost:9200/_cat/indices/.ds-logs-shopapi*?v'` |
| ILM 走到哪一步 | `curl -s -u elastic:ELKlearn2026 'localhost:9200/.ds-logs-shopapi-default-*/_ilm/explain?pretty'` |
| 解析有没有失败 | 聚合 `tags` 字段，**正常应只有 `beats_input_codec_plain_applied` 一个值** |
| Logstash 管道 | `curl -s localhost:9600/_node/pipelines` |
| Kibana | <http://localhost:5601>（elastic / ELKlearn2026） |

---

## 目录说明

```
projects/日志平台生产化/
├── README.md              ← 你在这里：需求 / 知识点地图 / 运行方式
├── 设计决策.md              ← 4 个真权衡点：候选对比 → 选择 → 理由 → 代价 → 何时改选
├── 反例对照.md              ← "能跑但很糟"的写法 vs 本项目写法，逐条讲为什么糟
├── 验收清单.md              ← 18 项主验收（A-E 五组）+ 5 项进阶自测，可逐条勾选
├── assets/
│   └── data-flow-pipeline.svg   ← 数据流全链路图（泳道 + 编号步骤 + 对象形态变化）
└── 实现/                   ← 可运行的完整工程
    ├── docker-compose.yml      四件套 + setup 初始化 + 三个命名卷
    ├── filebeat.yml            两个 filestream input + multiline + processors
    ├── .env                    COMPOSE_PROJECT_NAME（中文目录名必须显式指定）
    ├── logstash/
    │   ├── config/pipelines.yml  管道声明
    │   └── pipeline/shop-api.conf 双分支解析管道（本项目的核心）
    ├── scripts/
    │   ├── gen-logs.py         造假数据：应用日志（JSON/文本混杂）+ nginx 访问日志
    │   └── bootstrap.py        把 ES/Kibana 侧配置全部代码化，可重放
    ├── logs/                   运行期：生成的日志文件（挂给 Filebeat）
    ├── es/backup/              运行期：fs 快照仓库目录
    └── kibana/                 运行期：Saved Objects 导出备份
```

> `logs/`、`es/backup/`、`kibana/*.ndjson` 是**运行期产物**，已在 `.gitignore` 中忽略；删掉后重跑第 ③ 步即可再生。

---

## 实测基线（本项目的验收依据）

> ⚠️ 下表数字来自**某一次真实运行**。造数据脚本带随机性（JSON/文本比例、主机分布、日志级别都随机），
> 你重跑时**具体数字会变，量级和"失败标签为 0"这一条不会变**——验收要看的是后者。

| 指标 | 实测值 |
|------|--------|
| 应用日志 | 600 条（约 7:3 分成 JSON 与文本两路，单次实测 427 + 173） |
| nginx 访问日志 | 400 条 |
| 落库文档总数 | **1000**（与文件行数一致） |
| **解析失败标签** | **0**（`tags` 只剩 `beats_input_codec_plain_applied`） |
| `host.name` 分布 | 三个真实主机（单次实测 web-01 374 / web-02 339 / web-03 287）—— **无容器 ID 混入** |
| 分代 | gen1 1000 条 → rollover → gen2 新数据独立成代 |
| 两代映射 | `log.level=keyword`、`host.name=keyword` —— **完全一致** |
| 告警 | 规则 `enabled`，`.index` 连接器落盘 `shopapi-alerts`，渲染出 `hit_count` / `hit_host` / `hit_level` / `hit_path` |
| 快照 | `snap-final` **SUCCESS，32/32 shards**，含 `.kibana*` 功能状态 + 两代数据流 + 全部告警实例索引 |

---

## 📚 官方文档

> 全部链接经 `curl` 实测返回 **HTTP 200**（核查于 2026-09）。

**采集层（Filebeat）**

- [filestream input 参考](https://www.elastic.co/guide/en/beats/filebeat/current/filebeat-input-filestream.html) —— 多输入 / `id` / `paths` 的配置依据
- [多行合并示例](https://www.elastic.co/guide/en/beats/filebeat/current/multiline-examples.html) —— `negate` / `match: after` 的语义（反例 ① 的病根就在这一页）

**处理层（Logstash）**

- [grok 过滤器](https://www.elastic.co/guide/en/logstash/current/plugins-filters-grok.html) —— `%{PATTERN}` 语法、`tag_on_failure`
- [mutate 过滤器](https://www.elastic.co/guide/en/logstash/current/plugins-filters-mutate.html) —— `add_field` 的执行顺序与"追加而非覆盖"语义（反例 ④ 的依据）
- [date 过滤器](https://www.elastic.co/guide/en/logstash/current/plugins-filters-date.html) —— `timezone` 校准事件时间
- [持久化队列](https://www.elastic.co/guide/en/logstash/current/persistent-queues.html) —— `queue.type: persisted` 与 at-least-once

**存储层（Elasticsearch）**

- [Data stream 参考](https://www.elastic.co/guide/en/elasticsearch/reference/current/data-streams.html) —— 命名规则与"只能追加"的约束
- [ILM 索引生命周期](https://www.elastic.co/guide/en/elasticsearch/reference/current/ilm-index-lifecycle.html) —— hot / warm / delete 阶段与动作
- [索引模板（含 `composed_of`）](https://www.elastic.co/guide/en/elasticsearch/reference/current/index-templates.html) —— 决策点 3 与反例 ⑧ 的官方依据
- [快照与恢复](https://www.elastic.co/guide/en/elasticsearch/reference/current/snapshot-restore.html) —— `feature_states` 与系统索引的恢复方式

**可视化与告警（Kibana）**

- [ES query 规则类型](https://www.elastic.co/guide/en/kibana/current/rule-type-es-query.html) —— 动作组与 `groupBy` 语义
- [Saved Objects 导出 API](https://www.elastic.co/guide/en/kibana/current/saved-objects-api-export.html) —— 决策点 4 里提到的"配置资产备份"

**字段规范（ECS）**

- [ECS 字段参考](https://www.elastic.co/guide/en/ecs/current/ecs-field-reference.html) —— `log.level` / `host.name` / `url.path` 等字段的官方定义（决策点 2 里"要不要保留 ECS"的判据）

---

## 🚀 下一步

- 想自查是否真的做成了 → 打开 [`验收清单.md`](验收清单.md) 逐条勾
- 想知道每个设计选择背后的取舍 → 读 [`设计决策.md`](设计决策.md)
- 想先看看"反着写会怎样" → 读 [`反例对照.md`](反例对照.md)
- 本项目完成后 → 回到课程目录，进入 **Phase 4 汇总手册**与 **Phase 5 实战经验 + 排障速查手册 + 场景解法库**
