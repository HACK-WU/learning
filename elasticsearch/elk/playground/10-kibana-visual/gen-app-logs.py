#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
课 11《Kibana 从 Discover 到 Dashboard》演示数据生成器

用途：向 data stream `logs-appdemo-default` 灌一批"够看"的日志。
  - 3 台主机（web-03 故障明显更多，便于 Lens 按主机拆分时看出差异）
  - 4 个级别（DEBUG / INFO / WARN / ERROR）
  - 时间跨度：最近 3 小时
  - 在"约 45 分钟前"埋一个 10 分钟的 ERROR 尖峰（便于直方图下钻演示）

输出：bulk-app-logs.ndjson（ES _bulk 请求体，create 动作，无 _id）

为什么不用 Filebeat 采：本课主角是 Kibana 的可视化能力，采集链路在课 2-6 已经
跑通并验证过。这里直接 _bulk 灌演示数据，是为了让时间戳可控（能精确制造"默认
时间窗口内看不到数据"的教学场景），且不受 Filebeat 采集节奏影响。
"""

import json
import random
from datetime import datetime, timedelta, timezone

random.seed(20260907)

TOTAL = 600
WINDOW_HOURS = 3
SPIKE_START_MIN_AGO = 55      # 尖峰开始（距今分钟）
SPIKE_END_MIN_AGO = 45        # 尖峰结束
SPIKE_ERROR_RATE = 0.55       # 尖峰期 ERROR 占比
BASE_ERROR_RATE = 0.05        # 平时 ERROR 占比

HOSTS = ["web-01", "web-02", "web-03"]
SERVICES = ["order-service", "payment-service", "user-service"]

# 每个端点的基线耗时（毫秒），payment 明显更慢 —— 便于"Top N 慢接口"可视化
ENDPOINTS = [
    ("/api/order/create", "POST", 120),
    ("/api/order/query", "GET", 45),
    ("/api/pay/submit", "POST", 380),
    ("/api/pay/callback", "POST", 260),
    ("/api/user/profile", "GET", 30),
    ("/api/user/login", "POST", 150),
    ("/health", "GET", 5),
]

INFO_MSGS = [
    "request completed",
    "cache hit for key order:list",
    "downstream call succeeded",
    "session refreshed",
]
WARN_MSGS = [
    "slow query detected, took {d}ms",
    "connection pool usage above 80%",
    "retrying downstream call, attempt 2",
]
ERROR_MSGS = [
    "payment gateway timeout after {d}ms",
    "upstream connect error: connection refused",
    "db query failed: deadlock detected",
    "failed to serialize response: null pointer",
]
DEBUG_MSGS = [
    "entering handler with trace context",
    "resolved route to controller",
    "sql prepared in {d}ms",
]


def pick_level(ts_min_ago: int) -> str:
    in_spike = SPIKE_END_MIN_AGO <= ts_min_ago <= SPIKE_START_MIN_AGO
    err_rate = SPIKE_ERROR_RATE if in_spike else BASE_ERROR_RATE
    r = random.random()
    if r < err_rate:
        return "ERROR"
    if r < err_rate + 0.15:
        return "WARN"
    if r < err_rate + 0.15 + 0.55:
        return "INFO"
    return "DEBUG"


def status_for(level: str) -> int:
    if level == "ERROR":
        return random.choice([500, 500, 502, 503])
    if level == "WARN":
        return random.choice([200, 200, 404, 429])
    return random.choice([200] * 9 + [304])


def main() -> None:
    now = datetime.now(timezone.utc)
    out_path = "bulk-app-logs.ndjson"
    n = 0

    with open(out_path, "w", encoding="utf-8") as f:
        for _ in range(TOTAL):
            # 时间分布：最近 15 分钟密度略高，整体铺满 3 小时
            minutes_ago = random.uniform(0, WINDOW_HOURS * 60)
            ts = now - timedelta(minutes=minutes_ago)

            # web-03 故障率更高（模拟一台"有问题的机器"）
            if random.random() < 0.45:
                host = "web-03"
            else:
                host = random.choice(HOSTS[:2])

            level = pick_level(minutes_ago)
            path, method, base_ms = random.choice(ENDPOINTS)
            service = (
                "payment-service" if path.startswith("/api/pay")
                else "user-service" if path.startswith("/api/user")
                else "order-service"
            )

            # 尖峰期耗时整体抬升；web-03 再翻一倍
            duration = int(base_ms * random.uniform(0.6, 1.8))
            if SPIKE_END_MIN_AGO <= minutes_ago <= SPIKE_START_MIN_AGO:
                duration = int(duration * random.uniform(2.0, 4.0))
            if host == "web-03":
                duration = int(duration * 1.6)
            duration = max(duration, 3)

            if level == "ERROR":
                msg = random.choice(ERROR_MSGS).format(d=duration)
            elif level == "WARN":
                msg = random.choice(WARN_MSGS).format(d=duration)
            elif level == "DEBUG":
                msg = random.choice(DEBUG_MSGS).format(d=duration)
            else:
                msg = random.choice(INFO_MSGS)

            doc = {
                "@timestamp": ts.strftime("%Y-%m-%dT%H:%M:%S.") + f"{ts.microsecond // 1000:03d}Z",
                "message": msg,
                "log": {"level": level, "logger": service},
                "host": {"name": host},
                "service": {"name": service, "type": "java"},
                "http": {
                    "request": {"method": method},
                    "response": {"status_code": status_for(level)},
                },
                "url": {"path": path},
                "event": {"duration": duration * 1_000_000},  # ECS: 纳秒
                # 演示便利字段（非 ECS）：毫秒，便于 Lens 直接做"耗时"可视化。
                # 真实环境只保留 event.duration，用 Lens 公式 / 1000000 换算即可。
                "duration_ms": duration,
                "user": {"id": f"u{random.randint(1000, 1099)}"},
                "container": {"name": f"{service}-pod-{random.randint(1, 3)}"},
                "demo": {"batch": "kibana-lesson-11"},
            }

            f.write(json.dumps({"create": {}}, ensure_ascii=False) + "\n")
            f.write(json.dumps(doc, ensure_ascii=False) + "\n")
            n += 1

    print(f"生成 {n} 条，写入 {out_path}")
    print(f"时间范围：{(now - timedelta(minutes=WINDOW_HOURS*60)).isoformat()} ~ {now.isoformat()}")


if __name__ == "__main__":
    main()
