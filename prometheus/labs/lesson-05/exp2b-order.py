#!/usr/bin/env python3
"""课 5 实验二补：子路由顺序决定分流结果（顺序对照）。

同一批告警（NodeDown@zone-a + HighErrorRate@zone-b，都带 team=payments）：

  配置 X（通用 team=payments 在前）：
      NodeDown 被 payments 拦截 -> payments 收到 2 组，infra 收到 0
  配置 Y（专用 Node.* 在前）：
      NodeDown 走 infra          -> infra 收到 NodeDown，payments 只收 HighErrorRate

这直接证明：路由是**有序**的，命中即停（continue: false），
靠前的通用匹配会"吃掉"后面的专用匹配。
"""
import time
from l5lib import (fault, receiver_count, receiver_list, receiver_reset, snap)

T0 = time.time()
print(">>> reset")
print(receiver_reset())
time.sleep(1)

print("\n>>> 注入：NodeDown(l5-app-1, zone-a) + HighErrorRate(l5-app-2, zone-b)")
print("   两者都带 team=payments")
print(fault("l5-app-1", "/fault/node?v=0"))
print(fault("l5-app-2", "/fault/on?rate=0.6"))

time.sleep(18)
snap("firing", T0)
print("\n>>> 计数")
print(receiver_count())
for ch in ["infra", "payments", "default"]:
    print("\n>>> %s 明细" % ch)
    print(receiver_list(ch))

print("\n--- 恢复")
print(fault("l5-app-1", "/fault/node?v=1"))
print(fault("l5-app-2", "/fault/off"))
time.sleep(20)
print("\n>>> 最终计数")
print(receiver_count())
print("\n=== DONE t=%.1fs ===" % (time.time() - T0))
