# 课 15 实验原始输出汇总

> 环境：PostgreSQL 17.11（Docker `postgres:17`）/ macOS arm64 / 主库容器 `pg17`（5433）/ 从库容器 `pg17-standby`（5435）/ 级联从库 `pg17-standby2`（5436，实验后删除）。
> 时间：2026-09-11。脚本：[`l15_labs.sh`](l15_labs.sh)。编号与正文实验总览表一一对应。

## A 组 · 从库搭建

### A1 主库三件套默认值（开箱即满足）

```text
 replica
 10
 10
```

### A2 pg_basebackup -R 产物（三块积木）

```text
2378493/2378493 kB (100%), 1/1 tablespace        # 2.27 GB，--checkpoint=fast，14 秒
```

- `standby.signal`：存在（空文件，由 -R 自动创建）
- `postgresql.auto.conf` 追加行（-R 自动写入）：

```text
primary_conninfo = 'user=replicator password=*** host=host.docker.internal port=5433 ...'
primary_slot_name = 'l15_slot'                    # 使用 --slot 时才有
```

### A3 复制建立（主从两侧视角）

从库：

```text
 t  | 1/1C000060          # pg_is_in_recovery()=t
```

主库 `pg_stat_replication`：

```text
  pid  | usename    | application_name |   client_addr   |   state   | sync_state | sent_lsn   | replay_lsn
 28757 | replicator | walreceiver      | 169.254.169.254 | streaming | async      | 1/1C000060 | 1/1C000060
```

> application_name 默认 = `walreceiver`（官方：cluster_name 未设时的默认值）。sent_lsn = replay_lsn = 实时追平。

### A4 写入即达

```text
主库: INSERT 0 1
从库读到: |  1 | 主库刚写的订单          # 无 sleep 直查，异步流复制毫秒级
主库当前LSN:  1/1C029070
从库已重放LSN: 1/1C029070                 # 完全一致
```

### A5 walreceiver 视角（pg_stat_wal_receiver）

```text
 pid |  status   |     sender_host      | sender_port | slot_name | written_lsn | latest_end_lsn
 127 | streaming | host.docker.internal |        5433 |           | 1/1C000060  | 1/1C000060
```

## B 组 · 同步复制

### B1 application_name 改名后主库可见

```text
 application_name |   state   | sync_state
 standby1         | streaming | async
```

### B2′ 实测发现：synchronous_standby_names 不能 session SET

```text
ERROR:  parameter "synchronous_standby_names" cannot be changed now
```

（它是 sighup 级参数——只能改配置文件 + `pg_reload_conf()`；synchronous_commit 才是 user 级可 SET。）

### B2 同步复制开启后四档延迟（同一会话顺序实测）

```text
SET synchronous_commit = 'local';        INSERT → Time: 2.372 ms
SET synchronous_commit = 'on';           INSERT → Time: 5.177 ms   # 等远端 flush，一次网络往返
SET synchronous_commit = 'remote_write'; INSERT → Time: 1.798 ms
SET synchronous_commit = 'remote_apply'; INSERT → Time: 2.016 ms
 application_name | sync_state |    write_lag    |    flush_lag    |   replay_lag
 standby1         | sync       | 00:00:00.000731 | 00:00:00.001029 | 00:00:00.001124
```

> 单次 INSERT 有毫秒级抖动；方向正确（on = 本地 flush + 远端 flush 往返最贵）。三 lag 列在 sync_state=async 时为 NULL，转为 sync 后开始有值。

### B3 从库没了 → 同步提交挂起

```text
server stopped
walsender_剩余: 0
timeout 6 … INSERT → 6.671 s 被杀，无输出（挂起中）
id=301 是否已提交: 0        # 当时未提交
timeout 4 … UPDATE → 4.021 s 被杀    # 其他会话同样卡（挂起是全局的）
```

### B4 in-doubt 事务：客户端被杀 ≠ 回滚

从库拉起 3 秒后重插 id=301：

```text
ERROR:  duplicate key value violates unique constraint "replication_demo_pkey"
DETAIL:  Key (id)=(301) already exists.
```

> B3 里被 timeout 杀掉的 INSERT 在从库恢复确认后**最终提交**了——同步等待中的提交不可被客户端取消（取消只对执行阶段有效，commit 等待阶段事务已 in-doubt）。

