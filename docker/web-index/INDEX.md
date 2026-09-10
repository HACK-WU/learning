# 网页索引登记表（Docker 教程）

> 本教程自建的官方文档索引。**涉及 Docker 的问题，先查对应条目所在的分区/路由表，再 web_fetch 取正文**——不要现场搜链接。
> 与仓库根 `.web-index/`（跨主题共享）**是两套**，本表只服务 Docker 教程。

| 站点 | slug | 起始 URL | 范围 | 条数 | 生成日期 |
|------|------|----------|------|------|----------|
| Docker Docs | docker | https://docs.docker.com/ | 教程/引擎/构建/Compose/Docker Hub/参考（排除 ai、dhi、desktop、enterprise、scout、release-notes 等） | 309 | 2026-09-10 |

## 入口

- [docker/index.md](./docker/index.md) —— 元信息 + 高频直达 + 分区索引 + 课程映射（15 课 → 主查分区）

## 使用约定

1. 先查「高频直达」→ 再查分区表 → 最后 web_fetch
2. 索引是**一次性快照**（采集自官方 [llms-full.txt](https://docs.docker.com/llms-full.txt)，全站 1433 条按课程口径裁剪为 309 条）
3. **版本号、默认值、新特性以官网当页为准**——本索引只解决"去哪一页"，不保证页面内容未变
4. 命令参数细节本机可直接 `docker <命令> --help`，比 fetch 更快
5. 版本基线：课程以 Docker Engine **29.x** 为准（核查于 2026-09），Compose 一律 V2 写法 `docker compose`
6. 链接大面积失效时整站重跑重建，并更新生成日期

## 迁移记录

- 2026-09-10：由仓库根 `.web-index/docker/` 迁入本教程目录 `docker/web-index/docker/`，使其随课程走（与 Kafka 教程 `kafka/web-index/` 同一约定）
