#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
暴露一个带 exemplar 的 Prometheus 直方图 /metrics

⚠️ 本课最关键的一行是 Content-Type（见下方 do_GET）：
   application/openmetrics-text  ← 正确，Prometheus 才解析 # {...} 为 exemplar
   text/plain                    ← 错误，Prometheus 把 # 当注释，target 直接 down

exemplar 语法（OpenMetrics text format）：
    metric_bucket{le="0.5"} 7.0 # {traceID="xxx"} 0.42 1700000000000
                                   ^^^^^^^^ 标签   ^^^^值  ^^^^时间戳(ms)
"""
import time, http.server, socketserver

TRACE = "a1b2c3d4e5f60718293a4b5c6d7e8f90"


class H(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path != "/metrics":
            self.send_response(404)
            self.end_headers()
            return
        ts_ms = int(time.time() * 1000)
        lines = [
            "# HELP h_test 请求耗时直方图",
            "# TYPE h_test histogram",
            # 每个 le 桶只出现一次；exemplar 挂在唯一的 0.5 桶行末尾
            'h_test_bucket{le="0.5",job="shop",svc="payment"} 7.0 # {traceID="' + TRACE + '"} 0.42 ' + str(ts_ms),
            'h_test_bucket{le="+Inf",job="shop",svc="payment"} 8.0',
            'h_test_sum{job="shop",svc="payment"} 3.4',
            'h_test_count{job="shop",svc="payment"} 8.0',
            "# EOF",
        ]
        body = ("\n".join(lines) + "\n").encode()
        self.send_response(200)
        # ★★★ 关键：必须是 openmetrics-text，用 text/plain 会被 Prometheus 拒绝 ★★★
        self.send_header("Content-Type", "application/openmetrics-text; version=1.0.0; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *a):
        pass


socketserver.TCPServer.allow_reuse_address = True
with socketserver.TCPServer(("0.0.0.0", 9900), H) as httpd:
    httpd.serve_forever()