## C 组 · 复制槽

### C1 无槽基线

```text
槽数: 0        wal_keep_size: 0（默认，不给从库留任何额外 WAL）
```

### C2 无槽 + 停从库 + 写 WAL → checkpoint 回收

```text
从库落后字节: 83885984（80 MB）
写 200 万行 wal_filler ≈ 200 MB WAL
checkpoint 前: 52 段 / 816 MB
checkpoint 后: 38 段 / 592 MB            # 回收 14 段
主库日志: checkpoint complete: … 0 WAL file(s) added, 14 removed, 0 recycled …
起从库后主库日志（连续重试）:
ERROR:  requested WAL segment 000000010000000100000021 has already been removed
```

### C3 有槽对照（--slot=l15_slot 重建从库后）

```text
 slot_name | slot_type | active | restart_lsn | wal_status
 l15_slot  | physical  | t      | 1/2F000000  | reserved
停从库 → 写 200 万行 → CHECKPOINT:
checkpoint 后: 38 段 / 592 MB            # 段数纹丝不动（对照无槽时回收 14 段）
 l15_slot | f | 1/2F000060 | reserved    # restart_lsn 钉在原地
从库拉起追平后:
 l15_slot | t | 1/3B000000  | reserved    # restart_lsn 随消费推进
```

## C4 级联复制（standby2 从 standby 拉 basebackup）

继承坑：standby2 的 auto.conf 同时出现两行 primary_conninfo（继承的 port=5433 + 本次 port=5435）与 `primary_slot_name='l15_slot'`——standby 上没有该槽 → walreceiver 反复失败（pg_stat_wal_receiver 0 行）。删除 slot 行与旧行 conninfo 后 pg_reload_conf() 恢复。

```text
主库可见: | walreceiver      | streaming      # 主库只见直接下游（官方：Only directly connected standbys are listed）
standby下游数: |     1                      # standby 一收一发（cascading standby）
standby2连到: | host.docker.internal | 5435 | streaming
主库写 id=401 → standby2 立即读到 | 401 | 经级联到达第三台
```

## D 组 · 切换与分叉

### D1 promote

```text
 pg_promote
------------
 t
 pg_is_in_recovery | 1/3D000838
 f                 |                # 已脱离恢复态
ls standby.signal → No such file or directory    # 自动删除
旧主5433 timeline: | 1
新主5435 timeline: | 2
 l15_slot  | f |                   # 主库上的槽转 inactive
```

### D2 级联从库自动跟随新主

```text
 standby2: | 5435 | streaming      # recovery_target_timeline=latest 默认生效
```

### D3 脑裂分叉（旧主未停机）

```text
旧主写入 id=501 → 新主5435 count: 0
新主写入 id=502 → 旧主5433 count: 0
```

> 两台"主"各自演化、互不知晓。这就是 15.3 里"方案 A 手动切换最容易翻车"的实证，也是 Patroni 这类工具必须做 fencing 的原因。

## 环境复位（实验后）

- 删除 standby2（容器 + volume）
- standby 重新 basebackup（--slot=l15_slot）回主库 timeline 1，恢复"主 5433 / 从 5435"基线
- 验证：从库能读到 id=501（旧主分叉行），没有 id=502（新主分叉行）
- `finance.wal_filler` 脚手架表已删除

## 一次性踩坑清单（正文「常见误区」素材）

1. 容器间 Docker 网桥直连报 `Cannot assign requested address`（Docker Desktop 29.4.1 / macOS）→ 统一走 `host.docker.internal` + 宿主端口映射
2. pg_hba 漏 replication 行：报 `no pg_hba.conf entry for replication connection from host "169.254.169.254"`（经宿主映射进来的源 IP 是 Docker VM 的 link-local 地址）
3. `docker exec` 非 -i 时 heredoc 不进 stdin（psql 静默无输出）
4. `psql -c "ALTER SYSTEM …; SELECT …;"` 把两条语句包进单事务 → `ALTER SYSTEM cannot run inside a transaction block`
5. `synchronous_standby_names` 不能 SET（只能 ALTER SYSTEM + reload）
6. standby2 继承上游的 primary_slot_name → 槽不存在 → walreceiver 反复重试（连报错都不进主库日志，只能看 walreceiver 状态反推）
