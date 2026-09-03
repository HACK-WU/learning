#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
多租户监控平台 · 指标导出器

用标准库手写一个 Prometheus 文本格式的 /metrics 端点，避免依赖 prometheus_client
（容器镜像 python:3.12-slim 不带该库，离线环境装不了）。

用法：
    python3 exporter.py --tenant tenant-a --scenario degraded --port 9100
    python3 exporter.py --tenant tenant-b --scenario healthy  --port 9100

设计意图：
  * tenant-a 走 degraded 场景 —— /api/orders 注入约 5% 的 500 与 3 倍延迟
  * tenant-b 走 healthy  场景 —— 全程无错误
  这样两个租户在告警与查询上会呈现「一个有病、一个健康」的可对照结果。
"""

import argparse
import math
import random
import time
from collections import defaultdict
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

BUCKETS = [0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1.0, 2.5, 5.0, 10.0]

# 每个租户的接口与流量权重
PATHS = {
    "tenant-a": [("/api/orders", 0.50), ("/api/users", 0.35), ("/api/health", 0.15)],
    "tenant-b": [("/api/page", 0.50), ("/api/search", 0.35), ("/api/health", 0.15)],
}

# 降级租户的问题接口：错误率与延迟倍数
DEGRADED = {
    "tenant-a": {"/api/orders": (0.05, 3.0)},  # path -> (错误率, 延迟倍数)
}


class State:
    """跨抓取累积的状态。计数器必须单调递增，所以每次抓取生成「距上次抓取新增的量」。"""

    def __init__(self, tenant, scenario, rps, users, drop_userid=False):
        self.tenant = tenant
        self.scenario = scenario
        self.rps = rps
        self.users = users
        self.drop_userid = drop_userid
        self.last = time.time()
        self.counts = defaultdict(int)          # (path, status) -> 累计次数
        self.hist = defaultdict(lambda: [0] * len(BUCKETS))  # path -> 各桶计数
        self.hist_sum = defaultdict(float)      # path -> 延迟总和
        self.user_counts = defaultdict(int)     # user_id -> 累计次数（高基数来源）
        self.start = time.time()

    def advance(self):
        """按经过时间推进状态。"""
        now = time.time()
        elapsed = now - self.last
        self.last = now
        n = int(self.rps * elapsed)
        if n <= 0:
            return

        paths = PATHS[self.tenant]
        weights = [w for _, w in paths]
        broken = DEGRADED.get(self.tenant, {}) if self.scenario == "degraded" else {}

        for _ in range(n):
            path = random.choices([p for p, _ in paths], weights=weights)[0]
            err_rate, lat_mult = broken.get(path, (0.0, 1.0))

            status = "500" if random.random() < err_rate else "200"
            self.counts[(path, status)] += 1

            # 对数正态分布模拟延迟长尾；错误请求往往更慢
            base = math.exp(random.gauss(math.log(0.03), 0.6))
            latency = base * lat_mult * (2.0 if status == "500" else 1.0)
            self.hist_sum[path] += latency

            idx = 0
            while idx < len(BUCKETS) and latency > BUCKETS[idx]:
                idx += 1
            if idx < len(BUCKETS):
                self.hist[path][idx] += 1

            # 高基数：每个请求归属一个随机用户 —— 这是基数治理演示的数据源
            uid = "u%04d" % random.randrange(self.users)
            self.user_counts[uid] += 1


def esc(v):
    """转义标签值里的特殊字符。"""
    return str(v).replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n")


def render(state):
    t = state.tenant
    lines = []

    lines.append("# HELP app_up 导出器是否存活")
    lines.append("# TYPE app_up gauge")
    lines.append('app_up{service="%s"} 1' % esc(t))
    lines.append("")

    lines.append("# HELP app_inflight_requests 当前在途请求数（gauge）")
    lines.append("# TYPE app_inflight_requests gauge")
    lines.append('app_inflight_requests{service="%s"} %d' % (esc(t), random.randrange(3, 24)))
    lines.append("")

    lines.append("# HELP http_requests_total 按接口与状态码统计的请求数（counter）")
    lines.append("# TYPE http_requests_total counter")
    for (path, status), v in sorted(state.counts.items()):
        lines.append(
            'http_requests_total{service="%s",path="%s",status="%s"} %d'
            % (esc(t), esc(path), esc(status), v)
        )
    lines.append("")

    lines.append("# HELP http_request_duration_seconds 请求延迟直方图")
    lines.append("# TYPE http_request_duration_seconds histogram")
    for path in sorted({p for p, _ in state.counts}):
        counts = state.hist[path]
        cum = 0
        for i, le in enumerate(BUCKETS):
            cum += counts[i]
            lines.append(
                'http_request_duration_seconds_bucket{service="%s",path="%s",le="%g"} %d'
                % (esc(t), esc(path), le, cum)
            )
        lines.append(
            'http_request_duration_seconds_sum{service="%s",path="%s"} %.6f'
            % (esc(t), esc(path), state.hist_sum[path])
        )
        lines.append(
            'http_request_duration_seconds_count{service="%s",path="%s"} %d'
            % (esc(t), esc(path), cum)
        )
        if BUCKETS:
            lines.append(
                'http_request_duration_seconds_bucket{service="%s",path="%s",le="+Inf"} %d'
                % (esc(t), esc(path), cum)
            )
    lines.append("")

    lines.append("# HELP app_user_activity_total 按用户统计的活动次数")
    lines.append("# TYPE app_user_activity_total counter")
    if state.drop_userid:
        # 根治方案：从源头就不产出 user_id。
        # 用户维度的明细应放到日志 / 链路追踪里查，指标只保留聚合值。
        lines.append("# ℹ 已启用 --drop-userid：本指标不携带 user_id 标签")
        lines.append('app_user_activity_total{service="%s"} %d' % (esc(t), sum(state.user_counts.values())))
    else:
        lines.append("# ⚠ 高基数指标：user_id 基数 = --users，用于演示 relabel 降基数")
        for uid in sorted(state.user_counts):
            lines.append(
                'app_user_activity_total{service="%s",user_id="%s"} %d'
                % (esc(t), esc(uid), state.user_counts[uid])
            )
    lines.append("")

    lines.append("# HELP app_scrape_info 导出器元信息")
    lines.append("# TYPE app_scrape_info gauge")
    lines.append(
        'app_scrape_info{service="%s",scenario="%s",rps="%g",version="1.0"} 1'
        % (esc(t), esc(state.scenario), state.rps)
    )
    return "\n".join(lines) + "\n"


class Handler(BaseHTTPRequestHandler):
    state = None

    def do_GET(self):
        if self.path == "/metrics":
            self.state.advance()
            body = render(self.state).encode("utf-8")
            self.send_response(200)
            self.send_header("Content-Type", "text/plain; version=0.0.4; charset=utf-8")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
        elif self.path == "/healthz":
            self.send_response(200)
            self.end_headers()
            self.wfile.write(b"ok\n")
        else:
            self.send_response(404)
            self.end_headers()

    def log_message(self, fmt, *args):
        pass  # 静音访问日志，避免噪音淹没实验输出


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--tenant", required=True, choices=["tenant-a", "tenant-b"])
    ap.add_argument("--scenario", default="healthy", choices=["healthy", "degraded"])
    ap.add_argument("--port", type=int, default=9100)
    ap.add_argument("--rps", type=float, default=20.0)
    ap.add_argument("--users", type=int, default=50, help="高基数指标的 user_id 基数")
    ap.add_argument(
        "--drop-userid",
        action="store_true",
        help="不产出 user_id 标签（基数治理的「根治」方案：从源头就不产生高基数）",
    )
    args = ap.parse_args()

    Handler.state = State(
        args.tenant, args.scenario, args.rps, args.users, args.drop_userid
    )
    # 预热：先跑一轮，避免第一个抓取窗口是空数据
    Handler.state.last -= 5.0
    Handler.state.advance()

    srv = ThreadingHTTPServer(("0.0.0.0", args.port), Handler)
    print(
        "exporter ready: tenant=%s scenario=%s port=%d rps=%g users=%d"
        % (args.tenant, args.scenario, args.port, args.rps, args.users),
        flush=True,
    )
    srv.serve_forever()


if __name__ == "__main__":
    main()
