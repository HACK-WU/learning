#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
课 12 实操：往 data stream 注入"当前时间"的 ERROR 日志，用来触发告警规则。

为什么需要一个脚本：
  gen-app-logs.py 生成的是"最近 3 小时"的批量数据，跑完就固定了；
  告警规则看的是"最近 5 分钟"，所以每次要触发告警，都得现造几条 @timestamp=now 的。

用法:
  python3 inject-errors.py [条数]     # 默认 3 条
"""
import json
import random
import subprocess
import sys
from datetime import datetime, timezone

N = int(sys.argv[1]) if len(sys.argv) > 1 else 3
DS = "logs-appdemo-default"
ES_URL = "http://localhost:9200"
ES_AUTH = "elastic:ELKlearn2026"

HOSTS = ["web-01", "web-02", "web-03"]
MSGS = [
    "payment gateway timeout after 3000ms",
    "upstream connect error: connection refused",
    "db query failed: deadlock detected",
    "注入告警: 人工触发的 ERROR（课 12 演示）",
]


def main():
    now = datetime.now(timezone.utc)
    lines = []
    for i in range(N):
        ts = now.strftime("%Y-%m-%dT%H:%M:%S.") + f"{now.microsecond // 1000:03d}Z"
        doc = {
            "@timestamp": ts,
            "message": random.choice(MSGS),
            "log": {"level": "ERROR", "logger": "payment-service"},
            "host": {"name": random.choice(HOSTS)},
            "service": {"name": "payment-service", "type": "java"},
            "http": {"request": {"method": "POST"},
                     "response": {"status_code": random.choice([500, 502, 503])}},
            "url": {"path": "/api/pay/submit"},
            "event": {"duration": 3_000_000_000},
            "duration_ms": 3000,
            "user": {"id": f"u9{random.randint(100, 199)}"},
            "container": {"name": "payment-service-pod-1"},
            "demo": {"batch": "lesson-12-alert-demo"},
        }
        lines.append(json.dumps({"create": {}}, ensure_ascii=False))
        lines.append(json.dumps(doc, ensure_ascii=False))

    body = "\n".join(lines) + "\n"
    with open("/tmp/_inject.ndjson", "w", encoding="utf-8") as f:
        f.write(body)

    out = subprocess.run(
        ["curl", "-s", "-u", ES_AUTH, "-H", "Content-Type: application/x-ndjson",
         "-X", "POST", f"{ES_URL}/{DS}/_bulk?refresh=true", "--data-binary", "@/tmp/_inject.ndjson"],
        capture_output=True, text=True,
    )
    resp = json.loads(out.stdout)
    print(f"注入 {len(resp.get('items', []))} 条, errors={resp.get('errors')}")
    print(f"@timestamp = {now.isoformat()}")


if __name__ == "__main__":
    main()
