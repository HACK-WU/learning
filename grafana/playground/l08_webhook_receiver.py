#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
L08 webhook 接收端：让"通知"这件事变得可观测

为什么需要它：
  本环境没有 SMTP / 企业微信 / 钉钉的真实凭据。
  如果只配一个指向外网的 webhook，我们看不到"到底发了没、发了几次"。

  → 起一个本地 HTTP 服务，把 Grafana 发来的每一条通知落盘成 JSONL。
    课 8 的"分组收敛""静默生效"全靠读这个文件来验证。

用法：
  nohup python3 webhook_receiver.py > /dev/null 2>&1 &
  日志： l08-webhook-log.jsonl
"""
import json, os, sys, time
from http.server import BaseHTTPRequestHandler, HTTPServer

LOG = os.path.join(os.path.dirname(os.path.abspath(__file__)), "l08-webhook-log.jsonl")
PORT = 9999


class H(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def _log(self, tag, payload):
        rec = {"t": time.time(),
               "ts": time.strftime("%H:%M:%S", time.localtime()),
               "tag": tag,
               "payload": payload}
        try:
            with open(LOG, "a", encoding="utf-8") as f:
                f.write(json.dumps(rec, ensure_ascii=False) + "\n")
        except Exception as e:
            print("write fail: %s" % e, file=sys.stderr)

    def do_POST(self):
        ln = int(self.headers.get("Content-Length") or 0)
        raw = self.rfile.read(ln).decode("utf-8", "replace") if ln else ""
        try:
            body = json.loads(raw) if raw else {}
        except Exception:
            body = {"_raw": raw[:500]}

        # Grafana webhook 的标准结构：{status, alerts:[...], groupLabels, commonLabels, commonAnnotations}
        alerts = body.get("alerts") or []
        summary = {
            "status": body.get("status"),
            "groupLabels": body.get("groupLabels"),
            "commonLabels": body.get("commonLabels"),
            "alert_count": len(alerts),
            "names": sorted({(a.get("labels") or {}).get("alertname") for a in alerts}),
            "instances": sorted({(a.get("labels") or {}).get("instance") for a in alerts
                                 if (a.get("labels") or {}).get("instance")}),
            "states": sorted({a.get("status") for a in alerts}),
            "startsAt": [a.get("startsAt") for a in alerts][:3],
        }
        self._log(self.path, summary)
        print("[%s] recv %s  alerts=%d  group=%s  %s" % (
            time.strftime("%H:%M:%S"), self.path, len(alerts),
            body.get("groupLabels"), summary["names"]), flush=True)

        resp = b'{"ok":true}'
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(resp)))
        self.end_headers()
        self.wfile.write(resp)

    def do_GET(self):
        resp = b'{"ok":true,"receiver":"l08"}'
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(resp)))
        self.end_headers()
        self.wfile.write(resp)

    def log_message(self, fmt, *args):
        pass


if __name__ == "__main__":
    # 清空旧日志
    if os.path.exists(LOG):
        os.remove(LOG)
    print("l08 webhook receiver on :%d -> %s" % (PORT, LOG), flush=True)
    HTTPServer(("0.0.0.0", PORT), H).serve_forever()
