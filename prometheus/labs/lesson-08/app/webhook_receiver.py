#!/usr/bin/env python3
"""Alertmanager webhook 接收器：记录每条通知，用于验证 gossip 去重是否生效"""
import json
import os
import time
from http.server import BaseHTTPRequestHandler, HTTPServer

LOG = "/data/notifications.jsonl"
os.makedirs("/data", exist_ok=True)


class Handler(BaseHTTPRequestHandler):
    def do_POST(self):
        n = int(self.headers.get("Content-Length", 0))
        body = self.rfile.read(n)
        try:
            data = json.loads(body)
        except Exception:
            data = {}
        rec = {
            "ts": time.time(),
            "status": data.get("status"),
            "groupLabels": data.get("groupLabels"),
            "commonLabels": data.get("commonLabels", {}),
            "alerts": [
                {
                    "status": a.get("status"),
                    "labels": a.get("labels"),
                    "startsAt": a.get("startsAt"),
                }
                for a in data.get("alerts", [])
            ],
        }
        with open(LOG, "a") as f:
            f.write(json.dumps(rec) + "\n")
        # 控制台也打一行，便于 docker logs 观察
        print(f"[NOTIFY] status={rec['status']} alerts={len(rec['alerts'])} "
              f"labels={rec['commonLabels']}", flush=True)
        self.send_response(200)
        self.end_headers()
        self.wfile.write(b"ok\n")

    def do_GET(self):
        # /count 返回收到的通知条数
        if self.path == "/count":
            try:
                with open(LOG) as f:
                    n = sum(1 for _ in f)
            except FileNotFoundError:
                n = 0
            body = str(n).encode()
            self.send_response(200)
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
        elif self.path == "/reset":
            open(LOG, "w").close()
            self.send_response(200)
            self.end_headers()
            self.wfile.write(b"reset\n")
        else:
            self.send_response(404)
            self.end_headers()

    def log_message(self, *a):
        pass


if __name__ == "__main__":
    HTTPServer(("0.0.0.0", 8080), Handler).serve_forever()
