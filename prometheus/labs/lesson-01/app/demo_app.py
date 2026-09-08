import time
import random
from http.server import BaseHTTPRequestHandler, HTTPServer

# 全局计数器：模拟一个长期运行的服务自己暴露指标
REQUESTS = {"GET /": 0, "GET /order": 0}
STATUSES = {"200": 0, "500": 0}


def bump(endpoint):
    """每次请求累加计数器，并按 8% 概率制造一次 500。"""
    REQUESTS[endpoint] += 1
    status = "500" if random.random() < 0.08 else "200"
    STATUSES[status] += 1
    return status


def render_metrics():
    """手写 Prometheus 文本暴露格式。"""
    lines = [
        "# HELP demo_http_requests_total 演示用请求计数器",
        "# TYPE demo_http_requests_total counter",
    ]
    for endpoint, value in REQUESTS.items():
        lines.append(f'demo_http_requests_total{{endpoint="{endpoint}"}} {value}')
    lines.append("# HELP demo_http_request_status_total 按状态码分组的请求数")
    lines.append("# TYPE demo_http_request_status_total counter")
    for status, value in STATUSES.items():
        lines.append(f'demo_http_request_status_total{{status="{status}"}} {value}')
    lines.append("# HELP demo_build_info 构建信息，值恒为 1")
    lines.append("# TYPE demo_build_info gauge")
    lines.append('demo_build_info{version="1.0.0"} 1')
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

        endpoint = "GET /order" if self.path == "/order" else "GET /"
        status = bump(endpoint)
        body = f"hello from demo-app, path={self.path}, status={status}\n".encode("utf-8")
        self.send_response(int(status))
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, fmt, *args):
        pass


if __name__ == "__main__":
    print("demo-app listening on :8080", flush=True)
    HTTPServer(("0.0.0.0", 8080), Handler).serve_forever()
