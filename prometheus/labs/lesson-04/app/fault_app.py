import json
import math
import threading
import time
import urllib.parse
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

# 课 4 可控故障应用
#
# 端点：
#   GET /metrics                                 暴露指标
#   GET /fault/on?rate=0.5                       固定错误率（触发告警）
#   GET /fault/off                               错误率归零（告警恢复）
#   GET /fault/wobble?center=0.1&period=30&amp=0.06
#                                                错误率围绕阈值正弦振荡（演示抖动）
#   GET /fault/status                            查看当前状态
#
# 计数器用后台线程累加（每 0.1s 一跳），而不是"当前错误率 × uptime"合成。
# 这一点很关键：合成法会追溯性地改写全部历史，导致 rate() 行为失真；
# 累加法的历史真实反映"当时的错误率"，rate() 才会呈现出真实的滞后。

START = time.time()
LOCK = threading.Lock()
TICK = 0.1

STATE = {
    "mode": "fixed",      # "fixed" | "wobble"
    "rate": 0.0,          # fixed 模式的错误率
    "center": 0.08,       # wobble 中心
    "amp": 0.05,          # wobble 振幅
    "period": 30.0,       # wobble 周期（秒）
    "total": 0.0,         # 累计请求数
    "errors": 0.0,        # 累计错误数
    "changed_at": time.time(),
}


def current_rate():
    """返回当前这一跳应有的错误率。"""
    if STATE["mode"] == "wobble":
        t = time.time()
        v = STATE["center"] + STATE["amp"] * math.sin(2 * math.pi * t / STATE["period"])
    else:
        v = STATE["rate"]
    return min(max(v, 0.0), 1.0)


def accumulator():
    """后台累加器：每 TICK 秒按当前错误率累加一次。"""
    while True:
        time.sleep(TICK)
        r = current_rate()
        with LOCK:
            STATE["total"] += 1.0
            STATE["errors"] += r


def snapshot():
    with LOCK:
        return STATE["total"], STATE["errors"]


def render_metrics():
    total, errors = snapshot()
    ok = total - errors
    lines = []

    lines.append("# HELP app_requests_total 演示用请求计数器（按 status 拆分）")
    lines.append("# TYPE app_requests_total counter")
    lines.append('app_requests_total{route="/api/orders",status="200"} %.6f' % ok)
    lines.append('app_requests_total{route="/api/orders",status="500"} %.6f' % errors)

    lines.append("# HELP app_error_rate_target 当前这一跳的目标错误率（瞬时值）")
    lines.append("# TYPE app_error_rate_target gauge")
    lines.append("app_error_rate_target %.6f" % current_rate())

    lines.append("# HELP app_inprogress_requests 演示用的进行中请求数")
    lines.append("# TYPE app_inprogress_requests gauge")
    lines.append('app_inprogress_requests{route="/api/orders"} %d' % int(ok % 7))

    return "\n".join(lines) + "\n"


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
        path = u.path
        qs = urllib.parse.parse_qs(u.query)

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
            STATE["mode"] = "fixed"
            STATE["rate"] = min(max(rate, 0.0), 1.0)
            STATE["changed_at"] = time.time()
            print("[fault] fixed rate -> %.3f" % STATE["rate"], flush=True)
            self._json({"ok": True, "mode": "fixed", "rate": STATE["rate"]})
            return

        if path == "/fault/off":
            STATE["mode"] = "fixed"
            STATE["rate"] = 0.0
            STATE["changed_at"] = time.time()
            print("[fault] fixed rate -> 0.0", flush=True)
            self._json({"ok": True, "mode": "fixed", "rate": 0.0})
            return

        if path == "/fault/wobble":
            def g(k, d):
                try:
                    return float(qs.get(k, [str(d)])[0])
                except ValueError:
                    return d
            STATE["mode"] = "wobble"
            STATE["center"] = g("center", STATE["center"])
            STATE["amp"] = g("amp", STATE["amp"])
            STATE["period"] = g("period", STATE["period"])
            STATE["changed_at"] = time.time()
            print("[fault] wobble center=%.3f amp=%.3f period=%.1fs"
                  % (STATE["center"], STATE["amp"], STATE["period"]), flush=True)
            self._json({"ok": True, "mode": "wobble", "center": STATE["center"],
                        "amp": STATE["amp"], "period": STATE["period"]})
            return

        if path == "/fault/status":
            self._json({
                "mode": STATE["mode"],
                "instant_rate": round(current_rate(), 4),
                "uptime_s": round(time.time() - START, 1),
                "since_change_s": round(time.time() - STATE["changed_at"], 1),
                "total_requests": round(snapshot()[0], 1),
                "total_errors": round(snapshot()[1], 1),
            })
            return

        body = (b"l4 fault-demo app\n"
                b"  /metrics\n"
                b"  /fault/on?rate=0.5\n"
                b"  /fault/off\n"
                b"  /fault/wobble?center=0.1&period=30&amp=0.06\n"
                b"  /fault/status\n")
        self.send_response(200)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, fmt, *args):
        pass


if __name__ == "__main__":
    threading.Thread(target=accumulator, daemon=True).start()
    print("l4-app listening on :8080", flush=True)
    ThreadingHTTPServer(("0.0.0.0", 8080), Handler).serve_forever()
