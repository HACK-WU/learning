#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
告警接收 webhook：把 Grafana 发来的告警打印出来并落盘。

为什么要有它：
  告警配置的正确性不能靠「界面上看到规则存在」来判断，
  必须【真的收到一条告警】才算验证通过。这个 webhook 就是那个「证据」。
"""
import json
import os
import sys
from datetime import datetime
from http.server import BaseHTTPRequestHandler, HTTPServer

OUT_DIR = os.getenv("OUT_DIR", "/out")
os.makedirs(OUT_DIR, exist_ok=True)
PORT = int(os.getenv("PORT", "8080"))


class Handler(BaseHTTPRequestHandler):
    def do_POST(self):
        n = int(self.headers.get("Content-Length", 0))
        body = self.rfile.read(n)
        ts = datetime.now().strftime("%H:%M:%S")
        print(f"\n{'='*70}\n[{ts}] 收到告警 → {self.path}", flush=True)
        try:
            d = json.loads(body)
            st = d.get("status", "?")
            alerts = d.get("alerts", [])
            print(f"  状态={st}  告警条数={len(alerts)}", flush=True)
            print(f"  分组标签={d.get('groupLabels', {})}", flush=True)
            for a in alerts:
                labels = a.get("labels", {})
                anns = a.get("annotations", {})
                print(f"    - [{a.get('status')}] {labels.get('alertname')}", flush=True)
                print(f"      labels: {labels}", flush=True)
                print(f"      summary: {anns.get('summary', '')}", flush=True)
                print(f"      dashboard: {anns.get('runbook_url', '')}", flush=True)
        except Exception as e:  # noqa: BLE001
            print(f"  (非 JSON 或解析失败: {e}) body={body[:200]}", flush=True)
        # 落盘，供验收清单核对
        fn = os.path.join(OUT_DIR, f"alert-{datetime.now().strftime('%H%M%S')}.json")
        with open(fn, "wb") as f:
            f.write(body)
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.end_headers()
        self.wfile.write(b'{"ok":true}')

    def log_message(self, fmt, *args):
        pass


if __name__ == "__main__":
    print(f"webhook 监听 :{PORT}，告警写入 {OUT_DIR}", flush=True)
    HTTPServer(("0.0.0.0", PORT), Handler).serve_forever()
