# 阶段 4 · 并发实验脚本（课 11–13）

本目录存放阶段 4 各课**真实运行过**的并发实验脚本与原始输出，用于：
1. 正文里每段 `console`/`sql` 输出都能回溯到一次真实运行（实测证据闸门）；
2. 换机器 / 重装环境后一键复现同一组证据。

> 脚本是「三会话模型」：**HOLDER**（持锁）/ **WAITER**（被阻塞）/ **OBS**（观察者，永不被阻塞）。
> 会阻塞的语句用「只发不收」，等另一会话释放后再回收，避免脚本自身卡死。

## 环境要求

```bash
export PATH="/usr/local/bin:$PATH"   # docker 在 /usr/local/bin
docker start pg17                     # PostgreSQL 17.11，端口 5433
```

- 库 `order_service` / schema `finance`
- 运行：`/Users/wuyongping/.workbuddy/binaries/python/versions/3.13.12/bin/python3 l13_expN_*.py`
- 依赖表见正文「第四幕 · 环境准备（可复现）」SQL 块。

## 脚本 ↔ 正文实验编号对照

| 脚本 | 覆盖实验 | 关键结论 | 输出存档 |
|---|---|---|---|
| `l13_exp1_table_locks.py` | A / A-2 / A-3 / B / C / D / E / F | 各命令自动表锁；`LOCK TABLE` 八种模式；ACCESS EXCLUSIVE 阻塞 SELECT；`lock_timeout` 触发 | `out_l13_exp1_table_locks.txt` |
| `l13_exp1b_table_locks_extra.py` | VACUUM 抓锁 + NOWAIT / SKIP LOCKED（G-1 / G-2 / H） | `55P03`；`wait_event=transactionid`；`pg_locks` 无 `granted=f` 行锁 | `out_l13_exp1b_table_locks_extra.txt` |
| `l13_exp2e_row_matrix_advisory_deadlock.py` | I / J-1~8 / K | **行锁 4×4 矩阵（阻塞观察法，最终正确版）**；咨询锁会话级 vs 事务级；死锁复现 | `out_l13_exp2e_row_matrix_advisory_deadlock.txt` |
| `l13_exp4_txn_traps.py` | M-3 / N / P / R | `idle in transaction` 持锁；三个超时；长事务钉死元组；`40001` | `out_l13_exp4_txn_traps.txt` |
| `l13_exp5_sqlstates.py` | L / R | 一次拿全 3 个 SQLSTATE：`40001` / `40P01` / `55P03` | `out_l13_exp5_sqlstates.txt` |

## ⚠️ 两个已踩过的坑（写脚本时务必遵守）

1. **判据用「行为」，不要用「错误文本」**：psql 的 ERROR 走 stderr，与 stdout 合并读取时会**延迟到下次 read**，会把「报错」误判成「没报错」（`l13_exp2.py` 因此把整列行锁矩阵测错）。
   → 正确做法：**阻塞观察法**——发不带 `NOWAIT` 的语句，等 ~1.8s 看是否返回。
2. **不要用阻塞式 `readline` 做超时读取**：无数据时它**永久挂住**，`while time.time() < deadline` 形同虚设（脚本曾卡死近 5 分钟被 SIGTERM）。
   → 正确做法：**后台读取线程 + `queue.Queue` + `queue.get(timeout=)`**（见 `l13_exp2e_...py` 的 `P.read_until_end`）。

## 未归档的中间版本

`l13_exp2.py` / `exp2c` / `exp2d`（IO 模型与判据的试错版本）**故意不归档**，避免误导；其教训已写入正文 13.1④ 与上面的「两个坑」。
