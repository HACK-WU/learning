# 课 17 实验原始输出汇总

> 环境：PostgreSQL 17.11 / Docker / 主库 pg17（5433）。时间：2026-09-11。
> 实验命令与正文一致（labs 脚本精简为关键步骤）；本文件记录全部实测输出与踩坑。

## A 组 · 扩展生态

### A-1 盘点

```text
可装: 45（pg_available_extensions）
已装: pageinspect, pg_stat_statements, pg_trgm, pgstattuple, plpgsql   ← 前课资产
```

### A-2 pgcrypto + uuid-ossp

```text
CREATE EXTENSION pgcrypto; CREATE EXTENSION "uuid-ossp";    → 成功
 内置函数(gen_random_uuid())  |  扩展函数(uuid_generate_v4()) | sha256摘要
 162e262c-…                   |  69441668-…                  | 693e04af…
```

> PG 13+ 内置 `gen_random_uuid()`，新表用 UUID 不再必须装 uuid-ossp。

### A-3 trusted 扩展双对照（PG 13+ 机制）

```sql
CREATE ROLE dev1 LOGIN; GRANT CONNECT, CREATE ON DATABASE order_service TO dev1;
SET ROLE dev1;
CREATE EXTENSION pg_trgm;        -- trusted=t  → 成功
CREATE EXTENSION citext;         -- trusted=t  → 成功
CREATE EXTENSION pg_freespacemap;-- trusted=f → 报错 ↓
```

```text
ERROR:  permission denied to create extension "pg_freespacemap"
HINT:  Must be superuser to create this extension.
```

`pg_extension.extowner` 实测 = **dev1**（官方：extension 对象归调用用户，内部对象归 bootstrap superuser）。
trusted 标记来源实测：`pg_available_extension_versions.trusted`（citext=t / pg_freespacemap=f / amcheck=f）。

## B 组 · 角色与权限

### B-1 组继承 + USAGE 第一道门

```sql
CREATE ROLE devs NOLOGIN; GRANT devs TO dev1; GRANT SELECT ON finance.orders_big TO devs;
SET ROLE dev1; SELECT count(*) FROM finance.orders_big;
→ ERROR:  permission denied for schema finance        ← 表权限 ≠ schema USAGE
GRANT USAGE ON SCHEMA finance TO devs;
→ 补 USAGE 后组继承可查: 1000000                       ← 成功
```

### B-2 默认权限

```sql
ALTER DEFAULT PRIVILEGES IN SCHEMA finance GRANT SELECT ON TABLES TO devs;
CREATE TABLE finance.fresh_tbl2(id int);   -- 未手动授权
→ information_schema.role_table_grants: fresh_tbl2 | SELECT     ← 自动获得
```

### B-3 public schema 收紧（PG 15+）

```text
SET ROLE dev1; CREATE TABLE public.hack_t(id int);
ERROR:  permission denied for schema public
```

### B-4 RLS 四象限（多租户）

```sql
CREATE TABLE finance.orders_rls(id int, tenant text, amount numeric);
-- 数据：tenant='app_a' 2 行 / 'app_b' 2 行（⚠ 租户值必须与 current_user 完全相等，'a' 会匹配不上）
ALTER TABLE … ENABLE ROW LEVEL SECURITY;
CREATE POLICY tenant_isolation ON … USING (tenant = current_user) WITH CHECK (tenant = current_user);
```

| 象限 | 操作 | 实测 |
|---|---|---|
| 1 | app_a / app_b SELECT | 各只见自己 2 行 ✓ |
| 2 | app_b INSERT (tenant='app_a') | `ERROR: new row violates row-level security policy for table "orders_rls"`（WITH CHECK 拦截） |
| 3 | 非 super owner（rolena）SELECT | 未 FORCE：**4 行**（owner 默认绕过）→ `FORCE ROW LEVEL SECURITY` 后：**0 行**（策略对 owner 生效） |
| 4 | postgres（superuser）SELECT | 永远 4 行（**FORCE 对 superuser 无效**；官方：*Superusers and roles with the BYPASSRLS attribute always bypass*） |

## C 组 · 连接管理

