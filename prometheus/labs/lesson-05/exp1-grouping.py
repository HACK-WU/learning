#!/usr/bin/env python3
"""课 5 实验一：告警的到达、去重与分组。"""
import json
import time
from l5lib import (fault, receiver_count, receiver_list, receiver_reset,
                   prom_alerts, am_alerts, snap)

T0 = time.time()

print(">>> reset")
print(receiver_reset())
snap("baseline", T0)
time.sleep(2)

print("\n>>> 注入：三个实例错误率 50%")
for c in ["l5-app-1", "l5-app-2", "l5-app-3"]:
    print(" ", c, fault(c, "/fault/on?rate=0.5"))

time.sleep(14)
snap("after-fault-14s", T0)

print("\n>>> 通道计数")
print(receiver_count())

print("\n>>> payments 明细 (group_by=alertname+zone)")
print(receiver_list("payments"))

print("\n>>> default 明细")
print(receiver_list("default"))

print("\n>>> 等 repeat_interval 重发 ~35s")
time.sleep(35)
print(receiver_count())
print("\n>>> payments 明细（应见重复通知）")
print(receiver_list("payments"))

print("\n>>> 恢复")
for c in ["l5-app-1", "l5-app-2", "l5-app-3"]:
    print(" ", c, fault(c, "/fault/off"))

time.sleep(22)
snap("after-recover-22s", T0)
print("\n>>> 恢复后计数")
print(receiver_count())
print("\n>>> payments 明细（应含 resolved）")
print(receiver_list("payments"))

print("\n=== DONE t=%.1fs ===" % (time.time() - T0))
