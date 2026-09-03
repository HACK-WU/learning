#!/usr/bin/env python3
"""课 4 通用查询格式化：从 /api/v1/query 提取可读结果。"""
import json
import sys

raw = sys.stdin.read()
try:
    d = json.loads(raw)
except Exception:
    print("    RAW:", raw[:200])
    sys.exit(1)

if d.get("status") != "success":
    print("    ERROR:", str(d.get("error", "?"))[:160])
    sys.exit(0)

result = d["data"]["result"]
print("    命中 {} 条".format(len(result)))
for item in result[:8]:
    m = item["metric"]
    name = m.get("__name__", "<无名称>")
    labs = {k: v for k, v in m.items() if k != "__name__"}
    val = item["value"][1]
    print("      {} {} = {}".format(name, labs if labs else "", val))
