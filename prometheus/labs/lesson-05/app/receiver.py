#!/usr/bin/env python3
"""课 5 告警接收器：把 Alertmanager 发来的每一条通知落盘成 JSONL。

不同 receiver 走不同 URL path，便于验证路由树分流是否生效：
  /default  /payments  /search-critical  /infra
查询接口：
  GET /list?path=payments    列出该 receiver 收到的所有通知
  GET /count                 各 receiver 计数
  GET /reset                 清空
"""
import json
import os
import threading
import time
import urllib.parse
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

LOG_DIR = "/logs"
LOCK = threading.Lock()
START = time.time()

os.makedirs(LOG_DIR, exist_ok=True)


def log_path(name):
    return os.path.join(LOG_DIR, name + ".jsonl")


def append(name, obj):
    with LOCK:
        with open(log_path(name), "a", encoding="utf-8") as f:
            f.write(json.dumps(obj, ensure_ascii=False) + "\n")


def read(name):
    p = log_path(name)
    if not os.path.exists(p):
        return []
    out = []
    with open(p, "r", encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if line:
                try:
                    out.append(json.loads(line))
                except Exception:
                    pass
    return out


class Handler(BaseHTTPRequestHandler):
    def _json(self, obj, code=200):
        body = json.dumps(obj, ensure_ascii=False).encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_POST(self):
        path = urllib.parse.urlparse(self.path).path.strip("/")
        name = path if path else "default"
        try:
            n = int(self.headers.get("Content-Length", 0))
            raw = self.rfile.read(n).decode("utf-8")
            payload = json.loads(raw)
        except Exception as e:
            self._json({"error": str(e)}, 400)
            return

        recv_at = time.time()
        record = {
            "recv_at": round(recv_at, 3),
            "recv_since_start": round(recv_at - START, 2),
            "receiver": name,
            "status": payload.get("status"),
            "groupLabels": payload.get("groupLabels", {}),
            "commonLabels": payload.get("commonLabels", {}),
            "commonAnnotations": payload.get("commonAnnotations", {}),
            "externalURL": payload.get("externalURL", ""),
            "alerts": [
                {
                    "status": a.get("status"),
                    "labels": a.get("labels", {}),
                    "annotations": a.get("annotations", {}),
                    "startsAt": a.get("startsAt", ""),
                    "endsAt": a.get("endsAt", ""),
                    "generatorURL": a.get("generatorURL", ""),
                }
                for a in payload.get("alerts", [])
            ],
        }
        append(name, record)
        print("[%s] status=%s alerts=%d groupLabels=%s"
              % (name, record["status"], len(record["alerts"]),
                 json.dumps(record["groupLabels"], ensure_ascii=False)), flush=True)
        self._json({"ok": True})

    def do_GET(self):
        u = urllib.parse.urlparse(self.path)
        path, qs = u.path.strip("/"), urllib.parse.parse_qs(u.query)

        if path == "list":
            name = qs.get("path", ["default"])[0]
            rows = read(name)
            brief = qs.get("brief", ["1"])[0] == "1"
            if brief:
                out = [{
                    "t": r["recv_since_start"],
                    "status": r["status"],
                    "groupLabels": r["groupLabels"],
                    "n_alerts": len(r["alerts"]),
                    "alertnames": sorted({a["labels"].get("alertname", "?")
                                          for a in r["alerts"]}),
                    "instances": sorted({a["labels"].get("instance", "?")
                                         for a in r["alerts"]}),
                } for r in rows]
            else:
                out = rows
            self._json({"receiver": name, "count": len(rows), "items": out})
            return

        if path == "count":
            names = ["default", "payments", "search-critical", "infra"]
            self._json({n: len(read(n)) for n in names})
            return

        if path == "reset":
            for f in os.listdir(LOG_DIR):
                if f.endswith(".jsonl"):
                    os.remove(os.path.join(LOG_DIR, f))
            self._json({"ok": True, "msg": "cleared"})
            return

        self._json({"error": "unknown path"}, 404)

    def log_message(self, fmt, *args):
        pass


if __name__ == "__main__":
    print("l5-receiver listening on :8099", flush=True)
    ThreadingHTTPServer(("0.0.0.0", 8099), Handler).serve_forever()
