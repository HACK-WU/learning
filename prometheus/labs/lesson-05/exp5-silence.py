#!/usr/bin/env python3
"""课 5 实验五：静默（silence）。

与抑制的区别（本课核心辨析）：
  抑制 inhibit：alert -> alert，靠告警之间的关联自动触发，配置在 Alertmanager 配置文件里
  静默 silence：人工 -> 告警，按标签手动圈定一批告警，通过 API/UI 创建，有过期时间

本实验：
  1. 让 l5-app-3 错误率超标，告警正常发出
  2. 通过 API 创建 silence（匹配 alertname=HighErrorRate, zone=zone-a）
  3. 观察该告警不再产生新通知
  4. 提前使 silence 过期（或等它过期），观察告警恢复通知
"""
import json
import time
import urllib.request
from l5lib import (fault, receiver_count, receiver_list, receiver_reset,
                   snap, via_proxy, AM)

T0 = time.time()


def delete_all_silences():
    """删除所有已有 silence，避免上一次实验残留干扰。"""
    import subprocess
    out = via_proxy("http://l5-am:9093/api/v2/silences")
    try:
        rows = json.loads(out)
    except Exception:
        return "skip"
    ids = []
    for r in rows:
        st = r.get("status", {}).get("state", "")
        sid = r.get("id")
        if sid and st in ("pending", "active"):
            ids.append(sid)
    for sid in ids:
        subprocess.run(
            ["bash.exe", "-c",
             'docker exec l5-prom wget -qO- --method=DELETE '
             'http://l5-am:9093/api/v2/silence/%s' % sid],
            capture_output=True, text=True)
    return "deleted %d silences" % len(ids)


def create_silence(matchers, duration_s=60, created_by="lesson05", comment="课5演示"):
    """通过 l5-prom 容器用 wget 发送 POST 创建 silence（已实测可行写法）。"""
    import subprocess
    starts = time.strftime("%Y-%m-%dT%H:%M:%S.000Z", time.gmtime(time.time() - 5))
    ends = time.strftime("%Y-%m-%dT%H:%M:%S.000Z", time.gmtime(time.time() + duration_s))
    payload = {
        "matchers": matchers,
        "startsAt": starts,
        "endsAt": ends,
        "createdBy": created_by,
        "comment": comment,
    }
    body = json.dumps(payload).replace('"', '\\"')
    cmd = ('docker exec l5-prom wget -qO- --post-data="%s" '
           '--header="Content-Type: application/json" '
           'http://l5-am:9093/api/v2/silences' % body)
    r = subprocess.run(["bash.exe", "-c", cmd], capture_output=True, text=True)
    return (r.stdout or "") + (r.stderr or "")


print(">>> 清理历史 silence")
print(delete_all_silences())
print(">>> reset")
print(receiver_reset())
time.sleep(1)

print("\n=== 阶段 1：告警正常发出")
print(fault("l5-app-3", "/fault/on?rate=0.6"))
time.sleep(18)
snap("phase1-firing", T0)
print("计数:", receiver_count())

print("\n=== 阶段 2：创建 silence（alertname=HighErrorRate 且 zone=zone-a，持续 60s）")
r = create_silence([
    {"name": "alertname", "value": "HighErrorRate", "isRegex": False},
    {"name": "zone", "value": "zone-a", "isRegex": False},
], duration_s=60)
print("create ->", r.strip()[:300])

time.sleep(32)
print("\n>>> silence 期间计数（repeat_interval=30s，本应再发一次）")
print(receiver_count())
print(">>> default:", receiver_list("default"))

print("\n>>> 当前 silences")
print(via_proxy("http://l5-am:9093/api/v2/silences")[:600])

print("\n=== 阶段 3：等待 silence 过期（60s）")
time.sleep(45)
print(">>> 计数")
print(receiver_count())
print(">>> default:", receiver_list("default"))

print("\n--- 清理")
print(fault("l5-app-3", "/fault/off"))
time.sleep(15)
print("\n>>> 最终计数")
print(receiver_count())
print("\n=== DONE t=%.1fs ===" % (time.time() - T0))
