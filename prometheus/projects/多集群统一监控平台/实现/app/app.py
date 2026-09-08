# 多集群统一监控平台 —— 业务服务（三环境共用同一镜像，靠环境变量区分身份）

from http.server import BaseHTTPRequestHandler, HTTPServer
from prometheus_client import Counter, Histogram, Gauge, generate_latest, CONTENT_TYPE_LATEST
import os
import random
import threading
import time

# 环境身份由 docker-compose 注入，用于验证「external_labels 附加环境标」
ENV = os.environ.get("APP_ENV", "unknown")
CLUSTER = os.environ.get("APP_CLUSTER", "unknown")
REGION = os.environ.get("APP_REGION", "unknown")

# 本课故事主线：http_requests_total 从课 1 一路走到实战
REQUESTS = Counter(
    "http_requests_total",
    "HTTP 请求总数（课程主线指标）",
    ["route", "status", "env", "cluster"],
)
LATENCY = Histogram(
    "http_request_duration_seconds",
    "请求延迟分布",
    ["route", "env", "cluster"],
    buckets=[0.01, 0.05, 0.1, 0.25, 0.5, 1.0, 2.5],
)
INFLIGHT = Gauge(
    "http_requests_inflight",
    "正在处理中的请求数",
    ["env", "cluster"],
)

ROUTES = ["/", "/api/orders", "/api/pay", "/api/user"]

# 各环境的「性格」不一样，用来验证全局视图下多集群数据能正确区分
# prod 稳定、staging 慢一点、dev 有错误率——这样告警与对比才有东西可看
ERROR_RATE = {"prod": 0.01, "staging": 0.05, "dev": 0.12}.get(ENV, 0.05)
SLOW_RATE = {"prod": 0.02, "staging": 0.15, "dev": 0.08}.get(ENV, 0.05)


def labels(route):
    return {"route": route, "env": ENV, "cluster": CLUSTER}


def traffic():
    """持续产生流量。故意让 dev 环境偶发「抖动」，供告警演练使用。"""
    while True:
        for route in ROUTES:
            n = random.randint(1, 6)
            status = "500" if random.random() < ERROR_RATE else "200"
            REQUESTS.labels(route=route, status=status, env=ENV, cluster=CLUSTER).inc(n)
            with LATENCY.labels(route=route, env=ENV, cluster=CLUSTER).time():
                if random.random() < SLOW_RATE:
                    time.sleep(random.uniform(0.25, 0.6))
                else:
                    time.sleep(random.uniform(0.005, 0.08))
        time.sleep(1)


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == "/metrics":
            body = generate_latest()
            self.send_response(200)
            self.send_header("Content-Type", CONTENT_TYPE_LATEST)
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
        elif self.path == "/health":
            self.send_response(200)
            self.end_headers()
            self.wfile.write(b"ok")
        else:
            # 业务端点也计入指标，模拟真实服务
            route = self.path if self.path in ROUTES else "/"
            REQUESTS.labels(route=route, status="200", env=ENV, cluster=CLUSTER).inc()
            with INFLIGHT.labels(env=ENV, cluster=CLUSTER).track_inprogress():
                time.sleep(random.uniform(0.005, 0.05))
            self.send_response(200)
            self.end_headers()
            self.wfile.write(b"ok")

    def log_message(self, *args):
        pass


if __name__ == "__main__":
    print(f"[app] env={ENV} cluster={CLUSTER} region={REGION} err={ERROR_RATE} slow={SLOW_RATE}")
    threading.Thread(target=traffic, daemon=True).start()
    HTTPServer(("0.0.0.0", 8000), Handler).serve_forever()
