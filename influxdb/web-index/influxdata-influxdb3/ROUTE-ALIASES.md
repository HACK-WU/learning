# Core 文档范围与路由核查

> 核查日期：2026-09-17。此文件不是第二份网页索引，而是课程引用官方链接时使用的“旧路由 → 当前入口”登记表。

## 1. 索引边界

当前索引 `influxdata-influxdb3` 只覆盖：

- `https://docs.influxdata.com/influxdb3/core/` 全量文档；
- `which-influxdb-3` 选型页；
- 2026-09-10 生成，登记约 295 条路由。

以下产品线不由本索引背书：InfluxDB 3 Enterprise、InfluxDB Cloud/Cloud Dedicated、Explorer、Telegraf、InfluxDB 1.x、InfluxDB 2.x。课程可以保留这些链接作为对照，但它们必须标明产品线，不能把 Core 索引命中当成跨产品线事实。

## 2. Core 旧路由与当前入口

| 课程中出现的旧路由 | 当前 Core 入口 | 核查结论 | 处理规则 |
|---|---|---|---|
| `/core/admin/object-storage/` | `/core/object-storage/` | 旧路由 404；当前入口 200 | 课程正文改用当前入口 |
| `/core/reference/syntax/line-protocol/` | `/core/reference/line-protocol/` | 两者当前都可访问；索引登记以后者 | 新增引用统一以后者为准 |
| `/core/query-data/sql/aggregate-data/` | `/core/query-data/sql/aggregate-select/` | 旧路由 404；当前入口 200 | 课程正文改用当前入口 |
| `/core/process-data/` | `/core/plugins/` | 旧路由 404；当前插件总览 200 | 课程正文改用插件总览 |
| `/core/process-data/python-plugins/api-reference/` | `/core/plugins/python-api-reference/` | 旧路由 404；当前 API 参考 200 | 课程正文改用当前入口 |
| `/core/process-data/python-plugins/create-a-plugin/` | `/core/plugins/extend-plugin/` + `/core/plugins/library/examples/` | 没有一对一替代页 | 课程引用拆成“扩展机制 + 示例插件”两个入口 |
| `/core/process-data/create-triggers/` | `/core/reference/cli/influxdb3/create/trigger/` + `/core/plugins/` | 没有一对一替代页 | 概念回插件总览，命令回 CLI 参考 |
| `/core/process-data/python-plugins/use-plugin-cache/` | — | 当前 Core 索引未发现同名现行路由 | 暂不声称有当前官方一对一页面，保留为待复核项 |
| `/core/process-data/downsample/` | `/core/plugins/library/official/downsampler/` | 旧处理引擎页 404；官方 downsampler 插件页 200 | 课程按插件方式引用，并说明这是插件实现 |
| `/core/process-data/troubleshoot/` | `/core/plugins/` + `/core/reference/cli/influxdb3/test/schedule_plugin/` | 当前索引未发现同名排障页 | 暂不保留 404 链接，排障入口改指插件总览与 CLI test 示例 |

## 3. 本轮课程处理结果

- 已归一 L6 的 Line Protocol、L8 的 SQL 聚合、L10 的 object storage 链接。
- 已归一 L14 的 downsampler 与 processing engine 链接。
- L15 的处理引擎资料拆分为当前插件总览、Python API、扩展/示例、CLI trigger；缓存与专门排障页仍登记为未解决项，不伪造一对一替代关系。
- Enterprise / Cloud / Telegraf / 1.x / 2.x 的链接只在课程明确需要产品对照时保留，并在标题或表格中写明产品线；它们不计入 Core 索引的“已覆盖”。

## 4. 刷新规则

每次重新抓取 web-index 后，先更新本表的核查日期和失效路由，再批量修改课程链接。若新站点只改变导航名称、没有等价页面，记录为“无一对一替代”，不要根据相似标题强行替换。
