# Task 4：生产化 —— 副本、隔离、变更、备份

> **目标**：把 Task 1-3 建好的数仓，推到"能在生产上过夜"的状态。

**锚定课程**：课 9（副本、高可用、扩缩容）、课 10（Workload Group）、课 11（Schema Change、备份恢复）

**前置**：Task 3 已完成

---

## 1. 生产化的四件事

| # | 事项 | 锚定 | 本机可验证性 |
|---|------|------|-------------|
| 1 | 副本策略 | 课 9 | 🟡 能建 2 副本，但同主机无法验证抗宕机 |
| 2 | 资源隔离 | 课 10 | 🟡 能建组，但 cgroup 只读导致 CPU 限额不生效 |
| 3 | Schema 变更 | 课 11 | 🟢 完全可验证 |
| 4 | 备份恢复 | 课 11 | 🟢 完全可验证 |

---

## 2. 副本策略（课 9）

### 2.1 本项目的副本现状

```bash
docker exec -i doris-learn mysql -h 127.0.0.1 -P 9030 -uroot -e "
SHOW BACKENDS\G" | grep -E "Host:|HeartbeatPort:|Alive:|TabletNum:"
```

🟢 **实测**：

```
Host: 127.0.0.1     HeartbeatPort: 9050     Alive: true    TabletNum: 3757
Host: 127.0.0.1     HeartbeatPort: 19050    Alive: true    TabletNum: 2932
```

**两台 BE 的 host 都是 `127.0.0.1`** —— 这是课 9 用不同端口在同一容器里拉起的"伪多节点"。

#### 2.1.1 ⚠️ 副本数该怎么查（Phase 3 实测踩坑）

想查"每张表当前几个副本"，直觉写法是：

```sql
SELECT DISTINCT REPLICATION_NUM FROM information_schema.partitions
WHERE TABLE_SCHEMA='dw' AND TABLE_NAME='dwd_orders';
```

❌ **实测报错**：

```
ERROR 1105 (HY000): Unknown column 'REPLICATION_NUM' in 'table list' in PROJECT clause(line 1, pos 16)
```

`information_schema.partitions` **根本没有这一列**。

✅ **正确写法**：从 `SHOW CREATE TABLE` 的 `replication_allocation` 取：

```bash
docker exec -i doris-learn mysql -h 127.0.0.1 -P 9030 -uroot dw -e \
  "SHOW CREATE TABLE dwd_orders\G" | grep -oE '"replication_allocation" = "[^"]*"'
# → "replication_allocation" = "tag.location.default: 1"
```

🟢 **五张表实测全部为 `tag.location.default: 1`**（1 副本）。

> **方法论**：`information_schema` 的列名在不同 Doris 版本间差异很大，
> 不要凭记忆写。拿不准时先 `DESC information_schema.partitions` 看有哪些列，
> 或者直接改用 `SHOW` 系列语句 —— `SHOW` 的输出虽然不好解析，但列是稳定的。

### 2.2 ⚠️ 本机无法验证的核心能力

| 能力 | 状态 | 原因 |
|------|------|------|
| 建 2 副本表 | 🟢 可以 | 2 台 BE 满足副本数要求 |
| **多副本抗宕机** | 🔴 **无法验证** | 同主机反亲和规则不允许 |

课 9 实测过这个限制：

```
Failed to find enough backend ... or maybe all be on same host
```

> **反亲和规则**：Doris 默认不会把同一个 tablet 的多个副本放在**同一台主机**上，
> 因为那样主机一挂，所有副本一起没。**这是正确的设计**，但它让本机（2 BE 同 host）
> 无法演示"3 副本 + 宕 1 台 → 查询不断"。

### 2.3 副本数怎么定（生产决策）

| 副本数 | 适用 | 代价 |
|--------|------|------|
| 1 | 开发/测试、可重建的数据 | 节点挂了数据不可用 |
| 2 | 数据量极大的冷数据 | 只能扛 1 台故障，且**写入可用性下降** |
| **3** | **生产默认** | 3 倍存储，能扛 1 台故障 + 1 台维修中再坏 1 台 |

