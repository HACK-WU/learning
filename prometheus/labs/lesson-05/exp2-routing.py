#!/usr/bin/env python3
"""课 5 实验二：路由树与匹配。

验证点：
  A. 路由按配置顺序自上而下匹配，命中即停（continue: false 默认）
     -> team=payments 的告警只发 payments，不会同时发 default
  B. 子节点未命中则回落到父节点（根路由）的 receiver
     -> team=search 且 severity=warning 不匹配子路由2，落到 default
  C. continue: true 让告警在命中后继续匹配后续兄弟路由
     -> NodeDown 同时发 infra 与（继续匹配后）default
  D. matchers 语法：=  !=  =~  !~
"""
import time
from l5lib import (fault, receiver_count, receiver_list, receiver_reset, snap)

T0 = time.time()
print(">>> reset")
print(receiver_reset())
time.sleep(1)

print("\n--- A/C: 注入 NodeDown（l5-app-1 节点宕机，payments/zone-a）")
print("   同时触发 HighErrorRate（l5-app-2, payments/zone-b）以便观察分流")
print(fault("l5-app-1", "/fault/node?v=0"))
print(fault("l5-app-2", "/fault/on?rate=0.6"))

time.sleep(18)
snap("after-node+error", T0)
print("\n>>> 计数")
print(receiver_count())

for ch in ["infra", "default", "payments"]:
    print("\n>>> %s 明细" % ch)
    print(receiver_list(ch))

print("\n--- 恢复")
print(fault("l5-app-1", "/fault/node?v=1"))
print(fault("l5-app-2", "/fault/off"))
time.sleep(20)
print("\n>>> 最终计数")
print(receiver_count())
for ch in ["infra", "default", "payments"]:
    print("\n>>> %s 明细" % ch)
    print(receiver_list(ch))
print("\n=== DONE t=%.1fs ===" % (time.time() - T0))
