# 网页索引登记表（Kafka 教程）

> 本教程自建的官方文档索引。**涉及 Kafka 的问题，先查对应条目所在的分区/路由表，再 web_fetch 取正文**——不要现场搜链接。
> 与仓库根 `.web-index/`（跨主题共享）**是两套**，本表只服务 Kafka 教程。

| 站点 | slug | 起始 URL | 范围 | 条数 | 生成日期 |
|------|------|----------|------|------|----------|
| Apache Kafka Docs | kafka | https://kafka.apache.org/43/ | `/43/`（4.3 文档）+ `documentation/` 长页锚点 + 关键 Javadoc + 课程引用过的 KIP | 101 | 2026-09-10 |

## 入口

- [kafka/index.md](./kafka/index.md) —— 元信息 + 高频直达 + 分区索引

## 使用约定

1. 先查「高频直达」→ 再查分区表 → 最后 web_fetch
2. **查单个配置参数直接用锚点 URL**（如 `#producerconfigs_acks`）；锚点前缀规则见 [configuration 分区](./kafka/topics/configuration.md) 顶部
3. 版本号 / 默认值类事实核查：优先用 `/43/` 版本锁定页，不用 `documentation/` 长页（后者永远指向最新版，会漂移）
4. 索引是快照：Kafka 发新版后 `/43/` 会被更新版本目录取代，届时整站重跑重建并更新生成日期
