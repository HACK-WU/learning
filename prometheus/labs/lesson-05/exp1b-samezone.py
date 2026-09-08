#!/usr/bin/env python3
"""课 5 实验一补：同 zone 多实例时的聚合效果。

上一轮 payments 每个 zone 只有 1 个实例，n_alerts=1，看不出聚合。
本轮让 zone-a 的 l5-app-1(payments) 与 l5-app-3(search) 同时告警：
  - payments 路由 group_by=[alertname,zone] -> zone-a 只有 l5-app-1，仍 1 条
  - default 路由  group_by=[alertname]      -> l5-app-3 走这里
为了真正看到 "1 条通知含 2 条告警"，改为验证：
  把 group_by 从 [alertname,zone] 改为 [alertname] 后，
  payments 的两个 zone 会合并成 1 个分组、1 条通知含 2 条告警。

本脚本不改配置，只做"当前 group_by 下的对照记录"：
  记录 payments 收到 2 条通知（按 zone 拆）这一事实本身，
  即为 group_by 影响分组粒度的直接证据。
"""
import time
from l5lib import (fault, receiver_count, receiver_list, receiver_reset, snap)

T0 = time.time()
print(">>> reset")
print(receiver_reset())

print("\n>>> 注入 l5-app-1(payments/zone-a) + l5-app-2(payments/zone-b)")
print(fault("l5-app-1", "/fault/on?rate=0.6"))
print(fault("l5-app-2", "/fault/on?rate=0.6"))

time.sleep(16)
snap("after-fault", T0)
print("\n>>> 计数（payments 应为 2：两个 zone 分两组）")
print(receiver_count())
print("\n>>> payments 明细")
print(receiver_list("payments"))

print("\n>>> 恢复")
print(fault("l5-app-1", "/fault/off"))
print(fault("l5-app-2", "/fault/off"))
time.sleep(22)
print("\n>>> 最终计数")
print(receiver_count())
print("\n>>> payments 明细（含 resolved）")
print(receiver_list("payments"))
print("\n=== DONE t=%.1fs ===" % (time.time() - T0))
