# 分区 · 安全与扩展

> 服务课次：**课 17《扩展与安全》**（预收集，2026-09-10 备课期建立）
> 全部链接经 `curl` 实测 HTTP 200（核查于 2026-09）

---

## 1. 角色与权限

| 我要… | 页面 | 备注 |
|-------|------|------|
| 建角色 / 改角色 / 删角色 | [`sql-createrole.html`](https://www.postgresql.org/docs/17/sql-createrole.html) | 含 `LOGIN` / `SUPERUSER` / `CREATEDB` / `CREATEROLE` / `REPLICATION` / `BYPASSRLS` |
| 授权 / 收权 | [`sql-grant.html`](https://www.postgresql.org/docs/17/sql-grant.html) / [`sql-revoke.html`](https://www.postgresql.org/docs/17/sql-revoke.html) | 对象级 + 列级 + 默认权限（`ALTER DEFAULT PRIVILEGES`） |
| 权限模型总论 | [`ddl-priv.html`](https://www.postgresql.org/docs/17/ddl-priv.html)（5.8） | GRANT / REVOKE / 所有权 / 依赖 |
| 数据库角色与属性 | [`user-manag.html`](https://www.postgresql.org/docs/17/user-manag.html)（21.1） | 角色即用户：PG 里没有区别 |
| 角色属性细节（含 `SET ROLE`、继承） | [`role-attributes.html`](https://www.postgresql.org/docs/17/role-attributes.html)（21.2） | `INHERIT` / `NOINHERIT` / `SET ROLE` |
| 行级安全（RLS） | [`ddl-rowsecurity.html`](https://www.postgresql.org/docs/17/ddl-rowsecurity.html) | 多租户常用 |

> ⚠️ 实测 `privileges.html` **404**；权限总论只有 `ddl-priv.html`。

## 2. 客户端认证

| 我要… | 页面 |
|-------|------|
| `pg_hba.conf` 怎么配、匹配顺序 | [`client-authentication.html`](https://www.postgresql.org/docs/17/client-authentication.html)（20.1） |
| 各认证方法对比（trust / password / scram / gss / sspi / ident / peer / ldap / radius / cert / pam / bsd） | [`auth-methods.html`](https://www.postgresql.org/docs/17/auth-methods.html)（20.3） |
| 密码认证与 `scram-sha-256` | [`auth-password.html`](https://www.postgresql.org/docs/17/auth-password.html)（20.5） |
| LDAP / RADIUS 认证 | [`auth-ldap.html`](https://www.postgresql.org/docs/17/auth-ldap.html)（20.10） |
| 证书认证 | [`auth-cert.html`](https://www.postgresql.org/docs/17/auth-cert.html)（20.12） |

**要点提醒**：`pg_hba.conf` 是**自上而下第一条匹配生效**（不是最具体优先）；改完 `pg_hba.conf` 用 `pg_ctl reload` 或 `SELECT pg_reload_conf()` 即可生效（不需重启）。

## 3. 传输与静态加密

| 我要… | 页面 |
|-------|------|
| 开 SSL/TLS（`ssl` / `ssl_cert_file` / `ssl_key_file`） | [`ssl-tcp.html`](https://www.postgresql.org/docs/17/ssl-tcp.html)（18.9） |
| 选数据加密方案（含 `password_encryption`） | [`encryption-options.html`](https://www.postgresql.org/docs/17/encryption-options.html)（18.8） |

## 4. 扩展

| 我要… | 页面 | 备注 |
|-------|------|------|
| 写自己的扩展（`CREATE EXTENSION` 机制、扩展脚本） | [`extend.html`](https://www.postgresql.org/docs/17/extend.html)（36） | 36.17 = 扩展打包 |
| 后台工作进程（`bgworker`） | [`bgworker.html`](https://www.postgresql.org/docs/17/bgworker.html)（37） | 写常驻后台任务的入口 |
| 表访问方法（自定义存储引擎） | [`tableam.html`](https://www.postgresql.org/docs/17/tableam.html)（64） | PG 12+ |
| 自定义 WAL 资源管理器 | [`custom-rmgr.html`](https://www.postgresql.org/docs/17/custom-rmgr.html)（65） | PG 15+ |
| 官方附带模块清单（`contrib`） | [`contrib.html`](https://www.postgresql.org/docs/17/contrib.html)（附录 F） | `pg_stat_statements` / `pg_trgm` / `postgres_fdw` / `pgcrypto` / `hstore` / `uuid-ossp` 等都在这 |
| 校验数据页校验和 | [`app-pgchecksums.html`](https://www.postgresql.org/docs/17/app-pgchecksums.html) | 需停机或 offline |

> 📌 **课程已用过的扩展**：`pageinspect`（课 8 看 B-Tree 页）、`pgstattuple`（课 8/12 量膨胀）、`pg_trgm`（课 10 LIKE 加速）、`pg_stat_statements`（课 9/10 语句统计）。

## 5. 连接池与连接管理

| 我要… | 页面 | 备注 |
|-------|------|------|
| 单连接的后端进程模型（为什么连接贵） | [`kernel-resources.html`](https://www.postgresql.org/docs/17/kernel-resources.html)（18.3 管理内核资源） | 官方讲"每个连接消耗多少"的地方（semaphore / 共享内存 / 每连接进程） |
| 连接/认证相关参数 | [`runtime-config-connection.html`](https://www.postgresql.org/docs/17/runtime-config-connection.html)（19.3） | `max_connections` / `listen_addresses` / `port` / `unix_socket_directories` |
| 客户端侧超时 | [`runtime-config-client.html`](https://www.postgresql.org/docs/17/runtime-config-client.html)（19.12） | `idle_in_transaction_session_timeout` / `idle_session_timeout`（PG 14+）/ `statement_timeout` / `lock_timeout` / `transaction_timeout`（**PG 17 新增**） |
| 连接池软件 | **不在官方文档内** | PgBouncer / Pgpool-II 是第三方；官方只在 `high-availability.html` 里泛泛提及连接池位置 |

> ⚠️ 官方文档**没有 PgBouncer 专章**。讲连接池要么引第三方官网，要么只讲"为什么需要"（后端进程成本）+ 官方 `max_connections` 与内存的关系。

## 6. 升级与迁移

| 我要… | 页面 |
|-------|------|
| 大版本升级（`pg_upgrade`，in-place / link 模式） | [`pgupgrade.html`](https://www.postgresql.org/docs/17/pgupgrade.html) |
| 逻辑复制做跨版本迁移（低停机方案） | [`logical-replication.html`](https://www.postgresql.org/docs/17/logical-replication.html) |
| 完整迁移（含角色 / 表空间） | [`app-pg-dumpall.html`](https://www.postgresql.org/docs/17/app-pg-dumpall.html) + [`app-pgdump.html`](https://www.postgresql.org/docs/17/app-pgdump.html) |

> ⚠️ 实测 `app-pgupgrade.html` **404**，正确路径是 **`pgupgrade.html`**（无 `app-` 前缀）—— PG URL 命名不统一，**以本索引为准**。

## 7. 必查的事实点（课 17 讲义前须联网核实）

| # | 待核实 | 去哪查 |
|---|--------|--------|
| 1 | `max_connections` 与共享内存的关系（每连接的成本在哪） | `runtime-config-connection.html` |
| 2 | 连接池为什么能省（PG 后端进程模型 vs 线程模型） | `overview.html`（若需验证）+ `runtime-config-connection.html` |
| 3 | `scram-sha-256` 与 `md5` 的差别及迁移路径 | `auth-password.html` |
| 4 | `CREATE EXTENSION` 需要的权限与 `trusted` 标记 | `extend.html` + [`sql-createextension.html`](https://www.postgresql.org/docs/17/sql-createextension.html) |
| 5 | `pg_upgrade` 的前置条件（`--check` 干什么、link 模式的风险） | `pgupgrade.html` |
| 6 | PG 17 的安全 / 扩展相关变化 | [`release-17.html`](https://www.postgresql.org/docs/17/release-17.html) |

## 8. 相关分区

- 备份与恢复（升级前必做）→ [`backup-recovery.md`](backup-recovery.md)
- 复制（跨版本迁移的通道）→ [`replication-ha.md`](replication-ha.md)
- 参数体系与生效级别 → [`server-config-and-sql.md`](server-config-and-sql.md)
