import io

base = '/mnt/d/projects/learning/doris/'

# ---------- 1. 00-学习档案.md：环境状态 + 课 7 遗留待办 ----------
p = base + '00-学习档案.md'
s = io.open(p, encoding='utf-8').read()

old_env = '课 6 新增：`load_demo`、`s3_orders_ext`、`kafka_orders`、`uniq_load_demo`（均在 `shop` 库）。'
new_env = ('课 6 新增：`load_demo`、`s3_orders_ext`、`kafka_orders`、`uniq_load_demo`（均在 `shop` 库）。'
           '课 7 新增：`perf_wide`（200 万行，8 字段含 3 个 500B 填充列，磁盘仅 5.17 MB）、'
           '`perf_wide_big`（400 万行，scale 对照用）——课 8 可直接复用做 Join 实验，无需再造数据。')
assert old_env in s, 'env anchor not found'
s = s.replace(old_env, new_env)

old_todo = '- **课 6 遗留待办**：'
new_todo = (
    '- **课 7 遗留待办**：'
    '① 全局设置当前为 `enable_profile=true`、`enable_sql_cache=false`（课 7 实验留下的），'
    '课 8 测完记得恢复 `SET GLOBAL enable_sql_cache = true`；'
    '② **向量化开关 `enable_vectorized_engine` 在本机测不出差异**'
    '（关：20/18/15ms，开：18/17/17ms；扫宽列 191ms vs 189/214ms）——'
    'Doris 4.x 已全面向量化，该开关是历史遗留，两种设置下算子名都是 `OLAP_SCAN_OPERATOR`。'
    '结论已诚实写入讲义，用 `BlocksProduced`/`batch_size` 作机制证据，未编造性能数字；'
    '③ 课 7 实测确认 **Profile 抓取三板斧**：`SET GLOBAL enable_profile=true` → '
    '`SHOW QUERY PROFILE \'/\'` 按 SQL 文本 grep 取 QID（避开 mysql 探针 `select @@version_comment limit 1`）→ '
    '`curl -s -u root: "http://127.0.0.1:8030/api/profile?query_id=$QID"` 抓正文'
    '（`SHOW QUERY PROFILE \'/<QID>\'` 只列目录，试了 5 种写法均无效）；'
    '④ **`docker exec` 管道传 SQL 必须带 `-i`**——不带时静默无输出、失败不报错，课 7 setup 脚本踩到，已修；'
    '⑤ **`SHOW DATA` 紧跟 INSERT 返回 0**（后台统计延迟约 45 秒），需 sleep 后再查\n'
    '- **课 6 遗留待办**：'
)
assert old_todo in s, 'todo anchor not found'
s = s.replace(old_todo, new_todo, 1)

io.open(p, 'w', encoding='utf-8').write(s)
print('archive env/todo done')

# ---------- 2. overview.md：勾选产出 + 阶段状态 + 核心结论 ----------
p = base + 'stages/3-数据导入与查询/overview.md'
s = io.open(p, encoding='utf-8').read()

old = '- [ ] `lessons/lesson-07-查询引擎与执行计划.md`'
new = '- [x] `lessons/lesson-07-查询引擎与执行计划.md`'
assert old in s, 'overview checkbox not found'
s = s.replace(old, new)

old = '**进行中**（课 6 已完成，2026-09-02；课 7 / 课 8 待交付）'
new = '**进行中**（课 6、课 7 已完成，2026-09-02；课 8 待交付）'
assert old in s, 'overview status not found'
s = s.replace(old, new)

concl = """

### 课 7《查询引擎与执行计划》核心结论（2026-09-02）

**第一原则：看账单，不看计划。** EXPLAIN 是计划（打算怎么花钱），Profile 是账单（钱花在哪了）。
优化查询永远要看账单。判据只有一条：**`ExecTime` 大 = 它自己慢，`WaitForDependency` 大 = 它的上游慢**。
读反了就会去优化一个 `ExecTime` 只有 18 微秒、却等了 196 毫秒的聚合算子——那是南辕北辙。

**实测最硬的一组数字**（同一张表、同样 200 万行、同样 `COUNT+SUM`，只改 SELECT 的列）：

| | 扫 1 个窄列 | 扫 3 个 500B 宽列 | 倍数 |
|---|---|---|---|
| `ScanBytes`（磁盘读） | 15.26 MB | 22.92 MB | **1.5×** |
| `OutputBlockBytes`（送出去） | 15.26 MB | **2.82 GB** | **185×** |
| Scan `ExecTime` | 3.1 ms | 163.7 ms | **52×** |
| `Total` | 15 ms | 192 ms | **13×** |

**瓶颈不在磁盘 IO，在解压、内存拷贝、传递。** 磁盘读只多 1.5 倍，耗时却多 52 倍。
这个结论直接推翻"扫描慢就去买更快的 SSD"的直觉——钱应该花在**少扫几列**上。

**列存 + 向量化是天生一对**：列存让同列数据在磁盘/内存里连续，向量化把它切成 Block 批量处理
（实测 200 万行切 264 块 ≈ 7576 行/块，`batch_size` 上限 8160；宽列因每块塞满 8 MB 而切 368 块）。
200 万行、逻辑约 2.9 GB 的表，磁盘只占 **5.17 MB**（压缩约 550 倍，刻意构造的极端值，真实业务约 3–10 倍）。

**三个"本机测不出"，已诚实标注，不要拿去当普遍规律**：
1. **向量化开关无效**——Doris 4.x 已全面向量化，开关是历史遗留（关 18ms / 开 17ms，无差异）。
   向量化的价值要用 `BlocksProduced` / `batch_size` 这类**机制证据**说明，不是开关对比。
2. **调大 `parallel_pipeline_task_num` 不提速**——Scan 单次 `ExecTime` 从 16.26ms 降到 2.85ms（5.7 倍），
   但查询 `Total` 192ms → 191ms 几乎没变。证据：Scan 的 `RowsProduced` 里 `sum = max = 2.0M`，
   **扫描器只有 1 个**，它是木桶上最短的那块板。这是单机单 BE 的结论，多 BE 集群上不成立。
3. **MPP 横向扩展能力**——只有 1 台 BE，没有横向可言。

**给课 8 的资产**：Profile 抓取三板斧已跑通（课 5 曾失败）；
`HASH_JOIN_OPERATOR` 与 `runtime filters: RF000[min_max]` 的 EXPLAIN 输出已看到，课 8 展开原理。
"""
marker = '### 课 6《数据导入全家桶》核心结论（2026-09-02）'
assert marker in s, 'conclusion marker not found'
s = s.replace(marker, concl.lstrip('\n') + '\n---\n\n' + marker, 1)

io.open(p, 'w', encoding='utf-8').write(s)
print('overview done')
