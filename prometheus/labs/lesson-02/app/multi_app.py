import os
import time
from http.server import BaseHTTPRequestHandler, HTTPServer

# 由环境变量注入身份，这样一个镜像能跑出多个"不同的服务"
APP_NAME = os.environ.get("APP_NAME", "unknown")
ENV_NAME = os.environ.get("ENV_NAME", "dev")
VERSION = os.environ.get("VERSION", "1.0.0")
REGION = os.environ.get("REGION", "cn-south")

# 关键开关：打开后，暴露的样本会自带 job / instance 标签，
# 用于演示 honor_labels 的标签冲突
FAKE_LABELS = os.environ.get("FAKE_LABELS", "0") == "1"

START = time.time()


def base_labels(extra=""):
    """拼出标签串。FAKE_LABELS 打开时故意带上 job / instance。"""
    parts = [
        'app="%s"' % APP_NAME,
        'env="%s"' % ENV_NAME,
        'version="%s"' % VERSION,
        'region="%s"' % REGION,
    ]
    if FAKE_LABELS:
        # 故意与 Prometheus 自动附加的 job / instance 冲突
        parts.append('job="i-am-the-real-job"')
        parts.append('instance="i-am-the-real-instance:9999"')
    if extra:
        parts.append(extra)
    return ",".join(parts)


def render_metrics():
    uptime = int(time.time() - START)
    lines = []

    lines.append("# HELP app_requests_total 演示用请求计数器")
    lines.append("# TYPE app_requests_total counter")
    lines.append("app_requests_total{%s} %d" % (base_labels(), uptime * 3))
    lines.append("app_requests_total{%s} %d" % (base_labels('route="/health"'), uptime))

    lines.append("# HELP app_build_info 构建信息，值恒为 1")
    lines.append("# TYPE app_build_info gauge")
    lines.append("app_build_info{%s} 1" % base_labels())

    # 这条只在高基数演示（metric_relabel drop）时才有意义
    lines.append("# HELP app_debug_user_id 演示用的高基数调试指标")
    lines.append("# TYPE app_debug_user_id gauge")
    lines.append("app_debug_user_id{%s} 1" % base_labels('user_id="u-10001"'))

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

        body = ("hello from %s (env=%s)\n" % (APP_NAME, ENV_NAME)).encode("utf-8")
        self.send_response(200)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, fmt, *args):
        pass


if __name__ == "__main__":
    print("multi-app listening on :8080 app=%s env=%s fake_labels=%s"
          % (APP_NAME, ENV_NAME, FAKE_LABELS), flush=True)
    HTTPServer(("0.0.0.0", 8080), Handler).serve_forever()