> **课 9 的关键结论**：3 副本不只是"存 3 份"，它保证的是**任意时刻坏 1 台，
> 集群仍能正常写入且不丢数据**。2 副本在坏 1 台后，剩下那台要同时承担读写，
> 且**没有冗余了** —— 这时候再来一次故障就是数据丢失。

**本项目的副本决策**：

| 层 | 副本数 | 理由 |
|----|--------|------|
| ODS | 1（本机）→ **3（生产）** | 可从 S3 重建，但重建耗时，生产仍建议 3 |
| DWD | 1（本机）→ **3（生产）** | 核心层，去重成本高，**必须 3** |
| DWS | 1（本机）→ **3（生产）** | 数据量小（96 行），3 副本代价可忽略 |
| ADS | 1（本机）→ **3（生产）** | 报表直接读，必须高可用 |
| DIM | 1（本机）→ **3（生产）** | 维表参与 Join，缺了整个链路挂 |

> ⚠️ **坑（课 11）**：`RESTORE` 时 `replication_num` **默认是 3，不沿用原表**。
> 而且它**不报错** —— 失败信息藏在 `SHOW RESTORE` 的 Status 列里。见第 5.3 节。

---

## 3. 资源隔离（课 10）

### 3.1 为什么要隔离

数仓上会有两类负载混跑：

| 负载 | 特点 | 风险 |
|------|------|------|
| 报表查询（ADS 层） | 秒级返回，并发高 | 被大查询拖慢 |
| 数据加工（ODS→DWD） | 跑几分钟，吃内存 | **一个大查询拖垮整个集群** |

Workload Group 的作用：**给不同负载划定资源上限，互不影响**。

### 3.2 建两个资源组

```sql
-- 报表查询组：延迟敏感，允许高并发，但限制单查询内存
CREATE WORKLOAD GROUP IF NOT EXISTS wg_report
PROPERTIES (
  'max_memory_percent' = '40',
  'max_concurrency'    = '20',
  'max_queue_size'     = '50',
  'queue_timeout'      = '30000'
);

-- 数据加工组：吞吐优先，并发低，内存可以大
CREATE WORKLOAD GROUP IF NOT EXISTS wg_etl
PROPERTIES (
  'max_memory_percent' = '60',
  'max_concurrency'    = '3',
  'max_queue_size'     = '10',
  'queue_timeout'      = '300000'
);
```

### 3.3 ⚠️ 本机实测：CPU 配额完全不生效

```bash
# 容器 cgroup 是只读挂载
mount | grep cgroup
# → cgroup on /sys/fs/cgroup type cgroup2 (ro,...)
```

课 10 实测的数据：

| 资源组 | CPU 配额 | 实测耗时 |
|--------|---------|---------|
| 100% 组 | `max_cpu_percent=100` | 1.42 / 1.60 / 1.46 秒 |
| 5% 组 | `max_cpu_percent=5` | 1.03 / 1.00 / 1.18 秒 |

**受限组反而更快** —— 说明配额完全没生效，差异纯属噪声。

**本项目能验证什么、不能验证什么**：

| 能力 | 状态 |
|------|------|
| 建资源组 | 🟢 可验证 |
| 绑定用户/查询到组 | 🟢 可验证 |
| `max_concurrency` / `max_queue_size` / `queue_timeout` | 🟢 可验证（纯 FE 层逻辑）|
| `max_memory_percent` | 🟡 部分可验证 |
| **`max_cpu_percent` / `scan_thread_num`** | 🔴 **不生效**（cgroup 只读）|

### 3.4 验证：并发控制确实生效

CPU 测不了，但**并发控制是纯 FE 逻辑，能测**：

```bash
docker exec -i doris-learn mysql -h 127.0.0.1 -P 9030 -uroot -e "SHOW WORKLOAD GROUPS\G" \
  | grep -E "Name:|max_concurrency:|max_queue_size:|queue_timeout:"
```

