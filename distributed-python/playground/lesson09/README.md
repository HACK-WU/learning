# lesson09 · 分布式事务与 Saga —— 实测脚本

对应课文：[课 9 分布式事务与 Saga](../../stages/3-数据一致性/lessons/09-分布式事务与Saga.md)
对应实战：[应用实战 09 · 跨服务下单](../../应用实战/09-分布式事务与Saga.md)

## 环境

本课**全部脚本零第三方依赖**，纯标准库（`sqlite3` / `threading` / `socket`）。用系统的 `python3` 直接跑即可，不需要 venv，不需要 pip 安装任何包。

```bash
# Python 3.12.3（本机实测版本）
cd distributed-python/playground/lesson09
python3 m1_local_tx_boundary.py
python3 m2_2pc_cost.py
python3 m3_saga_three_way.py
```

> 与课 7（全部标准库 http.server）一致，本课也坚持零依赖：用**真实 sqlite3 的三个独立库文件**模拟"三个服务"，这样「一个事务护不住两个库」、2PC 的加锁、Saga 的补偿去重都能在真实数据库行为上观测，而不是抽象推演。

## 脚本与课文位置对照

| 脚本 | 对应知识点 / 小节 | 依赖 | 大致耗时 |
|---|---|---|---|
| `m1_local_tx_boundary.py` | 知识点 1 · 本地事务的边界（R1/R2/R3/R2b） | 标准库 | <10s |
| `m2_2pc_cost.py` | 知识点 2 · 2PC 的代价（R1/R2/R3/R4） | 标准库 | ~5s |
| `m3_saga_three_way.py` | 知识点 3 · Saga 三段对照（S1/S2/S3） | 标准库 | ~5s |
| `app09_saga_journey.py` | 应用实战 09 · 写死两库 → 2PC → Saga 纵向对比 | 标准库 | <10s |

## 运行

```bash
cd distributed-python/playground/lesson09
python3 m1_local_tx_boundary.py   # 本地事务边界
python3 m2_2pc_cost.py            # 2PC 代价
python3 m3_saga_three_way.py      # Saga 三段对照
python3 app09_saga_journey.py     # 应用实战纵向对比
```

## 复跑注意（踩过的坑）

- **M3 的失败清单必须预生成、三种策略共用**。第一版让每种策略各自 `random.Random(7)` 消耗随机流，导致三种策略看到的"失败发生在哪一笔"完全不同，成功/失败笔数对不上、没法横向比。改成 `make_decisions()` 预生成一份 (oid, 库存失败?, 支付失败?, 发货失败?) 清单，S1/S2/S3 共用，才能干净对照。
- **三个库必须各建自己的去重表**。M3 第一版把 `comp_log` 只建在 pay 库，`release_stock_idem` 却去 stock 库 `INSERT INTO comp_log`——抛 `OperationalError: database is locked`（不是 `IntegrityError`，所以没被 `except sqlite3.IntegrityError` 捕获），连接一直占着 `BEGIN IMMEDIATE` 写锁、永不释放，把 stock 库锁死。解法：每个服务（库）建自己的 `comp_log`。
- **事务必须保证 finally 释放连接**。`BEGIN IMMEDIATE` 若在异常路径上没有 ROLLBACK + close，写锁就一直挂着，后面的写全报 `database is locked`。用 `contextmanager` 的 `tx()` 包住「BEGIN → yield → COMMIT/ROLLBACK → finally close」统一收尾。
- **去重键用业务键，不是"第几次投递"**。S2 里 `cancel_order`（DELETE）天然幂等、投 80 次都安全；`refund`（UPDATE）第二次找不到可退的会报错（"会响"，能被监控抓住）；`release_stock`（add）第二次照样加、不报错（"不响"，最难查）。这份"三种补偿三种命运"的差异就是实验要你亲眼看见的。
- **S3 的 0 偏差是"补对 + 补不重"，不是"运气好"**。它靠的是去重表（同一业务键判重复跳过）+ PENDING 语义锁（中间态可见用状态机兜）。没有幂等，S2 的偏差就在 8 和 32 之间来回。

## 相关文件

- 阶段配图：`../stages/3-数据一致性/assets/tx-*.svg`（直觉图 / 本地边界 / 2PC 代价 / Saga 补偿 / 决策树）
- 实战配图：`../应用实战/assets/app-step{1,2,3}-saga.svg`
- 全库校验：`python3 distributed-python/playground/check_links.py`

## 一个可选的小实验

把 `m3_saga_three_way.py` 里 `dup_delivery` 从 `True` 改成 `False`（每条补偿只投 1 次），你会看到 S2 的偏差从 32 掉回 8——这证明"重复投递"正是幂等性价值被逼出来的地方：单次投递时幂等与非幂等看起来没差别。

```python
# 改这里：
s2 = run_saga(decisions, idempotent=False)                     # 90 → 8
s2_dup = run_saga(decisions, idempotent=False, dup_delivery=False)  # 不重复投递 → 8
```
