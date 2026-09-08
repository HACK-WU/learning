#!/usr/bin/env python3
"""课 7 数据源：产生有辨识度的指标，用于 remote write 全链路观测。"""
import random
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

CARDS = 500          # 基数：足以让 remote write 有可观的样本量
START = time.time()


def metrics_text():
    ts_ms = int(time.time() * 1000)
    lines = []
    lines.append("# HELP l7_card_balance Simulated per-card balance")
    lines.append("# TYPE l7_card_balance gauge")
    for i in range(CARDS):
        lines.append(f'l7_card_balance{{idx="{i:04d}",region="r{i%4}"}} {random.random()*100:.3f}')
    lines.append("# HELP l7_requests_total Simulated request counter")
    lines.append("# TYPE l7_requests_total counter")
    for i in range(4):
        lines.append(f'l7_requests_total{{region="r{i}"}} {int(time.time()-START)*10+i}')
    lines.append("# HELP l7_up Scrape health")
    lines.append("# TYPE l7_up gauge")
    lines.append(f"l7_up {1}")
    lines.append("# HELP l7_runtime_seconds Process uptime")
    lines.append("# TYPE l7_runtime_seconds counter")
    lines.append(f"l7_runtime_seconds {time.time()-START:.1f}")
    lines.append(f"# HELP l7_build_info Build info")
    lines.append("# TYPE l7_build_info gauge")
    lines.append('l7_build_info{version="1.0.0"} 1')
    lines.append("# EOF")
    del ts_ms
    return "\n".join(lines) + "\n"


class H(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, *a):
        pass

    def do_GET(self):
        if self.path == "/metrics":
            body = metrics_text().encode()
            self.send_response(200)
            self.send_header("Content-Type", "text/plain; version=0.0.4; charset=utf-8")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
        else:
            body = b"ok"
            self.send_response(200)
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)


if __name__ == "__main__":
    print("l7-app on :8080", flush=True)
    ThreadingHTTPServer(("0.0.0.0", 8080), H).serve_forever()
