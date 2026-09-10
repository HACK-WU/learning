# Elastic Docs 网页索引

> 起始 URL：https://www.elastic.co/docs
> 生成日期：2026-09-10 · 范围（scope）：官方 llms.txt（124 条全收）+ docs sitemap.xml（8161 条）按课程 scope 筛出 840 条；已排除：elasticsearch/clients（183）、elasticsearch/plugins（85）、elasticsearch/curator（176）、logstash 逐插件字典页（364）、kibana connectors 逐页（111）、Beats 逐字段页（1386）、ES|QL 三级以下命令页、integration/APM/Fleet/ECS 等非课程产品线 · 条目数：964 · 一次性快照
> 只索引不镜像：需要正文时用 web_fetch 打开对应 URL（带锚点直达）
> 课程对齐：ES 主课（5 阶段 15 课）+ ELK 子教程（12 课：Logstash/Beats/Kibana）

## 怎么用

1. 按「我要…」列定位条目（不确定先看下方分区索引）
2. 用 web_fetch 打开该条 URL 取细节
3. 本表是快照，链接大面积失效时整站重跑重建（脚本与中间地图见仓库 `temp/`：`build_elastic_docs_web_index.py` / `web-index-elastic-docs-map.md`；原始 sitemap `temp/elastic-docs-sitemap.xml`、官方 llms.txt `temp/elastic-docs-llms.txt`）

## 高频直达

| 我要… | 去哪一页 | 分区 |
|-------|----------|------|
| 理解 Elastic Stack 各组件怎么协作 | [the-stack](https://www.elastic.co/docs/get-started/the-stack) | overview |
| 查字段类型权威参考（mapping 设计必读） | [mapping-reference](https://www.elastic.co/docs/reference/elasticsearch/mapping-reference) | es-mapping |
| 看 Query DSL 总目录 | [query-dsl](https://www.elastic.co/docs/reference/query-languages/query-dsl) | query-dsl |
| 查逐聚合参考 | [aggregations](https://www.elastic.co/docs/reference/aggregations) | aggregations |
| 查 REST API 清单（document/search/indices） | [rest-apis](https://www.elastic.co/docs/reference/elasticsearch/rest-apis) | es-apis |
| 查 elasticsearch.yml 配置项 | [configuration-reference](https://www.elastic.co/docs/reference/elasticsearch/configuration-reference) | es-config |
| 查 ILM 动作（rollover/shrink/force-merge） | [index-lifecycle-actions](https://www.elastic.co/docs/reference/elasticsearch/index-lifecycle-actions) | es-ops-tools |
| 看 Logstash 官方手册总目录 | [logstash](https://www.elastic.co/docs/reference/logstash) | logstash |
| 看 Beats 总览（采集层） | [beats](https://www.elastic.co/docs/reference/beats) | beats |
| 看 Kibana 官方手册总目录 | [kibana](https://www.elastic.co/docs/reference/kibana) | kibana |
| 对比部署方式（Cloud/自管/serverless） | [deployment-options](https://www.elastic.co/docs/get-started/deployment-options) | overview |

## 分区索引

| 分区 | 文件 | 条数 | 覆盖内容 |
|------|------|------|----------|
| overview | [topics/overview.md](./topics/overview.md) | 47 | Elastic 全景/部署选项/导读/release notes/排障入口 |
| solutions | [topics/solutions.md](./topics/solutions.md) | 6 | Search/Observability/Security 方案入口 |
| manage-data | [topics/manage-data.md](./topics/manage-data.md) | 6 | 索引/摄取/生命周期/迁移 |
| explore-analyze | [topics/explore-analyze.md](./topics/explore-analyze.md) | 20 | 查询/Kibana 可视化/ML/告警 |
| deploy-manage | [topics/deploy-manage.md](./topics/deploy-manage.md) | 25 | 部署/监控/安全/用户角色 |
| misc | [topics/misc.md](./topics/misc.md) | 19 | troubleshoot/extend/cloud account |
| es-core | [topics/es-core.md](./topics/es-core.md) | 3 | ES 手册总目录等散页 |
| es-mapping | [topics/es-mapping.md](./topics/es-mapping.md) | 87 | 逐字段类型参考（平铺） |
| es-apis | [topics/es-apis.md](./topics/es-apis.md) | 50 | REST API 端点参考 |
| es-config | [topics/es-config.md](./topics/es-config.md) | 60 | 配置项与索引设置 |
| es-ops-tools | [topics/es-ops-tools.md](./topics/es-ops-tools.md) | 56 | CLI 工具/ILM 动作 |
| query-dsl | [topics/query-dsl.md](./topics/query-dsl.md) | 75 | 逐查询类型（平铺） |
| esql | [topics/esql.md](./topics/esql.md) | 48 | ES|QL 语法与命令（两级） |
| sql-eql-promql | [topics/sql-eql-promql.md](./topics/sql-eql-promql.md) | 86 | SQL/EQL/PromQL |
| aggregations | [topics/aggregations.md](./topics/aggregations.md) | 84 | 逐聚合参考（平铺） |
| text-analysis | [topics/text-analysis.md](./topics/text-analysis.md) | 80 | 分词组件参考（平铺） |
| scripting | [topics/scripting.md](./topics/scripting.md) | 67 | painless 脚本（平铺） |
| logstash | [topics/logstash.md](./topics/logstash.md) | 93 | 管道/配置/升级/调优（平铺） |
| beats | [topics/beats.md](./topics/beats.md) | 14 | libbeat 公共配置与部署 |
| kibana | [topics/kibana.md](./topics/kibana.md) | 38 | 配置参考/命令/插件 |
