#!/usr/bin/env python3
"""课 5 通用实验工具库。

关键修正（课 5 实测）：
  - app 容器是 python:3.12-slim，**没有 wget/curl**，无法在容器内自调故障端点。
    改用 l5-prom 容器（prom/prometheus 基于 busybox，有 wget）代发请求。
  - receiver 查询同理，用 l5-prom 代发。
"""
import json
import subprocess
import time
import urllib.request

PROM = "http://localhost:19090"
AM = "http://localhost:19093"
PROXY = "l5-prom"  # 代发 HTTP 请求的容器（有 wget）


def sh(cmd):
    return subprocess.run(["bash.exe", "-c", cmd],
                          capture_output=True, text=True).stdout.strip()


def via_proxy(url):
    """借 l5-prom 容器发 GET 请求（该容器有 wget）。"""
    return sh('docker exec %s wget -qO- "%s"' % (PROXY, url))


def http_get(url):
    req = urllib.request.Request(url)
    with urllib.request.urlopen(req, timeout=15) as r:
        return json.loads(r.read().decode("utf-8"))


def fault(target, path):
    """向 app 实例注入故障，返回响应文本。"""
    return via_proxy("http://%s:8080%s" % (target, path))


def receiver_count():
    return via_proxy("http://l5-receiver:8099/count")


def receiver_reset():
    return via_proxy("http://l5-receiver:8099/reset")


def receiver_list(name, brief=True):
    b = "1" if brief else "0"
    return via_proxy("http://l5-receiver:8099/list?path=%s&brief=%s" % (name, b))


def prom_alerts():
    return http_get(PROM + "/api/v1/alerts")["data"]["alerts"]


def am_alerts():
    return http_get(AM + "/api/v2/alerts")


def am_silences():
    return http_get(AM + "/api/v2/silences")


def short_labels(labels, keys=("alertname", "instance", "team", "zone", "severity")):
    return {k: v for k, v in labels.items() if k in keys}


def snap(tag, t0):
    pa = prom_alerts()
    aa = am_alerts()
    firing = [a for a in pa if a["state"] == "firing"]
    print("\n===== [%s] t=%.1fs =====" % (tag, time.time() - t0))
    print("Prometheus: total=%d firing=%d" % (len(pa), len(firing)))
    for a in firing:
        print("   P %s" % short_labels(a["labels"]))
    print("Alertmanager: %d" % len(aa))
    for a in sorted(aa, key=lambda x: x["labels"].get("alertname", "")):
        print("   A %s" % short_labels(a["labels"]))
    return pa, aa
