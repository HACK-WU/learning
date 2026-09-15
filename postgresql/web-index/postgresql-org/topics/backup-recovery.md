# 分区 · 备份与恢复

> 服务课次：**课 14 备份与恢复**（阶段 5 开篇，2026-09-10 交付时建立本索引）
> 全部链接经 `curl` 实测 HTTP 200（核查于 2026-09）

---

## 1. 三条路径怎么选（先读这三页）

| 我要… | 页面 | 关键结论 |
|-------|------|----------|
| 先看清逻辑 / 物理 / PITR 的分工 | [`backup.html`](https://www.postgresql.org/docs/17/backup.html)（25.1） | 25.1.1 = SQL dump，25.1.2 = 文件系统级，25.2 = 连续归档；**先读这页再进细节** |
| 彻底搞懂"回到任意时刻"怎么实现 | [`continuous-archiving.html`](https://www.postgresql.org/docs/17/continuous-archiving.html)（25.3） | 25.3.5 = 恢复十步流程；含 timeline 概念、*时间旅行*警告、`pg_dump` **不能**用于连续归档 |
| 背参数默认值 | [`runtime-config-wal.html`](https://www.postgresql.org/docs/17/runtime-config-wal.html)（19.5） | `archive_mode` 是 **server start 级**（改了要重启）；`recovery_target_action` 默认 **`pause`** |

## 2. 逻辑备份四工具

| 工具 | 页面 | 必须记住的 |
|------|------|-----------|
| `pg_dump` | [`app-pgdump.html`](https://www.postgresql.org/docs/17/app-pgdump.html) | 四格式：`-Fp` plain（**默认**）/ `-Fc` custom / `-Fd` directory / `-Ft` tar。**`-Fd` 是唯一支持 `-j` 并行转储的格式**（官方原文）。`-Ft` **没有压缩选项**。不含 roles / tablespaces |
| `pg_dumpall` | [`app-pg-dumpall.html`](https://www.postgresql.org/docs/17/app-pg-dumpall.html) | 备**整个集群**；`--globals-only` 只备角色与表空间 —— 与 `pg_dump` 组合才是完整迁移 |
| `pg_restore` | [`app-pgrestore.html`](https://www.postgresql.org/docs/17/app-pgrestore.html) | **默认不中止**（跑完汇总 `errors ignored on restore: N`）；`-e` 才第一个错就停；`--if-exists` **必须配** `--clean`；`-t` **不恢复依赖对象** |
| `psql`（恢复 plain） | [`app-psql.html`](https://www.postgresql.org/docs/17/app-psql.html) | plain 格式只能用 psql 喂；`pg_restore` 读 plain 会报 *input file appears to be a text format dump. Please use psql.* |

**锚点**：`app-pgdump.html#APP-PGDUMP-NOTES`（注意事项）、`app-pgrestore.html#APP-PGRESTORE-NOTES`

## 3. 物理备份

| 工具 | 页面 | 必须记住的 |
|------|------|-----------|
| `pg_basebackup` | [`app-pgbasebackup.html`](https://www.postgresql.org/docs/17/app-pgbasebackup.html) | 走**复制协议**；*always backs up the whole database cluster*；`-F` 默认 **plain**、`-X` 默认 **stream**、`--manifest-checksums` 默认 **CRC32C**；`--target`（默认 `client`）**不能与 `-X stream` 同用**；`-R` 写 `standby.signal` + `postgresql.auto.conf` |
| `pg_verifybackup` | [`app-pgverifybackup.html`](https://www.postgresql.org/docs/17/app-pgverifybackup.html) | 校验 `backup_manifest`；**必须对解包后的目录**跑（对 tar 产物直接跑会报 *is present in the manifest but not on disk*） |
| `pg_combinebackup`（PG 17+） | [`app-pgcombinebackup.html`](https://www.postgresql.org/docs/17/app-pgcombinebackup.html) | 把基础备份 + 增量备份合成一份完整备份；配 `pg_basebackup --incremental` 使用。官方：*incremental backup (`--incremental`) only works with server version 17 and later* |

**锚点**：`app-pgbasebackup.html#APP-PGBASEBACKUP-OPTIONS`

## 4. WAL 归档与恢复配置

| 我要… | 页面 / 锚点 |
|-------|------------|
| `wal_level` / `archive_mode` / `archive_command` / `archive_timeout` | [`runtime-config-wal.html`](https://www.postgresql.org/docs/17/runtime-config-wal.html) |
| **恢复目标家族**（`recovery_target` / `_time` / `_xid` / `_name` / `_lsn` / `_action` / `_inclusive` / `_timeline`） | `runtime-config-wal.html#RECOVERY-TARGET`（**五者最多设一个**；`recovery_target_action` 默认 `pause`） |
| 归档细节与退出码契约 | `runtime-config-wal.html#WAL-ARCHIVING`（`archive_command` 返回 0 = 成功；设成 `/bin/true` 会**破坏 WAL 链**） |
| 恢复流程十步 | `continuous-archiving.html#BACKUP-PITR-RECOVERY` |
| `recovery.signal` vs `standby.signal` | `continuous-archiving.html`（两者同时存在时 **`standby.signal` 优先**；恢复完 `recovery.signal` **会被自动删除**） |
| timeline 与 `.history` 文件 | `continuous-archiving.html#BACKUP-TIMELINES`（`.history` 须与 WAL **一起归档**） |

### 已验证的官方原话（引用时可直接抄）

| 事实 | 原文 |
|------|------|
| 停止点必须在基础备份结束之后 | *The stop point must be after the ending time of the base backup, i.e., the end time of the backup* |
| `pg_dump` 不能做连续归档 | *pg_dump ... cannot be used as part of a continuous-archiving solution* |
| `pg_dump` 不阻塞读写 | *does not block other users accessing the database (readers or writers)* |
| 只有 directory 支持并行 dump | *The "directory" format is the only format that supports parallel dumps.* |
| `archive_command` 假成功的危害 | *effectively disables archiving, but also breaks the chain of WAL files* |
| `recovery.conf` 存在的后果（PG 12+） | *the server will not start if that file exists* |

## 5. 版本史（写讲义时引用）

| 版本 | 时间 | 备份相关变化 | 来源 |
|------|------|-------------|------|
| 7.1 | 2001-04 | 引入 WAL（当时**还不能归档**）+ `pg_dump` 大改造（新增 tar 格式与 `pg_restore`，作者 Philip Warner） | `/docs/release/7.1/` |
| 8.0 | 2005-01 | 引入 **PITR**；动机之一是把 `pg_dump` 从"唯一备份手段"的重担中解放 | `/docs/release/8.0/` |
| 9.1 | 2011-09 | 引入 **`pg_basebackup`** | `/docs/release/9.1/` |
| 12 | 2019-10 | 移除 `recovery.conf` | [`/docs/12/release-12.html`](https://www.postgresql.org/docs/12/release-12.html) |
| 17 | 2024-09 | `pg_basebackup --incremental` + `pg_combinebackup` | [`release-17.html`](https://www.postgresql.org/docs/17/release-17.html) |

## 6. 相关分区

- 复制与高可用（从这份基础备份搭从库）→ [`replication-ha.md`](replication-ha.md)
- 参数体系怎么改、什么时候生效 → [`server-config-and-sql.md`](server-config-and-sql.md)
- 磁盘用量与膨胀（备份体积的邻居问题）→ [`observability.md`](observability.md)