### C-1 50 空闲连接的真实代价

```text
连接前: postgres 进程 RSS 总计 361.934 MB
50 连接: 客户端后端进程 50 / RSS 总计 1148.86 MB      ← 净增 787 MB ÷ 50 ≈ 15.7 MB/连接
断开后: RSS 回落 361.934 MB（精确回落，无泄漏）
```

> max_connections 默认 100 且直接决定共享内存分配（官方 19.3）。500 连接 ≈ 7.9 GB——这就是 PgBouncer 存在的理由。

### C-3 PgBouncer 三模式（纸面，官方无专章 · pgbouncer.org，核查于 2026-09-11）

| 模式 | 连接绑定 | 兼容性 | 吞吐 |
|---|---|---|---|
| session | 客户端 ↔ 服务端整会话 | 全兼容 | 低 |
| transaction | 每事务借还 | ⚠ 会话级 SET / 通知监听等跨事务特性失效；**1.21 起支持协议级 prepared statements** | 高 |
| statement | 每语句借还 | 不允许多语句事务 | 最高 |

## D 组 · 升级与迁移

### D-1 postgres_fdw 跨库查询实测

```sql
CREATE EXTENSION postgres_fdw;
CREATE SERVER other_db FOREIGN DATA WRAPPER postgres_fdw OPTIONS (host '127.0.0.1', port '5432', dbname 'b_restored');
CREATE USER MAPPING FOR postgres SERVER other_db OPTIONS (user 'postgres');
IMPORT FOREIGN SCHEMA finance LIMIT TO (categories, doctors) FROM SERVER other_db INTO foreign_b;
SELECT count(*) FROM foreign_b.categories;   -- → 6（与本库一致）
```

### D-2 pg_upgrade 关键事实（官方 18.6 页原文，核查于 2026-09-11）

- **统计信息不随升级转移**：*"statistics are not transferred by pg_upgrade, you will be instructed to run a command to regenerate that information at the end of the upgrade"*（⚠ 备课笔记曾误记"PG 17 保留 statistics"——核查推翻；PG 17 真正保留的是**逻辑复制槽与订阅状态** + 新增 `--copy-file-range`）
- `--check` 只查不升级；`--link` 硬链接秒级但旧数据目录不可再用；`--jobs` 并行加速

### D-3 三路线对比（升级大版本）

| 路线 | 停机窗口 | 跨大版本 | 回滚 | 适用 |
|---|---|---|---|---|
| pg_upgrade | 分钟级 | ✓（单次一步） | link 模式难 | 同机同架构 |
| 逻辑复制 | 秒级（切换时刻） | ✓（10→任意新） | 容易（切回旧主） | 低停机要求 |
| pg_dump/restore | 小时级（随库大小） | ✓ | 重跑 | 跨架构/小库 |

## 收尾清理（实验后）

- DROP TABLE orders_rls；DROP OWNED + DROP ROLE app_a/app_b/rolena/devs/dev1（dev1 名下 pg_trgm 用 **REASSIGN OWNED BY dev1 TO postgres** 转移后删除——⚠ `ALTER EXTENSION … OWNER TO` **不存在**（实测 syntax error），改扩展 owner 用 REASSIGN）
- 保留扩展：pgcrypto / uuid-ossp / pg_trgm（+课 10 GIN 索引）/ postgres_fdw / 前四课全部资产
- 残留角色 0；pg_trgm owner=postgres；idx_note_trgm 在

## 踩坑清单（正文素材）

1. 组继承授了表权限仍查不了 → **schema USAGE 是第一道门**
2. RLS 策略里租户值 `'a'` ≠ `current_user='app_a'` → 象限 1 全 0 行（策略值要与角色名逐字相等）
3. `FORCE ROW LEVEL SECURITY` 对 superuser 无效 → 演示 FORCE 必须用非超级 owner
4. `ALTER EXTENSION … OWNER TO` 不存在 → 用 `REASSIGN OWNED`
5. PG 15 的 public schema 收紧**不随 pg_upgrade 自动生效**（Percona/depesz 核实：升级保留旧 ACL，需手动 REVOKE）
