#!/usr/bin/env python3
"""课 5 实验三：continue: true 的语义。

NodeDown 带 team=payments 且 alertname 匹配 Node.*：
  continue: false（配置 Y）-> 只发 infra
  continue: true （配置 Z）-> 先发 infra，继续匹配 -> 再发 payments
"""
import time
from l5lib import (fault, receiver_count, receiver_list, receiver_reset, snap)

T0 = time.time()
print(">>> reset")
print(receiver_reset())
time.sleep(1)

print("\n>>> 注入 NodeDown(l5-app-1, payments/zone-a)")
print(fault("l5-app-1", "/fault/node?v=0"))

time.sleep(18)
snap("firing", T0)
print("\n>>> 计数（预期 infra>=1 且 payments>=1，同一告警多通道）")
print(receiver_count())
for ch in ["infra", "payments", "default"]:
    print("\n>>> %s 明细" % ch)
    print(receiver_list(ch))

print("\n--- 恢复")
print(fault("l5-app-1", "/fault/node?v=1"))
time.sleep(18)
print("\n>>> 最终计数")
print(receiver_count())
print("\n=== DONE t=%.1fs ===" % (time.time() - T0))
