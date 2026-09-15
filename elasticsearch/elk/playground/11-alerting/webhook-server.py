#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
课 12 实操：本机 webhook 接收端点（供 Kibana Connector 回调）

- 监听 0.0.0.0:9999，任何 POST 都落盘到 webhook-inbox.log
- Kibana 容器内部用 http://host.docker.internal:9999/webhook 访问

用法:
  python3 webhook-server.py            # 前台运行
  python3 webhook-server.py &          # 后台运行
"""
import json
from datetime import datetime
from http.server import BaseHTTPRequestHandler, HTTPServer

PORT = 9999
LOG = "webhook-inbox.log"


class Handler(BaseHTTPRequestHandler):
    def _handle(self):
        length = int(self.headers.get("Content-Length") or 0)
        body = self.rfile.read(length).decode("utf-8", errors="replace") if length else ""
        ts = datetime.now().isoformat(timespec="seconds")
        line = f"=== {ts} {self.command} {self.path} ===\n{body}\n"
        with open(LOG, "a", encoding="utf-8") as f:
            f.write(line)
        print(line, flush=True)
        # 尽量回 200，避免 Kibana 认为投递失败
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.end_headers()
        self.wfile.write(b'{"ok":true}')

    def do_POST(self):
        self._handle()

    def do_GET(self):
        self._handle()

    def log_message(self, fmt, *args):  # 关掉默认访问日志，避免干扰
        pass


if __name__ == "__main__":
    print(f"listening on 0.0.0.0:{PORT}, writing to {LOG}")
    HTTPServer(("0.0.0.0", PORT), Handler).serve_forever()
