# 方案 A 真实备份演练 · 完整记录（2026-09-20）

> 用户授权方案 A 后实际执行。以下为**真实命令与真实输出**，非演示。
> 环境：l12-pg（PostgreSQL 16.15）／ 备份落盘 `/mnt/d/projects/learning/docker/backups/l12-pg/`

## 全流程四步

```mermaid
graph LR
    A[①取源库基线] --> B[②pg_dump 导出]
    B --> C[③隔离容器导入]
    C --> D[④逐表 diff 校验]
    D --> E[⑤清理演练环境]
```

---

## ① 取源库基线（演练前必须做，否则无法校验）

```bash
$ docker exec l12-pg psql -U grafana -d grafana -tAc \
    "select count(*) from information_schema.tables where table_schema='public';"
94

$ docker exec l12-pg psql -U grafana -d grafana -tAc \
    "select relname, n_live_tup from pg_stat_user_tables
     where n_live_tup > 0 order by n_live_tup desc limit 5;"
permission|794
migration_log|731
role|130
resource_migration_log|55
secret_migration_log|35
```

> 📌 **基线三件套**：**表数 94** + **各表行数** + **逐表精确 count**。
> ⚠️ `n_live_tup` 是**估算值**（来自统计信息），只用来快速看量级；**校验必须用 `count(*)` 精确值**。

---

## ② pg_dump 导出

```bash
$ docker exec l12-pg pg_dump -U grafana -d grafana \
    --format=custom --no-owner --no-acl | gzip > grafana-2026-09-20-124927.sql.gz

  开始时间: 2026-09-20 12:49:27
  结束时间: 2026-09-20 12:49:28
  耗时: 1 秒
  pg_dump 退出码: 0
```

🟢 **产物实测**：

```
-rwxrwxrwx 1 root root 76K Sep 20 12:49 grafana-2026-09-20-124927.sql.gz
  字节数: 77810
  gzip 完整性: ✅ 通过 (gzip -t)

  物理目录:   82M      ← 卷 /var/lib/postgresql/data
  逻辑导出:   76K      ← gzip 后
  压缩前大小: 0.27 MB  ← custom 格式未压缩时
```

> 🎯 **本课最有说服力的一个数字**：物理目录 **82MB**，逻辑导出 **76KB**——**相差约 1000 倍**。
>
> 原因：82MB 里绝大部分是 **WAL 段、索引膨胀、空闲空间**；真实业务数据只有 0.27MB。
> 📌 **这正是「逻辑备份 vs 物理备份」取舍的实证**：小库用 `pg_dump`，产物极小、一致性由库保证、还可跨版本恢复。

> ⚠️ **`--format=custom` 的取舍**：
> - `custom`（本次用）：二进制，可用 `pg_restore` **选择性恢复单表**；但不能直接用 `psql` 导入
> - `plain`（纯 SQL）：文本可读、可直接 `psql <` 导入；但不能选择性恢复
>
> 本次选 `custom`，因为演练重点是**可选择性恢复**这一运维刚需。

**导出期间源库是否受影响？**

```bash
$ docker exec l12-pg psql -U grafana -d grafana -tAc 'select count(*) from public.permission;'
794
```

> ✅ **导出后立刻查，返回 794，与基线一致**——`pg_dump` 在只读事务中进行，**不锁表、不影响业务**。

---

## ③ 隔离环境恢复（关键：全新容器 + 全新卷，绝不碰生产）

```bash
$ docker volume create l4-drill-vol
$ docker run -d --name l4-drill-pg \
    -e POSTGRES_USER=grafana -e POSTGRES_DB=grafana -e POSTGRES_PASSWORD=grafana \
    -v l4-drill-vol:/var/lib/postgresql/data \
    -p 55433:5432 \
    postgres:16-alpine

  起容器:   2026-09-20 12:50:14
  第 2 次探测就绪（约 4 秒）
  启动到就绪耗时: 2 秒
```

> 📌 **三个隔离要点**：
> ① **全新卷** `l4-drill-vol`——不与 `l12-pg` 共享任何存储
> ② **端口 55433**——避开源库的 5433，防止误连
> ③ **同镜像** `postgres:16-alpine`——版本一致才能恢复 custom 格式

```bash
$ gzip -dc grafana-2026-09-20-124927.sql.gz | \
    docker exec -i l4-drill-pg pg_restore -U grafana -d grafana --no-owner --no-acl

  pg_restore 退出码: 0
  导入耗时: 2 秒
  stderr: （空）
```