🟢 **实测输出**：

```
Name: wg_report    max_concurrency: 20   max_queue_size: 50   queue_timeout: 30000
Name: wg_etl       max_concurrency: 3    max_queue_size: 10   queue_timeout: 300000
Name: normal       max_concurrency: 2147483647   max_queue_size: 0
```

### 3.5 ⚠️ 三个必踩的坑（课 10 + 本项目）

| # | 坑 | 现象 |
|---|-----|------|
| 1 | **废弃属性名** | `memory_limit` / `cpu_share` / `cpu_hard_limit` / `enable_memory_overcommit` / `tag` 全被废弃，报 `Property xxx is not supported, maybe it is deprecated` |
| 2 | **水位必须成对** | `memory_high_watermark` 必须 > `memory_low_watermark`（默认 75%），只设 70% 会报 `should bigger than memory_low_watermark(75)` |
| 3 | **最多 15 个组** | 超了报 `Workload group number in Compute Group default can not exceed 15`。排查时先 `SHOW WORKLOAD GROUPS` 数字数 |

> ⚠️ 还有一个隐蔽的：`SET workload_group` 后 `SELECT @@workload_group` **返回空字符串**，
> 不代表没生效。验证要去看 `SHOW WORKLOAD GROUPS` 的 `running_query_num` 列。

### 3.6 生产建议：spill 要显式打开

课 10 实测：`enable_spill` **出厂默认是 `false`**。

```
SHOW VARIABLES LIKE 'enable_spill';
-- Variable_name: enable_spill   Value: false   Default_Value: false   Changed: 0
```

**生产环境建议显式打开** —— 内存不够时落盘，而不是直接报错。

但课 10 也实测了 **spill 不是万能的**：

| 内存限制 | 结果 |
|---------|------|
| 128 MB | 直接报错（0.22 秒）|
| 256 MB | **挣扎 88.63 秒后仍报错** |
| 512 MB | 成功，但要 **480 秒** |
| 1024 MB | 成功，只要 **1.06 秒** |

**代价高度非线性，内存差太远时 spill 也救不了。**

---

## 4. Schema 变更（课 11）

### 4.1 🟢 加列（毫秒级）

```bash
docker exec -i doris-learn mysql -h 127.0.0.1 -P 9030 -uroot dw -e "
ALTER TABLE dwd_orders ADD COLUMN remark VARCHAR(64);"
```

🟢 **实测：立即返回，毫秒级。**

原因：`light_schema_change=true` 是 Doris 4.x 的**出厂默认值**，
加列只改 FE 元数据，不搬数据。

> ⚠️ **坑 1（Phase 3 实测）**：`ADD COLUMN IF NOT EXISTS` **不支持**！
>
> ```
> ERROR 1105 (HY000): no viable alternative at input 'ADD COLUMN IF'(line 1, pos 34)
> ```
>
> 幂等重跑时，直接执行、忽略"列已存在"的报错即可。

> 🔥 **坑 2（Phase 3 实测，比坑 1 严重得多）**：**加列时不要写 `DEFAULT`**。
> 写了 DEFAULT，这一列后面**永远改不动**（见 4.2）。

### 4.2 🔥 改列宽：能不能改，取决于加列时有没有写 DEFAULT

这一条是课 11 `Can not change default value` 的**完整复现**。课 11 只记了报错，
Phase 3 才把"为什么会撞上"和"怎么绕"彻底测清楚。

🟢 **正反对比实测**（同一张 `dwd_orders`）：

