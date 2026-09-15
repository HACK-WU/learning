# 阶段 5 · 备份恢复、复制、监控与安全实验（课 14–17）

本目录存放课 14 的**真实运行**实验脚本与原始输出，用于：
1. 正文里每段 `console` / `sql` 输出都能回溯到一次真实运行（实测证据闸门）；
2. 换机器 / 重装环境后一键复现同一组证据。

## 环境要求

```bash
export PATH="/usr/local/bin:$PATH"   # docker 在 /usr/local/bin
docker start pg17                     # PostgreSQL 17.11，端口 5433
```

- 库 `order_service`（约 **661 MB**，`finance` schema 24 张表，含课 8 建的 100 万行 `orders_big`）
- **课 14 起需要归档能力**：`wal_level=replica`（默认）、`full_page_writes=on`（默认）已满足；
  需新增 `archive_mode=on` + `archive_command`，并 **`docker restart pg17`**（`archive_mode` 是 server start 级参数）
- 本地 `pg_hba.conf` 必须允许复制连接（官方镜像默认 `local replication all trust`，已满足）

## 脚本 ↔ 正文实验编号对照

| 脚本 | 覆盖实验 | 关键结论 | 输出存档 |
|---|---|---|---|
| `l14_exp1_logical_backup.sh` | A / B / C | 四种格式体积对照；`pg_restore` 读不了 plain；`-e` 与默认的差异；`-t` 不恢复依赖对象；`--clean --if-exists`；`pg_dumpall` 补全局对象 | `out_l14_exp1a~1f_*.txt` |
| `l14_exp2_physical_backup.sh` | D-1 ~ D-6 | `pg_basebackup` 全量备份（2.0 GB → 447 MB / 41.5 s）；tar 需解包才能 `pg_verifybackup`；backup_manifest / backup_label；开启 WAL 归档 | `out_l14_exp2a~2d_*.txt` |
| `l14_exp3_pitr.sh` | E-1 ~ E-12 | **PITR 完整演练**：删表 → 恢复到删除前那一刻；timeline 1→2；`recovery.signal` 自动删除；目标设错的静默失败对照 | `out_l14_exp3a~3e_*.txt` |
| `l15_labs.sh` | A1~A5 / B1~B4 / C1~C4 / D1~D3 | **真容器主从流复制全链路**：一条 `pg_basebackup -R` 变从库；同步复制四档延迟（on 5.177 ms）；从库没了 → 写事务全局挂起 + in-doubt 提交实证；无槽回收 WAL 14 段 vs 有槽 0 段；级联三台；promote 后 timeline 1→2 + 双主分叉 | `out_l15_full.md` |
| `l16_labs.sh` | A1~A5 / B1~B2 / C1~C2 / D1~D3 / E1~E3 / F1~F2 | **监控全链路实测**：巡检五件套（命中率 98.45%）；统计延迟 0→force→1000；三态合影（idle in transaction/ClientRead vs active/Lock）；pg_stat_io bulkread 13.6% vs normal 99.9%；800 万行 VACUUM 进度条；auto_explain LOAD 抓并行计划；**从库冲突分流 confl_lock vs confl_snapshot** | `out_l16_full.md` |
| （课 17 实验合并记录） | A1~A3 / B1~B4 / C1 / D1 | **RLS 四象限全实测**；trusted 双对照（permission denied + HINT）；50 连接 +787 MB；postgres_fdw 跨库打通；**pg_upgrade 不转移统计**（官方原文推翻备课误记） | `out_l17_full.md` |

## 课 15 的核心实测数字（PG 17.11 / 2026-09-11）

| 项目 | 数值 |
|---|---|
| 从库搭建耗时 | 2.27 GB 数据目录 `pg_basebackup -R --checkpoint=fast` **14 秒** |
| 复制用户 / 槽上限默认值 | `max_wal_senders=10`、`max_replication_slots=10`、`wal_keep_size=0` |
| 同步四档单次 INSERT | local 2.372 ms / **on 5.177 ms** / remote_write 1.798 ms / remote_apply 2.016 ms（容器同机，抖动毫秒级） |
| 同步复制挂起实测 | 停从库后写事务 **6.67 s 未返回**（timeout 杀）；其他会话 UPDATE 同样 4.0 s 卡死（**全局挂起**） |
| in-doubt 提交 | 客户端被杀的同步事务，从库恢复后**最终落地**（复插同主键报 duplicate key） |
| 无槽代价 | checkpoint 回收 **14 个 WAL 段**（52→38 段）→ 从库 `ERROR: requested WAL segment … has already been removed` |
| 有槽对照 | 停从库 + 写 200 MB WAL + CHECKPOINT → **38 段不变**（restart_lsn 钉住） |
| promote | timeline **1 → 2**；`standby.signal` 自动删除；主库槽转 inactive |
| 级联 | 主库只见直接下游 1 行；standby 一收一发；standby2 经 5435 级联读写立即可达 |

