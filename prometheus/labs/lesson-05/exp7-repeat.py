#!/usr/bin/env python3
"""课 5 实验七：repeat_interval vs group_interval（最容易混淆的一对）。

group_interval : 分组**内容发生变化**后，下一次通知的等待间隔
repeat_interval: 分组**内容没变化**时，重复提醒的最小间隔

实验设计：
  阶段 A（内容稳定）：只让 l5-app-1 故障，持续 75s，观察重发节奏
                     -> 期间内容不变，间隔应≈repeat_interval(30s)
  阶段 B（内容变化）：稳定后再让 l5-app-2 故障，新告警加入分组
                     -> 内容变了，应较快发一条新通知（≈group_interval 10s），
                        且该条 n_alerts=2
"""
import time
from l5lib import (fault, receiver_count, receiver_list, receiver_reset,
                   prom_alerts)

T0 = time.time()
print(">>> reset")
print(receiver_reset())

print(">>> 强制清零所有实例的故障状态（防上一轮残留污染）")
for c in ["l5-app-1", "l5-app-2", "l5-app-3"]:
    print("  ", c, fault(c, "/fault/off"), fault(c, "/fault/node?v=1"))
print(">>> 等待残留告警完全消失（25s）")
time.sleep(25)
print(">>> 确认告警已清空:", prom_alerts() == [])

print("\n=== 阶段 A：只有 l5-app-1 故障，观察 repeat_interval 重发节奏")
print("   配置 group_wait=20s, group_interval=10s, repeat_interval=30s")
print(fault("l5-app-1", "/fault/on?rate=0.6"))

for i in range(9):
    time.sleep(10)
    print("  [t=%5.1fs] %s" % (time.time() - T0, receiver_count()))

print("\n>>> payments 明细（应见多条 firing，间隔≈30s）")
print(receiver_list("payments"))

print("\n=== 阶段 B：加入 l5-app-2，分组内容发生变化")
print(fault("l5-app-2", "/fault/on?rate=0.6"))
for i in range(4):
    time.sleep(8)
    print("  [t=%5.1fs] %s" % (time.time() - T0, receiver_count()))

print("\n>>> payments 明细（新增那条应 n_alerts=2）")
print(receiver_list("payments"))

print("\n--- 恢复")
print(fault("l5-app-1", "/fault/off"))
print(fault("l5-app-2", "/fault/off"))
time.sleep(18)
print("\n>>> 最终计数")
print(receiver_count())
print("\n=== DONE t=%.1fs ===" % (time.time() - T0))
