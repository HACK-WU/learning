# -*- coding: utf-8 -*-
"""解析 Docker Hub 上 victoriametrics/victoria-metrics 的可用 tag"""
import json
import os

p = "/tmp/vmtags.json"
if not os.path.exists(p):
    print("未找到 tags 文件")
    raise SystemExit(1)

with open(p, encoding="utf-8") as f:
    d = json.load(f)

tags = [t["name"] for t in d.get("results", [])]
print("总 tag 数: %d" % len(tags))

cl = [t for t in tags if "cluster" in t.lower()]
print("\n含 cluster 的 tag (%d 个):" % len(cl))
for t in cl[:30]:
    print("   ", t)

print("\n最新 25 个 tag:")
for t in tags[:25]:
    print("   ", t)

# 找 v1.151 相关的
v151 = [t for t in tags if "1.151" in t]
print("\n含 1.151 的 tag (%d 个):" % len(v151))
for t in v151:
    print("   ", t)
