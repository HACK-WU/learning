# 告警接收端 —— 把 Alertmanager 的通知落盘成日志文件
#
# 为什么要有它：Alertmanager 的 webhook 如果不接一个真实接收端，
# 「分层告警到底有没有生效」就只能靠看 Alertmanager UI，无法验证。
# 有了它，验收清单里就能写「cat 日志确认 prod 走了 pager、dev 走了 silent」。

from http.server import BaseHTTPRequestHandler, HTTPServer
import json
import os
import threading
from datetime import datetime

LOG_DIR = os.environ.get("LOG_DIR", "/logs")

# 每个接收端一个日志文件，便于验收时按通道核对
FILES = {
    "/pager": "pager.log",
    "/chat": "chat.log",
    "/silent": "silent.log",
    "/default": "default.log",
}

lock = threading.Lock()


def write(path, obj):
    with lock:
        with open(path, "a", encoding="utf-8") as f:
            f.write(json.dumps(obj, ensure_ascii=False) + "\n")


class Handler(BaseHTTPRequestHandler):
    def do_POST(self):
        length = int(self.headers.get("Content-Length", 0))
        body = self.rfile.read(length)
        ts = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
        try:
            obj = json.loads(body)
            alerts = obj.get("alerts", [])
            status = obj.get("status", "?")
            n = len(alerts)
            # 提取关键字段，让日志可读
            brief = [
                {
                    "name": a.get("labels", {}).get("alertname"),
                    "env": a.get("labels", {}).get("env", "-"),
                    "cluster": a.get("labels", {}).get("cluster", "-"),
                    "severity": a.get("labels", {}).get("severity", "-"),
                }
                for a in alerts
            ]
            line = {"ts": ts, "channel": self.path, "status": status, "count": n, "alerts": brief}
        except Exception as e:
            line = {"ts": ts, "channel": self.path, "parse_error": str(e)}

        fname = FILES.get(self.path, "other.log")
        write(os.path.join(LOG_DIR, fname), line)
        print(f"[{ts}] {self.path} -> {line.get('count', 0)} alerts", flush=True)

        self.send_response(200)
        self.end_headers()
        self.wfile.write(b"ok")

    def log_message(self, *args):
        pass


if __name__ == "__main__":
    os.makedirs(LOG_DIR, exist_ok=True)
    print(f"[webhook] listening on 8080, log dir = {LOG_DIR}", flush=True)
    HTTPServer(("0.0.0.0", 8080), Handler).serve_forever()
