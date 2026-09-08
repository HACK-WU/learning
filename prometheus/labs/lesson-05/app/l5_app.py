#!/usr/bin/env python3
"""课 5 可控故障应用（多实例版）

端点：
  GET /metrics
  GET /fault/on?rate=0.5       固定错误率
  GET /fault/off               错误率归零
  GET /fault/status            查看状态

环境变量：
  APP_INSTANCE  实例名（写入 instance 标签语义，默认 hostname）
  APP_TEAM      团队名（注入 team 标签，用于路由树分流）
  APP_ZONE      可用区（注入 zone 标签，用于分组与抑制）
"""
import json
import math
import os
import threading
import time
import urllib.parse
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

START = time.time()
LOCK = threading.Lock()
TICK = 0.1

INSTANCE = os.environ.get("APP_INSTANCE", "app-unknown")
TEAM = os.environ.get("APP_TEAM", "default")
ZONE = os.environ.get("APP_ZONE", "zone-a")

STATE = {
    "rate": 0.0,
    "node_up": 1,
    "total": 0.0,
    "errors": 0.0,
    "changed_at": time.time(),
}


def accumulator():
    while True:
        time.sleep(TICK)
        with LOCK:
            STATE["total"] += 1.0
            STATE["errors"] += STATE["rate"]


def snapshot():
    with LOCK:
        return STATE["total"], STATE["errors"]


def render_metrics():
    total, errors = snapshot()
    ok = total - errors
    up = STATE["node_up"]
    L = []
    L.append("# HELP app_requests_total 演示用请求计数器（按 status 拆分）")
    L.append("# TYPE app_requests_total counter")
    L.append('app_requests_total{route="/api/orders",status="200",team="%s",zone="%s"} %.6f'
             % (TEAM, ZONE, ok))
    L.append('app_requests_total{route="/api/orders",status="500",team="%s",zone="%s"} %.6f'
             % (TEAM, ZONE, errors))
    L.append("# HELP app_error_rate_target 当前目标错误率（瞬时值）")
    L.append("# TYPE app_error_rate_target gauge")
    L.append('app_error_rate_target{team="%s",zone="%s"} %.6f' % (TEAM, ZONE, STATE["rate"]))
    L.append("# HELP app_node_up 模拟节点存活状态（1 存活 / 0 宕机）")
    L.append("# TYPE app_node_up gauge")
    L.append('app_node_up{team="%s",zone="%s"} %d' % (TEAM, ZONE, up))
    return "\n".join(L) + "\n"


class Handler(BaseHTTPRequestHandler):
    def _json(self, obj, code=200):
        body = json.dumps(obj, ensure_ascii=False).encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        u = urllib.parse.urlparse(self.path)
        path, qs = u.path, urllib.parse.parse_qs(u.query)

        if path == "/metrics":
            body = render_metrics().encode("utf-8")
            self.send_response(200)
            self.send_header("Content-Type", "text/plain; version=0.0.4; charset=utf-8")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
            return

        if path == "/fault/on":
            try:
                rate = float(qs.get("rate", ["0.5"])[0])
            except ValueError:
                rate = 0.5
            STATE["rate"] = min(max(rate, 0.0), 1.0)
            STATE["changed_at"] = time.time()
            print("[fault] rate -> %.3f" % STATE["rate"], flush=True)
            self._json({"ok": True, "instance": INSTANCE, "rate": STATE["rate"]})
            return

        if path == "/fault/off":
            STATE["rate"] = 0.0
            STATE["changed_at"] = time.time()
            print("[fault] rate -> 0.0", flush=True)
            self._json({"ok": True, "instance": INSTANCE, "rate": 0.0})
            return

        if path == "/fault/node":
            v = qs.get("v", ["0"])[0]
            STATE["node_up"] = 0 if v in ("0", "down", "false") else 1
            STATE["changed_at"] = time.time()
            print("[fault] node_up -> %d" % STATE["node_up"], flush=True)
            self._json({"ok": True, "instance": INSTANCE, "node_up": STATE["node_up"]})
            return

        if path == "/fault/status":
            self._json({
                "instance": INSTANCE,
                "team": TEAM,
                "zone": ZONE,
                "rate": STATE["rate"],
                "node_up": STATE["node_up"],
                "uptime_s": round(time.time() - START, 1),
                "since_change_s": round(time.time() - STATE["changed_at"], 1),
                "total": round(snapshot()[0], 1),
                "errors": round(snapshot()[1], 1),
            })
            return

        body = ("l5 fault-demo app\n"
                "  /metrics\n  /fault/on?rate=0.5\n  /fault/off\n"
                "  /fault/node?v=0\n  /fault/status\n").encode("utf-8")
        self.send_response(200)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, fmt, *args):
        pass


if __name__ == "__main__":
    threading.Thread(target=accumulator, daemon=True).start()
    print("l5-app[%s] team=%s zone=%s listening on :8080"
          % (INSTANCE, TEAM, ZONE), flush=True)
    ThreadingHTTPServer(("0.0.0.0", 8080), Handler).serve_forever()