```sql
-- 路线 A：加列不写 DEFAULT → 改宽成功
ALTER TABLE dwd_orders ADD COLUMN remark VARCHAR(64);      -- 成功
ALTER TABLE dwd_orders MODIFY COLUMN remark VARCHAR(128);  -- 成功，无输出

-- 路线 B：加列写了 DEFAULT '' → 改宽两条路全堵死
ALTER TABLE dwd_orders ADD COLUMN remark_def VARCHAR(64) DEFAULT '';  -- 成功
ALTER TABLE dwd_orders MODIFY COLUMN remark_def VARCHAR(128);         -- ❌ 报错
ALTER TABLE dwd_orders MODIFY COLUMN remark_def VARCHAR(256) DEFAULT 'x'; -- ❌ 报错
```

两条 MODIFY 报的是同一个错：

```
ERROR 1105 (HY000) at line 1: errCode = 2, detailMessage = Can not change default value
```

🟢 **DESC 验证最终结果**：

```
remark      varchar(128)   Yes   false   NULL    NONE   ← 路线 A，改宽生效
remark_def  varchar(64)    ...                          ← 路线 B，卡死在 64
```

**为什么路线 B 的"不带 DEFAULT"也报错？** 因为该列在元数据里已经带了默认值，
`MODIFY COLUMN` 只要发现默认值前后不一致就拒绝 —— 你"不写 DEFAULT"等于
"默认值变成 NULL"，和原来的 `''` 不一致，一样拒绝。

**规避办法（四步）**：

```sql
ALTER TABLE dwd_orders ADD COLUMN remark_new VARCHAR(256);   -- 1. 加新列（不写 DEFAULT）
UPDATE dwd_orders SET remark_new = remark_def;               -- 2. 回填
ALTER TABLE dwd_orders DROP COLUMN remark_def;               -- 3. 删旧列
-- 4. 若必须保留列名，再走一次 加列→回填→删列（Doris 无 RENAME COLUMN）
```

> **给生产流程的一条硬规则**：**加列一律不写 `DEFAULT`**。
> 需要默认值时用 `UPDATE` 回填，或在导入/ETL 层处理。
> 省下这一行 DEFAULT，换回"以后还能改"的余地。

> ⚠️ **坑 3（Phase 3 实测）**：`DROP COLUMN IF EXISTS` 同样**不支持**：
>
> ```
> ERROR 1105 (HY000): mismatched input 'IF' expecting {...}
> ```
>
> 即 `ADD COLUMN` / `DROP COLUMN` 两端的 `IF EXISTS` 都没实现，
> 幂等重跑只能"直接执行 + 忽略报错"。

### 4.3 🟢 删列

```bash
docker exec -i doris-learn mysql -h 127.0.0.1 -P 9030 -uroot dw -e "
ALTER TABLE dwd_orders DROP COLUMN remark;"
```

🟢 **实测**：删 `remark`（路线 A）与 `remark_def`（路线 B）都成功，
删完 `dwd_orders` 行数不变（9999563），Schema 回到加列前。

> ✅ **这正好说明删列是"后悔药"**：4.2 里改不动的 `remark_def`，
> 靠"加新列 → 回填 → 删旧列"照样能换掉。四步法是可行的，
> 只是比 `MODIFY` 麻烦，且中间有短暂的"新旧列并存"窗口。
```

### 4.4 变更流程（生产规范）

```text
1. 在测试库执行 ALTER，确认语法与耗时
2. 低峰期执行（即使 light schema change 是毫秒级，
   但改完的查询计划会变，且 ADD COLUMN 后旧数据要有默认值）
