# 网页索引登记表

> 涉及下列站点的问题，先查对应条目所在的分区/路由表，再 web_fetch 取正文

| 站点 | slug | 起始 URL | 范围 | 条数 | 生成日期 |
|------|------|----------|------|------|----------|
| InfluxDB 3 Core Docs | influxdata-influxdb3 | https://docs.influxdata.com/influxdb3/core/ | /influxdb3/core 全量 + which-influxdb-3 选型页（排除 Enterprise/Cloud/Explorer/Telegraf/1.x/2.x 等其他产品线） | 295 | 2026-09-10 |

## 范围与路由治理

- 本表的 Core 条目是当前课程主线的官方资料证据源；它不代表 Enterprise、Cloud、Telegraf 或旧版 InfluxDB 文档已建立索引。
- Core 旧路由、当前入口和“没有一对一替代页”的记录见 [`influxdata-influxdb3/ROUTE-ALIASES.md`](./influxdata-influxdb3/ROUTE-ALIASES.md)。
- 课程引用非 Core 产品线时，必须在链接文字或表格中写明产品线，不能只写“官方文档”。
