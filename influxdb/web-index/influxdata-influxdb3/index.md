# InfluxDB 3 Docs 网页索引

> 起始 URL：https://docs.influxdata.com/influxdb3/core/
> 生成日期：2026-09-10 · 范围（scope）：InfluxDB 3 Core 全量（294 页，来自官方 llms-full.txt 语料）+ which-influxdb-3 选型页；已排除 Enterprise / Clustered / Cloud Dedicated / Cloud Serverless / Explorer / Telegraf / InfluxDB 1.x·2.x 版本文档等其他产品线 · 条目数：295 · 一次性快照
> 只索引不镜像：需要正文时用 web_fetch 打开对应 URL（带锚点直达）
> 课程对齐：课程基线 InfluxDB 3.x（Core），含 1.x/2.x 迁移与 432 查询文件限制等 3.x 特有机制

## 怎么用

1. 按「我要…」列定位条目（不确定先看下方分区索引）
2. 用 web_fetch 打开该条 URL 取细节
3. 本表是快照，链接大面积失效时整站重跑重建（脚本与中间地图见仓库 `temp/`：`build_influxdata-influxdb3_web_index.py` / `web-index-influxdata-influxdb3-map.md`；原始语料 `temp/influxdb3-core-llms-full.txt` 3.0MB 含每页正文，按需 grep）
4. 查 1.x/2.x 文档：https://docs.influxdata.com/influxdb/v2/ 等（本次未索引）

## 高频直达

| 我要… | 去哪一页 | 分区 |
|-------|----------|------|
| 对比 InfluxDB 3 各版本并决定从 1.x/2.x 迁到哪 | [which-influxdb-3](https://docs.influxdata.com/influxdb3/which-influxdb-3/) | get-started |
| 快速上手：起服务→写入→查询 | [get-started](https://docs.influxdata.com/influxdb3/core/get-started/) | get-started |
| 用 HTTP API 写入行协议 | [write-data/http-api](https://docs.influxdata.com/influxdb3/core/write-data/http-api/) | write-data |
| 理解行协议语法 | [write-data/line-protocol](https://docs.influxdata.com/influxdb3/core/write-data/line-protocol/) | write-data |
| 管理 token（创建/权限/轮转） | [admin/token](https://docs.influxdata.com/influxdb3/core/admin/token/) | admin |
| 备份与恢复 | [admin/backup-restore](https://docs.influxdata.com/influxdb3/core/admin/backup-restore/) | admin |
| 查 SQL 逐语句/函数参考 | [reference/sql](https://docs.influxdata.com/influxdb3/core/reference/sql/) | reference-sql |
| 查 influxdb3 CLI 逐命令参考 | [reference/cli](https://docs.influxdata.com/influxdb3/core/reference/cli/) | reference-cli |
| 查 v3 原生 API 端点（write_lp/query） | [api/v3](https://docs.influxdata.com/influxdb3/core/api/v3/) | api |
| 处理引擎与 Python 插件总览 | [plugins](https://docs.influxdata.com/influxdb3/core/plugins/) | plugins |

## 分区索引

| 分区 | 文件 | 条数 | 覆盖内容 |
|------|------|------|----------|
| get-started | [topics/get-started.md](./topics/get-started.md) | 10 | 安装/上手/选型/迁移/版本 |
| write-data | [topics/write-data.md](./topics/write-data.md) | 14 | HTTP API/line protocol/各工具写入 |
| query-data | [topics/query-data.md](./topics/query-data.md) | 19 | SQL 查询/参数化/Flight |
| admin | [topics/admin.md](./topics/admin.md) | 34 | 数据库/token/备份/去重缓存 |
| plugins | [topics/plugins.md](./topics/plugins.md) | 42 | 处理引擎与 Python 插件 |
| api | [topics/api.md](./topics/api.md) | 15 | HTTP API 端点（v3/v2 兼容） |
| object-storage | [topics/object-storage.md](./topics/object-storage.md) | 5 | 对象存储配置 |
| visualize-data | [topics/visualize-data.md](./topics/visualize-data.md) | 4 | Grafana/Explorer |
| reference-sql | [topics/reference-sql.md](./topics/reference-sql.md) | 36 | SQL 逐语句/函数 |
| reference-influxql | [topics/reference-influxql.md](./topics/reference-influxql.md) | 21 | InfluxQL 兼容参考 |
| reference-cli | [topics/reference-cli.md](./topics/reference-cli.md) | 42 | CLI 逐命令参考 |
| reference-clients | [topics/reference-clients.md](./topics/reference-clients.md) | 39 | 各语言 SDK |
| reference-misc | [topics/reference-misc.md](./topics/reference-misc.md) | 14 | 术语/行协议/配置项等 |