3. 执行后立即验证：SELECT 新列、跑一遍核心查询
4. 观察 10 分钟监控（QPS、延迟、BE 内存）
5. 出问题立即回滚（DROP COLUMN / MODIFY 回去）
```

> ⚠️ **课 11 的两个坑**：
> - **`CANCEL ALTER` 只在作业进行中有效**。作业已 FINISHED 会报
>   `Table[xxx] is not under SCHEMA_CHANGE.`。而 light schema change 毫秒级完成，
>   **根本抓不到 CANCEL 窗口**。
> - **表处于 SCHEMA_CHANGE 时再 ALTER**，报
>   `state(SCHEMA_CHANGE) is not NORMAL. Do not allow doing ALTER ops`。

---

## 5. 备份与恢复（课 11）

### 5.1 建 S3 仓库

```bash
docker exec -i doris-learn mysql -h 127.0.0.1 -P 9030 -uroot -e "
CREATE REPOSITORY p3_repo
WITH S3 ON LOCATION 's3://doris-demo/p3backup/'
PROPERTIES (
  's3.endpoint' = 'http://minio:9000',
  's3.access_key' = 'minioadmin',
  's3.secret_key' = 'minioadmin',
  's3.region' = 'us-east-1',
  'use_path_style' = 'true'
);"
```

> ⚠️ **`CREATE REPOSITORY` 不支持 `IF NOT EXISTS`**（课 11）。
> 重复建同名仓库会报 `Repository [xxx] already exists`。
> 幂等做法：先 `DROP REPOSITORY`，忽略报错，再 `CREATE`。

### 5.2 备份

🟢 **脚本演示用 DWS 层**（96 行，几秒完成，便于反复重跑）：

```bash
docker exec -i doris-learn mysql -h 127.0.0.1 -P 9030 -uroot dw -e "
BACKUP SNAPSHOT p3_dws TO p3_repo ON (dws_prov_month);"
```

🟢 **实测**：`State=FINISHED`，96 行 / `SUM(total_amount)=25097795339.16`。

> **生产上应该备的是 DWD，不是 DWS** —— 理由见 5.4 的备份策略表
> （DWD 去重成本最高，DWS 可从 DWD 重算）。
> 这里演示用 DWS 纯粹是为了快，别把"演示选了谁"误读成"该备谁"。

**幂等重跑注意**：同名快照已存在时，备份会报

```
Snapshot with name 'p3_dws' already exist in repository
```

要先 `DROP SNAPSHOT p3_dws ON p3_repo` 再备份（该语句同样没有 `IF EXISTS`）。
```

### 5.3 ⚠️ 恢复：三个坑连在一起

```bash
# 1. 先看有哪些快照
docker exec -i doris-learn mysql -h 127.0.0.1 -P 9030 -uroot -e "
SHOW SNAPSHOT ON p3_repo;"

# 2. 恢复（必须显式写 replication_num=1，本机只有 2 台 BE）
docker exec -i doris-learn mysql -h 127.0.0.1 -P 9030 -uroot dw -e "
RESTORE SNAPSHOT dwd_20260903 FROM p3_repo
ON (dwd_orders AS dwd_orders_restored)
PROPERTIES (
  'backup_timestamp' = '2026-09-03-10-45-00',
  'replication_num'  = '1'
);"

# 3. 关键：查状态要 tail -1（默认第一条是最老的记录）
docker exec -i doris-learn mysql -h 127.0.0.1 -P 9030 -uroot dw -e "
SHOW RESTORE;" | tail -1
```

**四个坑（课 11 + Phase 3 全部实测）**：

| # | 坑 | 现象 |
|---|-----|------|
| 1 | **`replication_num` 默认 3 不沿用原表** | 语句提交时**不报错**，失败信息藏在 `SHOW RESTORE` 里：`replication num should be less than the number of available backends. replication num is 3, available backend num is 2` |
| 2 | **必须带 `backup_timestamp`** | 漏了报 `Missing backup_timestamp property`；值从 `SHOW SNAPSHOT ON <repo>` 取 |
| 3 | **`SHOW RESTORE` 要 `tail -1`** | 默认输出第一条是**最老**的记录，不是最新的 |
| 4 | **不能用 `awk` 按列号取 Status** | 见下 |

