#!/usr/bin/env python3
"""课 5 实验一决定性对照：group_by 决定分组粒度。

配置 A: payments group_by=[alertname, zone] -> 2 条告警 = 2 个分组 = 2 条通知
配置 B: payments group_by=[alertname]       -> 2 条告警 = 1 个分组 = 1 条通知(n_alerts=2)

本脚本跑配置 B，并与已记录的配置 A 结果对照。
"""
import time
from l5lib import (fault, receiver_count, receiver_list, receiver_reset, snap)

T0 = time.time()
print(">>> reset")
print(receiver_reset())
time.sleep(1)

print("\n>>> 注入 l5-app-1 + l5-app-2 (同 team=payments, 不同 zone)")
print(fault("l5-app-1", "/fault/on?rate=0.6"))
print(fault("l5-app-2", "/fault/on?rate=0.6"))

time.sleep(16)
snap("after-fault", T0)

print("\n>>> 计数")
print(receiver_count())
print("\n>>> payments 明细（预期 1 条通知，n_alerts=2）")
print(receiver_list("payments"))

print("\n>>> 恢复")
print(fault("l5-app-1", "/fault/off"))
print(fault("l5-app-2", "/fault/off"))
time.sleep(20)

print("\n>>> 最终计数")
print(receiver_count())
print("\n>>> payments 明细（含 resolved）")
print(receiver_list("payments"))
print("\n=== DONE t=%.1fs ===" % (time.time() - T0))