## 课 15 的踩坑清单（正文「常见误区」与复现指引）

1. **本机容器间 Docker 网桥直连报 `Cannot assign requested address`**（Docker Desktop 29.4.1 / macOS）——统一改走 `host.docker.internal` + 宿主端口映射。
2. **pg_hba 必须显式放行 replication 数据库 + 来源 IP**：经宿主映射进来的源 IP 是 `169.254.169.254`（Docker VM link-local），报错原文 `no pg_hba.conf entry for replication connection from host "169.254.169.254"`。
3. **`synchronous_standby_names` 不能 SET**（实测 `cannot be changed now`），只能 `ALTER SYSTEM` + `pg_reload_conf()`；`synchronous_commit` 才是会话级可切。
4. **`psql -c` 多语句 = 单事务** → `ALTER SYSTEM cannot run inside a transaction block`（与课 12 `VACUUM` 报错同族）。
5. **级联从库会继承上游的 `primary_slot_name`**，但槽只存在于链头主库—— walreceiver 反复重试且不进上游日志，只能从 `pg_stat_wal_receiver` 为空反推。

## 课 14 的核心实测数字（PG 17.11）

| 项目 | 数值 |
|---|---|
| 源库大小 | 661 MB（数据目录 3.0 G） |
| `pg_dump -Fp`（plain） | 158 MB |
| `pg_dump -Fc`（custom，默认 gzip） | 45 MB |
| `pg_dump -Fd -j 4`（directory） | 45 MB，1.16 s |
| `pg_dump -Ft`（tar） | **158 MB（完全不压缩）** |
| `pg_basebackup -Ft -z` | 447 MB（含 `base.tar.gz` 446 M + `pg_wal.tar.gz` 17 K + manifest 376 K），41.5 s |
| 完整恢复到新库（`-j 4`） | 4.1 s，24 张表 / 100 万行校验通过 |
| 重复恢复错误数 | 不加 `-e`：**113** 个；加 `-e`：**1** 个（立即停） |
| 备份清单 | Version 2，System-Identifier 7682798685620764710，**2633** 个文件，CRC32C |
| PITR 恢复耗时 | 从起实例到 `archive recovery complete` ≈ **0.06 s**（WAL 量小） |

## ⚠️ 三个踩过的坑（写脚本时务必注意）

1. **`tar` 格式的备份不能直接 `pg_verifybackup`**：tar 是压缩包，清单里的文件"不在磁盘上"。
   必须先 `tar -xzf` 解包（并把 `backup_manifest` 放进解包目录）再校验——正文 D-3/D-4 即此对照。
2. **`pg_basebackup` 会在 `waiting for checkpoint` 处停顿**：要给足超时（本文实测 41.5 s，给 60 s 会中途被掐断）。
   跑之前先 `CHECKPOINT;` 可显著缩短等待。
3. **`createdb` / `dropdb` 不会自动用 `-U postgres`**：容器内以 root 执行会报
   `FATAL: role "root" does not exist`。三个命令都要显式带 `-U postgres`。

## 关于 `-e` 的精确语义（正文 14.1⑤ 引用）

`pg_restore` **默认不中止**（把整份归档跑完，最后汇总 `errors ignored on restore: N`），
但**最终退出码仍为非 0**（实测 1）。`-e/--exit-on-error` 的差别不在退出码，而在**是否继续**：
实测同一份重复恢复，不加 `-e` 报 **113** 个错、加 `-e` 只报 **1** 个就停。

## 保留的运行态产物（容器内，不在本目录）

- `/var/lib/postgresql/l14_backup`（2.1 G）—— plain 格式基础备份，**保留供课 15《复制与高可用》复用**
- `/var/lib/postgresql/backup`（2.5 G）—— tar 格式备份 + 解包目录
- `/var/lib/postgresql/archive`（65 M）—— WAL 归档目录，课 15 做流复制时可对照
- 演练用的 `restore` / `restore2` 目录**已删除**（占空间且可随时重建）