> 🔥 **坑 4 详解（Phase 3 实测）**：`SHOW RESTORE` 的输出里，Info 列是**一段
> 把换行转义成 `\n` 的 JSON**（分区名列表），它把整行的 tab 结构打乱，
> `awk -F'\t' '{print $14}'` 取到的 Status 是 `NULL`：
>
> ```
> col12=2026-09-03 10:45:01 | col13=NULL | col14=NULL
> ```
>
> ✅ **稳健取法**：别按列号取，用 `grep -oE` 直接抽关键句：
>
> ```bash
> ... -e "SHOW RESTORE;" | grep -oE "replication num should be less than[^\"\\\\]*" | head -1
> ```
>
> 状态字段（JobId / Label / State / ReplicAlloc）在前 8 列、JSON 之前，
> 用 `awk '{print $1, $2, $5, $8}'` 是安全的 —— **只有 JSON 之后的列不可信**。

> 还有一个：**一个库同一时刻只能跑一个 backup/restore 作业**。
> 连发两条，第二条报 `Currently, this DB is under backup or restore.`
>
> 以及：**同名快照重复备份会报 `Snapshot with name 'xxx' already exist in
> repository`**，需要先 `DROP SNAPSHOT <name> ON <repo>`（该语句没有 `IF EXISTS`）。

### 5.4 备份策略（生产建议）

| 层 | 备份频率 | 保留 | 理由 |
|----|---------|------|------|
| ODS | 不备份 | — | 源数据在 S3，可重建 |
| **DWD** | **每日全量 + 每小时增量** | 30 天 | **核心层，去重成本高，必须备份** |
| DWS | 每日 | 7 天 | 可从 DWD 重算 |
| ADS | 不备份 | — | 可从 DWS 重算 |
| DIM | 每日 | 90 天 | 数据量小，但缺了整个 Join 链路挂 |

> **原则**：**备份的是"重算成本高的层"，不是"数据量大的层"。**
>
> ODS 有 1000 万行但不备份（S3 里有原始数据）；DIM 只有 8 行但要备份
> （没了它所有 Join 全废）。

---

## 6. 执行

```bash
bash assets/phase3-task4-prod.sh
```

脚本会：建资源组 → 演示 Schema 变更 → 建备份仓库 → 备份 DWD → 恢复验证 → 清理。

---

## 7. 自查题

<details>
<summary>1. 为什么本机验证不了"多副本抗宕机"？</summary>

**因为两台 BE 的 host 都是 `127.0.0.1`，触发了 Doris 的反亲和规则。**

🟢 实测 `SHOW BACKENDS`：

```
Host: 127.0.0.1   HeartbeatPort: 9050    Alive: true
Host: 127.0.0.1   HeartbeatPort: 19050   Alive: true
```

课 9 为了能演示扩缩容，在同一个容器里用不同端口拉起了第二个 BE 进程（`/opt/be2`）。
**逻辑上是 2 个节点，物理上是同一台机器。**

Doris 的**反亲和规则**要求：同一个 tablet 的多个副本不能放在同一台主机上。
这是正确的设计 —— 如果放同一台，主机一挂所有副本一起没，多副本就没意义了。

所以请求 3 副本时会报：

```
Failed to find enough backend ... or maybe all be on same host
```

**想真正验证"3 副本 + 宕 1 台 → 查询不断"，需要至少 3 台真机（或 3 个不同 host 的容器）。**

> 课 9 的另一条遗留：`DROP BACKEND` 被拒绝，需**故意拼错成 `DROPP`** 才能执行 ——
> 这是 Doris 的防呆设计。
</details>

<details>
<summary>2. Workload Group 的 CPU 限额在本机为什么不生效？还能验证什么？</summary>

**因为容器的 cgroup 是只读挂载，Doris 没法写 cgroup 文件来限流。**

```bash
mount | grep cgroup
# → cgroup on /sys/fs/cgroup type cgroup2 (ro,...)
```

课 10 的实测数据很直观：

| 资源组 | CPU 配额 | 实测耗时 |
|--------|---------|---------|
| 100% 组 | `max_cpu_percent=100` | 1.42 / 1.60 / 1.46 秒 |
| 5% 组 | `max_cpu_percent=5` | 1.03 / 1.00 / 1.18 秒 |

**限到 5% CPU 的那组反而更快** —— 唯一合理的解释就是配额压根没生效。

