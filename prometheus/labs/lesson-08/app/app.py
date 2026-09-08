#!/usr/bin/env python3
"""课 8 数据源：507 条序列（与课 7 同构，便于对照）"""
import random
import time
from http.server import BaseHTTPRequestHandler, HTTPServer

random.seed(8)
N_CARDS = 500


class Cards:
    def __init__(self):
        # 每条卡一个随机游走的余额
        self.bal = {f"{i:04d}": random.uniform(100, 5000) for i in range(N_CARDS)}

    def tick(self):
        for k in self.bal:
            self.bal[k] = max(0.0, self.bal[k] + random.gauss(0, 12))


CARDS = Cards()
START = time.time()
REQ_TOTAL = {"n": 0}


def metrics() -> str:
    out = []
    # 1. 500 条卡片余额序列
    out.append("# HELP l8_card_balance Card balance")
    out.append("# TYPE l8_card_balance gauge")
    for i in range(N_CARDS):
        idx = f"{i:04d}"
        out.append(f'l8_card_balance{{idx="{idx}",zone="z{i%3}"}} {CARDS.bal[idx]:.2f}')

    # 2. 4 条请求计数（counter，用于 rate 演示）
    out.append("# HELP l8_requests_total Total requests")
    out.append("# TYPE l8_requests_total counter")
    for m in ("GET", "POST", "PUT", "DELETE"):
        out.append(
            f'l8_requests_total{{method="{m}",zone="z0"}} '
            f'{1000 + REQ_TOTAL["n"] * (1 + "GETPOSTPUTDELETE".find(m) // 4)}'
        )

    # 3. up（Prometheus 自动附加 job/instance，这里给个基础值）
    out.append("# HELP up Up status")
    out.append("# TYPE up gauge")
    out.append("up 1")

    # 4. runtime 序列（用于观察序列数）
    out.append("# HELP l8_runtime_seconds Runtime")
    out.append("# TYPE l8_runtime_seconds counter")
    out.append(f"l8_runtime_seconds {time.time() - START:.3f}")

    # 5. build_info（恒定序列）
    out.append("# HELP l8_build_info Build info")
    out.append("# TYPE l8_build_info gauge")
    out.append('l8_build_info{version="1.0.0",revision="abc1234"} 1')

    return "\n".join(out) + "\n"


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == "/metrics":
            CARDS.tick()
            REQ_TOTAL["n"] += 1
            body = metrics().encode()
            self.send_response(200)
            self.send_header("Content-Type", "text/plain; version=0.0.4; charset=utf-8")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
        elif self.path == "/bump":
            REQ_TOTAL["n"] += 10
            self.send_response(200)
            self.end_headers()
            self.wfile.write(b"ok\n")
        else:
            self.send_response(404)
            self.end_headers()

    def log_message(self, *a):
        pass


if __name__ == "__main__":
    HTTPServer(("0.0.0.0", 8080), Handler).serve_forever()
