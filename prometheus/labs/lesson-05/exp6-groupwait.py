#!/usr/bin/env python3
"""课 5 实验六：group_wait 的攒批作用 + 三个时间参数的实测语义。

group_wait:     新分组出现后，先等这段时间"攒批"，再把这一批合成 1 条通知发出
group_interval: 已有分组在下一次批量发送前的等待间隔
repeat_interval:同一分组（内容未变）重复通知的最小间隔

实验设计（精确计时）：
  t0    : 让 l5-app-1 错误率超标 -> 产生 HighErrorRate(zone-a)
  t0+3  : 让 l5-app-2 错误率超标 -> 产生 HighErrorRate(zone-b)
  两个分组独立，各自有自己的 group_wait

  关键测量：把 group_wait 设为 20s，group_by=[alertname]（合并成一个分组），
  则 t0 与 t0+3 的两条告警会被攒进**同一条**通知（n_alerts=2）；
  若 group_wait 只有 5s，则第一条在 t0+5 就发出，第二条只能等下一轮。
"""
import time
from l5lib import (fault, receiver_count, receiver_list, receiver_reset, snap)

T0 = time.time()
print(">>> reset")
print(receiver_reset())
time.sleep(1)

print("\n=== group_wait=10s, group_by=[alertname]（当前为 alertname+zone，见下）===")
print("t0  : l5-app-1 故障")
print(fault("l5-app-1", "/fault/on?rate=0.6"))
time.sleep(3)
print("t0+3: l5-app-2 故障（错开 3 秒，落在同一 group_wait 窗口内）")
print(fault("l5-app-2", "/fault/on?rate=0.6"))

for wait in (4, 4, 6, 8, 10):
    time.sleep(wait)
    print("  [t=%.1fs] counts=%s" % (time.time() - T0, receiver_count()))

print("\n>>> 此时 payments 明细（预期：1 条通知含 2 条告警 = 攒批生效）")
print(receiver_list("payments"))

print("\n--- 恢复")
print(fault("l5-app-1", "/fault/off"))
print(fault("l5-app-2", "/fault/off"))
time.sleep(20)
print("\n>>> 最终计数")
print(receiver_count())
print("\n=== DONE t=%.1fs ===" % (time.time() - T0))
