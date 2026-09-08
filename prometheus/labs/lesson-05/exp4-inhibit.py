#!/usr/bin/env python3
"""课 5 实验四：抑制（inhibition）。

规则：
  source: alertname=NodeDown, severity=critical
  target: severity=warning
  equal:  ['zone']

含义：某 zone 内节点宕机时，抑制该 zone 内所有 severity=warning 的告警。

场景设计（关键：source 与 target 必须在**同一个 zone**）：
  l5-app-1 是 payments/zone-a
  l5-app-3 是 search/zone-a
  -> 让 l5-app-1 节点宕机（NodeDown, zone-a, critical）
  -> 让 l5-app-3 错误率超标（HighErrorRate, zone-a, warning）
  -> 预期：HighErrorRate 被抑制，payments/default 通道不再发出它

对照：先只注入 HighErrorRate（无 NodeDown），确认它会正常发出；
      再注入 NodeDown，观察它被抑制（通知转为 resolved 或不再重发）。
"""
import time
from l5lib import (fault, receiver_count, receiver_list, receiver_reset, snap)

T0 = time.time()
print(">>> reset")
print(receiver_reset())
time.sleep(1)

print("\n=== 阶段 1：只让 l5-app-3(search/zone-a) 错误率超标")
print("   预期：HighErrorRate 正常发出（走 default，因为 search+warning 不匹配子路由）")
print(fault("l5-app-3", "/fault/on?rate=0.6"))
time.sleep(18)
snap("phase1-error-only", T0)
print("\n>>> 计数")
print(receiver_count())
for ch in ["default", "payments", "infra"]:
    print(">>> %s: %s" % (ch, receiver_list(ch)))

print("\n=== 阶段 2：叠加 NodeDown（l5-app-1，同属 zone-a）")
print("   预期：zone-a 的 HighErrorRate 被抑制")
print(fault("l5-app-1", "/fault/node?v=0"))
time.sleep(30)
snap("phase2-node-down", T0)
print("\n>>> 计数")
print(receiver_count())
for ch in ["default", "payments", "infra"]:
    print(">>> %s: %s" % (ch, receiver_list(ch)))

print("\n=== 阶段 3：恢复节点，抑制解除")
print("   预期：HighErrorRate 重新出现")
print(fault("l5-app-1", "/fault/node?v=1"))
time.sleep(25)
snap("phase3-node-recover", T0)
print("\n>>> 计数")
print(receiver_count())
for ch in ["default", "payments", "infra"]:
    print(">>> %s: %s" % (ch, receiver_list(ch)))

print("\n--- 清理")
print(fault("l5-app-3", "/fault/off"))
time.sleep(15)
print("\n>>> 最终计数")
print(receiver_count())
print("\n=== DONE t=%.1fs ===" % (time.time() - T0))
