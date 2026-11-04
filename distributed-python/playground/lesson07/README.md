# 课 7 实测脚本（熔断、限流与隔离）

对应课程：阶段 2《服务之间的通信》· 课 7《熔断、限流与隔离》正文 4.1 与 4.2

## 环境

- Linux（WSL2，kernel 6.6.87.2）
- Python 3.12.13
- 零第三方依赖：只用标准库 `http.server` / `threading` / `urllib`

## 怎么跑

```bash
cd distributed-python/playground/lesson07
python3 m1_avalanche.py              # 雪崩：谁被打死了
python3 m2_breaker_states.py         # 熔断器三态转换
python3 m3_breaker_blocks_avalanche.py  # 熔断对"快失败"vs"慢成功"
python3 m4_rate_limiters.py          # 四种限流算法对比
python3 m5_bulkhead.py               # 舱壁隔离
python3 m6_ratelimit_placement.py    # 限流器装在调用方 vs 被调方
python3 m7_assembly_order.py         # 三道门的装配顺序
python3 verify_app07_compare.py      # 应用实战 07 的三段对照（含子预算）
```

每个脚本都自起本地 HTTP 下游（绑定 `127.0.0.1` 随机端口），跑完自行退出，不占端口、不写文件。

## 脚本与课文对应

| 脚本 | 对应位置 | 关键结论 |
|---|---|---|
| `_downstream.py` | 共用 | 真实 HTTP 下游（可调延迟与状态码）+ 最近秩百分位 |
| `m1_avalanche.py` | 知识点 1 / 4.1 M1 | 下游只被打 8 次却 42 个超时；下游恢复后被打 0 次仍全灭 |
| `m2_breaker_states.py` | 知识点 2 / 4.1 M2 | 三态转换时间点；Open 期间 0.00ms、下游 0 次 |
| `m3_breaker_blocks_avalanche.py` | 知识点 2 / 4.1 M3 | 慢但成功时只算硬失败的熔断器跳闸 0 次 |
| `m4_rate_limiters.py` | 知识点 3 / 4.1 M4 | 固定窗口边界放过 20/20；令牌桶 burst=20 放过 20/20 |
| `m5_bulkhead.py` | 知识点 3 / 4.1 M5 | 无关接口成功率 69.7% → 100.0%，P99 300ms → 6ms |
| `m6_ratelimit_placement.py` | 知识点 3 / 4.1 M6 | 每实例限流 3.00× 超容量；入口限流 0.87× |
| `m7_assembly_order.py` | 知识点 3 / 4.1 M7 | 只有熔断 122.7 QPS、加舱壁 90.0、三道门 9.5 |
| `verify_app07_compare.py` | 知识点 3 / 4.1 M5b / 实战 07 | 舱壁+子预算让核心链路 0/50 → 45/50；熔断把下游被打 35 → 7 次 |

## 复跑注意

- 这些脚本是**教学探针**，不是生产库。参数（阈值、窗口、位子数）是为让现象在几秒内显现而挑的，不要直接搬进线上。
- 脚本对时间敏感（`m3`/`m7` 需要几秒的负载期），在负载极高的机器上数字会漂移，但量级与结论不变。
- 脚本会打印 `BrokenPipeError` 栈——这是"客户端超时先断开、下游还在写响应"的正常现象（正好就是知识点 1 的幽灵请求），不影响统计结果。