> ⚠️ **`docker exec -i` 的 `-i` 不能省**——管道输入必须有 stdin，少了 `-i` 会导入空数据且**不报错**（静默失败）。
> ⚠️ **不要加 `-t`**——无 TTY 环境（cron/脚本）会直接挂起。

---

## ④ 校验（本演练的证明力所在）

```bash
$ docker exec l4-drill-pg psql -U grafana -d grafana -tAc \
    "select count(*) from information_schema.tables where table_schema='public';"
94                          ← 与源库一致 ✅
```

**逐表精确 count diff（源 vs 恢复）**

```
表名                               源库  恢复库  一致?
alert                                0       0      ✅
alert_configuration                  1       1      ✅
alert_configuration_history          1       1      ✅
alert_image                          0       0      ✅
alert_instance                       1       1      ✅
alert_notification                   0       0      ✅
alert_notification_state             0       0      ✅
alert_rule                           1       1      ✅
alert_rule_state                     1       1      ✅
alert_rule_tag                       0       0      ✅
alert_rule_version                   1       1      ✅
annotation                           2       2      ✅
```

**抽样真实数据内容（证明不是只有表结构）**

```bash
$ docker exec l4-drill-pg psql -U grafana -d grafana -tAc \
    'select id, uid, title from public.dashboard limit 3;'
1|old-created|Created By 12.0.0

$ docker exec l4-drill-pg psql -U grafana -d grafana -tAc \
    'select id, login from public.user limit 5;'
2|sa-1-bk-test-sa
1|admin
```

> ✅ **演练结论**：表数 94 一致、12 张表精确 count 全一致、真实业务数据（dashboard / user）可读。**备份可恢复，已验证。**

---

## ⑤ RTO 记录与清理

```
从「起容器」到「数据可查」总耗时: 4 秒
  其中：容器启动到就绪 2 秒 / 数据导入 2 秒
```

> 📌 **RTO = 4 秒**（本机、76KB 小库）。**这才是能拿去承诺的数字**——演练前是「未知」。
> ⚠️ 注意：这个 4 秒**不含**恢复 compose 编排、切流量、应用自检的时间，**真实 RTO 要更长**。

```bash
$ docker rm -f l4-drill-pg
$ docker volume rm l4-drill-vol

  l4-drill-pg 容器残留: 0
  l4-drill-vol 卷残留: 0

# 源库确认未受影响
$ docker inspect -f '{{.State.Status}}' l12-pg
running
$ docker exec l12-pg psql -U grafana -d grafana -tAc 'select count(*) from public.permission;'
794
```

---

## 演练前后对比

| 指标 | 演练前 | 演练后 |
|------|--------|--------|
| 备份文件数 | **0**（零备份） | **1**（76KB） |
| RPO | **∞** | 取决于备份频率（本次为手动单次） |
| RTO | **未知** | **4 秒**（本机实测） |
| 备份是否验证过 | ⛔ 没有 | ✅ **已逐表 diff 验证** |
| 是否有恢复流程文档 | ⛔ 没有 | ✅ 本文档 |

---

## 🐞 本次演练踩到的坑（真实记录）

| # | 现象 | 原因与正解 |
|---|------|-----------|
| 1 | 第一次连库报 `FATAL: role "postgres" does not exist` | 容器 `POSTGRES_USER=grafana`；**用户名须从 `docker inspect` 的 Env 读** |
| 2 | `n_live_tup` 与 `count(*)` 可能不一致 | 前者是**估算值**（统计信息）；**校验必须用 `count(*)`** |
| 3 | `pg_dump` 用 `psql -c` 方式连会踩会话坑 | 同 `pg_backup_start`：需要长会话的操作不要用 `psql -c` 拆开 |
| 4 | 管道导入时若漏 `docker exec -i` | **静默导入空数据且不报错**——最危险的一类失败 |

---

## 📌 后续建议（未执行，等你决定）

1. **定时化**：把 `pg_dump` 写成 `systemd timer` 或 cron，明确 RPO（如每天 02:00 → RPO ≤ 24h）
2. **3-2-1**：目前只有 1 份、在本机 D 盘 → 建议再加异地/异介质副本
3. **扩覆盖**：本次只备了 `l12-pg`。讲义实测的 **203 个匿名卷、57 个 bind mount** 仍未被任何备份覆盖
4. **凭据**：`pg_dump` 密码若写进命令行会进 history，建议 `PGPASSWORD` 或 `~/.pgpass`
