# 网页索引登记表 · PostgreSQL

> 涉及下列站点的问题，先查对应条目所在的分区/路由表，再 `web_fetch` 取正文。
>
> **本表所有 URL 均经 `curl` 实测 HTTP 200**（核查于 2026-09）。PG 官方 URL 命名不统一（`app-pgdump.html` 有连字符、`app-pgdumpall` 实际是 `app-pg-dumpall.html`、`app-pgupgrade` 实际是 `pgupgrade.html`），**不要凭命名规律猜，以本表为准**。

| 站点 | slug | 起始 URL | 范围 | 条数 | 生成日期 |
|------|------|----------|------|------|----------|
| PostgreSQL 17 官方文档 | postgresql-org | https://www.postgresql.org/docs/17/index.html | 官方文档 17 版（当前课程版本基线），按「我要做什么」组织；覆盖课 1–17 与结课项目所需 | 62 | 2026-09-10 |

## 说明

- **版本基线**：PG **17.x**（2024-11 GA，2026-09 在维护期）。课程容器 `pg17` 实测为 **17.11**。
- **URL 形态**：`docs/17/{page}.html`（站点前缀 `www.postgresql.org`），锚点用 `#UPPER-CASE-WITH-DASHES`（官方锚点全大写）。
- **跨版本页**：发布说明不在 17 路径下，而在 `/docs/{major}/release-{major}.html`（如 PG 12 的 `recovery.conf` 移除 → `https://www.postgresql.org/docs/12/release-12.html`）。
- **未收录的坑**（实测 404，勿用）：`security.html`、`privileges.html`、`recovery-configuration.html`、`runtime-config-vacuum.html`、`view-pg-stat-activity.html`、`app-pg-waldump.html`、`app-pg-resetwal.html`、`app-pg-receivewal.html`、`app-pg-upgrade.html`。

## 分区

| 分区 | 覆盖内容 | 主要服务课次 |
|------|----------|--------------|
| [`topics/backup-recovery.md`](postgresql-org/topics/backup-recovery.md) | 逻辑备份 / 物理备份 / WAL 归档 / PITR / 备份校验 | 课 14（已用） |
| [`topics/replication-ha.md`](postgresql-org/topics/replication-ha.md) | 流复制 / 复制槽 / 同步异步 / 故障切换 / HA 方案 / 逻辑复制 | 课 15（预收集） |
| [`topics/observability.md`](postgresql-org/topics/observability.md) | 监控标准 / `pg_stat_*` 视图族 / 进度报告 / EXPLAIN / 规划器 / 并行 / VACUUM | 课 9–10、课 12、课 16（预收集） |
| [`topics/security-extensions.md`](postgresql-org/topics/security-extensions.md) | 扩展 / 附加模块 / 角色与权限 / 认证 / SSL 与加密 | 课 17（预收集） |
| [`topics/server-config-and-sql.md`](postgresql-org/topics/server-config-and-sql.md) | 参数体系与五个 runtime-config 页 / 服务器程序 / 锁与隔离 / 错误码 | 课 1–17 通用 |

- 总路由表：[`postgresql-org/index.md`](postgresql-org/index.md)