**那还能验证什么？** 分层看：

| 能力 | 实现层 | 本机 |
|------|--------|------|
| `max_concurrency` / `max_queue_size` / `queue_timeout` | **纯 FE 逻辑**，不依赖 cgroup | 🟢 可验证 |
| `max_memory_percent` | BE 内存管理 | 🟡 部分可验证 |
| `max_cpu_percent` / `scan_thread_num` | **依赖 cgroup** | 🔴 不生效 |

**所以本项目的验证策略是**：建资源组、验证并发/排队参数能被正确接受，
**但不宣称验证了 CPU 隔离效果**。

> **方法论**：环境限制导致的"测不出来"，要**明确标注为 🔴 未实测**，
> 而不是编一个漂亮的数字。这是课 10 到课 12 一以贯之的原则。
>
> 若后续换成物理机或 cgroup 可写的容器，应回来补测。
</details>

<details>
<summary>3. RESTORE 提交成功但数据没恢复，怎么查？</summary>

**去 `SHOW RESTORE` 的 Status 列看，而且要 `tail -1`。**

这是课 11 最隐蔽的一个坑：**`RESTORE` 语句提交时不报错，失败信息藏在别处。**

🟢 实测会看到：

```
replication num should be less than the number of available backends.
replication num is 3, available backend num is 2
```

**根因**：`RESTORE` 的 `replication_num` **默认是 3，且不沿用原表的副本数**。
本项目的表是 1 副本，本机只有 2 台 BE —— 恢复到 3 副本必然失败。

**修复**：显式写 `'replication_num' = '1'`。

**还有两个连带的坑**：

1. **必须带 `backup_timestamp`** —— 漏了报 `Missing backup_timestamp property`，
   值从 `SHOW SNAPSHOT ON <repo>` 取
2. **`SHOW RESTORE` / `SHOW BACKUP` 取最新作业要 `tail -1`** ——
   默认输出里**第一条是最老的记录**，直接看会拿到过时的状态

> **这一条是"静默失败"的典型**：语句返回 OK，你以为成功了，
> 第二天才发现恢复的表是空的。**验证要看数据对不对，不只是看有没有报错。**
>
> 顺带一提：4.1.3 **没有 `DROP SNAPSHOT` 语句**，清理快照只能
> 「删仓库 + 物理清 S3 目录」。
</details>

<details>
<summary>4. 备份策略该按什么定？</summary>

**按"重算成本"定，不是按"数据量"定。**

| 层 | 数据量 | 重算成本 | 备份？ |
|----|--------|---------|--------|
| ODS | 1100 万行（最大）| **低** —— S3 里有原始 parquet | ❌ 不备份 |
| DWD | 1000 万行 | **高** —— 要从 ODS 跑窗口函数去重 | ✅ **必须备份** |
| DWS | 96 行 | 中 —— 从 DWD 聚合即可 | 每日 |
| ADS | 更少 | 低 —— 从 DWS 算 | ❌ 不备份 |
| DIM | **8 行（最小）** | **极高** —— 没了它所有 Join 全废 | ✅ **必须备份** |

**两个反直觉的点**：

1. **ODS 数据量最大，但不备份** —— 因为源数据在 S3 上，重建只是重跑一次导入。
2. **DIM 只有 8 行，但要备份** —— 因为它是所有 Join 的枢纽，
   一旦丢失，DWS/MV/ADS 全部失效。**数据量小 ≠ 不重要。**

**备份的基本原则**：
- **备份的是"丢了会很痛且难以重建"的东西**
- **能从上游重算的层，备份的价值低于"重算脚本的可靠性"**
- **维表/配置表永远要备份，不管多小**

> 生产上还要加一条：**验证恢复**。备份没验证过，等于没备份。
> 建议每月做一次恢复演练，恢复到测试库后跑数据对账。
</details>

---

## 🚀 下一步

Task 5：[验收与边界](./task-5-验收与边界.md)
