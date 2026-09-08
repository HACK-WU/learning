import os
import time
from http.server import BaseHTTPRequestHandler, HTTPServer

# 固定的标签维度，方便计算序列数
# app_requests_total: route(3) x status(2) = 6 条
# app_build_info: 1 条（无额外维度）
# app_debug_user_id: user_id(2) = 2 条
# 合计 9 条序列（不含 Prometheus 自动生成的 up / scrape_* 等）

ROUTES = ["/health", "/api/orders", "/api/users"]
STATUSES = ["200", "500"]
USERS = ["u-10001", "u-10002"]

START = time.time()


def render_metrics():
    uptime = int(time.time() - START)
    lines = []

    lines.append("# HELP app_requests_total 演示用请求计数器")
    lines.append("# TYPE app_requests_total counter")
    for route in ROUTES:
        for status in STATUSES:
            # 让值随时间变化，便于观察 chunk 打包
            val = uptime * len(route) + (0 if status == "200" else 7)
            lines.append('app_requests_total{route="%s",status="%s"} %d'
                         % (route, status, val))

    lines.append("# HELP app_build_info 构建信息，值恒为 1")
    lines.append("# TYPE app_build_info gauge")
    lines.append('app_build_info{version="1.2.3",region="cn-south"} 1')

    lines.append("# HELP app_debug_user_id 演示用的高基数调试指标")
    lines.append("# TYPE app_debug_user_id gauge")
    for u in USERS:
        lines.append('app_debug_user_id{user_id="%s"} 1' % u)

    return "\n".join(lines) + "\n"


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == "/metrics":
            body = render_metrics().encode("utf-8")
            self.send_response(200)
            self.send_header("Content-Type", "text/plain; version=0.0.4; charset=utf-8")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
            return

        body = b"l3 demo app\n"
        self.send_response(200)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, fmt, *args):
        pass


if __name__ == "__main__":
    print("l3-app listening on :8080", flush=True)
    HTTPServer(("0.0.0.0", 8080), Handler).serve_forever()
