"""课 9 被测应用：产生可区分来源的指标，用于验证三种长期存储方案的去重与全局查询。

与课 8 保持一致：requests_total（counter）、inflight（gauge）、request_duration_seconds（histogram）。
额外提供 /set 接口，便于人为制造两个副本的数值差异。
"""
import os
import random
import time
from prometheus_client import Counter, Gauge, Histogram, start_http_server

APP_ID = os.environ.get("APP_ID", "app")

REQUESTS = Counter(
    "app_requests_total", "Total requests", ["route", "status"]
)
INFLIGHT = Gauge("app_inflight", "Requests in flight")
DURATION = Histogram(
    "app_request_duration_seconds", "Request duration", ["route"],
    buckets=(0.01, 0.05, 0.1, 0.25, 0.5, 1.0),
)

ROUTES = ["/", "/api/list", "/api/detail"]

# ---- 高基数造数指标（用于 remote read 分模式对照）----
# CARD：每个 route 下的序列数，由环境变量 RR_CARD 控制（默认 0=关闭）
CARD = int(os.environ.get("RR_CARD", "0"))
if CARD > 0:
    BENCH = Gauge("rr_bench", "high cardinality bench series", ["route", "idx"])
    for r in ROUTES:
        for i in range(CARD):
            BENCH.labels(route=r, idx=f"{i:05d}").set(0.0)


def loop():
    while True:
        for route in ROUTES:
            n = random.randint(3, 12)
            for _ in range(n):
                REQUESTS.labels(route=route, status="200").inc()
            INFLIGHT.set(random.randint(1, 20))
            if CARD > 0:
                for i in range(CARD):
                    BENCH.labels(route=route, idx=f"{i:05d}").set(
                        float(random.randint(1, 1000))
                    )
            with DURATION.labels(route=route).time():
                time.sleep(random.uniform(0.005, 0.03))
        time.sleep(1)


if __name__ == "__main__":
    print(f"{APP_ID} metrics on :8000", flush=True)
    start_http_server(8000, addr="0.0.0.0")
    loop()
