"""诊断：用引擎直方图的 inner_eval 差值度量单次查询成本，是否可靠？

slice 语义（官方文档）：
  queue_time   —— 在队列里等待的时间（并发打满时才明显）
  prepare_time —— 准备阶段：解析、查索引、选序列
  inner_eval   —— 真正的求值阶段：读样本、算函数、聚合
  result_sort  —— 结果排序

判据：跑 N 次同一查询，看 inner_eval 的 sum 增量是否 ≈ N × 单次成本。
"""
import json
import time

from l6lib import _wget, query, query_range, now

SUM = 'sum(prometheus_engine_query_duration_seconds_sum{slice="inner_eval"})'
CNT = 'sum(prometheus_engine_query_duration_seconds_count{slice="inner_eval"})'


def pair():
    s = query(SUM)
    c = query(CNT)
    return (float(s[0]["value"][1]) if s else 0.0,
            float(c[0]["value"][1]) if c else 0.0)


print("== 方法验证：跑 5 次同一查询，看增量是否线性 ==")
end = now()
for i in range(1, 6):
    s0, c0 = pair()
    query_range("l6_requests_total", end - 300, end, "15s")
    s1, c1 = pair()
    print(f"   第{i}次: sum +{s1-s0:.6f}s   count +{c1-c0:.0f}")

print()
print("== 对照：不同 step 下的 inner_eval 单次耗时 ==")
print(f'{"step":>6} | {"单次求值(ms)":>12} | {"墙钟(ms)":>10}')
print("-" * 40)
for step in ["1s", "5s", "15s", "60s"]:
    s0, c0 = pair()
    t0 = time.perf_counter()
    query_range("l6_requests_total", end - 300, end, step)
    el = (time.perf_counter() - t0) * 1000
    s1, c1 = pair()
    dc = c1 - c0
    per = (s1 - s0) / dc * 1000 if dc else 0
    print(f"{step:>6} | {per:>12.2f} | {el:>10.1f}")
    time.sleep(1)
