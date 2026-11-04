# lesson08 · 服务发现与负载均衡 —— 实测脚本

对应课文：[课 8 服务发现与负载均衡](../../stages/2-服务之间的通信/lessons/08-服务发现与负载均衡.md)
对应实战：[应用实战 08 · 实例扩缩容](../../应用实战/08-服务发现与负载均衡.md)

## 环境

本课**大部分脚本零第三方依赖**，只有 M3 / M3b 两段需要真实 gRPC：

```bash
# Python 3.12.3（本机实测版本）
cd distributed-python/playground/lesson08
python3 -m venv .venv
.venv/bin/pip install "grpcio==1.85.1"
```

> 和课 7 的 `playground/lesson07/` 不同：课 7 全部走标准库 `http.server`，本课 M3/M3b 必须用真实 gRPC 才能观察到 HTTP/2 连接复用，因此引入了一个第三方依赖。M3/M3b 之外的脚本用系统 `python3` 直接跑即可。

## 脚本与课文位置对照

| 脚本 | 对应知识点 / 小节 | 依赖 | 大致耗时 |
|---|---|---|---|
| `m1_hardcoded_address.py` | 知识点 1 · 硬编码地址的三个问题（R1/R2/R3） | 标准库 | <5s |
| `m2_lb_algorithms.py` | 知识点 2 · 四种负载均衡算法 | 标准库 | ~10s |
| `m3_grpc_percall.py` | 知识点 2 · gRPC per-call（pick_first vs round_robin） | **grpcio** | <5s |
| `m3b_grpc_l4.py` | 知识点 2 · L4 代理对 gRPC 无效（三轮） | **grpcio** | ~20s |
| `m4_probe_confusion.py` | 知识点 3 · 三种探针语义（组 A/组 B 对照） | 标准库 | ~15s |
| `m5_drain_timing.py` | 知识点 3 · 摘流时机（确定性推演） | 标准库 | <1s |
| `m6_stale_registry.py` | 知识点 1 · 名单过期窗口 | 标准库 | ~15s |
| `m7_client_vs_proxy.py` | 知识点 2 · 客户端 LB vs 服务端代理（四方案） | 标准库 | ~15s |
| `m8_client_lb_full.py` | 知识点 2 + 3 · 完整客户端 LB | 标准库 | ~10s |
| `app08_discovery_journey.py` | 应用实战 08 · 三段演进（四幕同口径） | 标准库 | ~30s |

## 运行

```bash
# 零依赖部分（M1/M2/M4/M5/M6/M7/M8 + 应用实战）
cd distributed-python/playground/lesson08
python3 m1_hardcoded_address.py
python3 m2_lb_algorithms.py
python3 m4_probe_confusion.py
python3 m5_drain_timing.py
python3 m6_stale_registry.py
python3 m7_client_vs_proxy.py
python3 m8_client_lb_full.py
python3 app08_discovery_journey.py

# 需要 grpcio 的两段
.venv/bin/python m3_grpc_percall.py
.venv/bin/python m3b_grpc_l4.py
```

## 复跑注意（踩过的坑）

- **M3b 必须关掉进程内 subchannel 池**。gRPC C-core 默认会把同 target 的多个 channel 复用同一条 TCP 连接，导致「6 个客户端」实际只建了 1 条连接、结果全打一个实例。每个 channel 都要带 `options=[("grpc.use_local_subchannel_pool", 1)]`。
- **M3b 轮 2 的 24/24/24 是假象**。客户端数恰好是实例数的整数倍时会看起来"很均匀"。真正的倾斜证据在轮 3（1 个重客户端 + 5 个轻客户端，92/4/4）。任何关于 L4 的结论只看轮 3。
- **M5 是确定性推演，不是真实计时**。它用固定参数（`INIT_MS=200` / `WARM_MS=1800` / `PROBE_PERIOD_MS=1000` / `SIGTERM_GRACE_MS=30000`）算出窗口长度，输出是时间轴而不是测量值。想要真实数字需要在 K8s 集群里跑。
- **M6 的"下线"是「摘流 + 返回 503」而不是真 `shutdown()`**。第一版用真 `shutdown()`，它自身的耗时吃掉了大部分 800ms 缓存窗口，测出来只有 2 次失败（失真）。真实形态是「readiness 失败但进程还活着，endpoint 摘除还在传播」。
- **M7 必须有 D 方案**。只有 A/B/C 时测出 A 和 C 都是 33.3%，无法证明"起作用的是探测这个动作"。加上 D（代理主动探测 + strikes）后才形成干净对照。
- **应用实战 08 的 `sync()` 不能重建 Endpoint**。每次拉取都重建会把 `strikes` / `ejected_until` 清零，摘流完全不生效。必须保留已有对象、只更新 `port`。
- **所有端口都是 0（系统分配）**。输出里的端口号每次都不同，这是正常的；对照数字看分布和比例，不要看具体端口号。

## 相关文件

- 阶段配图：`../stages/2-服务之间的通信/assets/discovery-*.svg`、`grpc-percall-vs-perconnection.svg`、`probe-semantics.svg`
- 实战配图：`../应用实战/assets/app-step{1,2,3}-discovery.svg`
- 全库校验：`python3 distributed-python/playground/check_links.py`
