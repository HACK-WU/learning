#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
实战项目「从告警到定位」的被监控对象：一个三层电商服务。

对外暴露：
  - :9400/metrics   Prometheus 指标（含 histogram + exemplar）
  - :9401/health    健康检查
  - 日志文件 logs/app.log，每行一个 JSON（供 Promtail 采集进 Loki）
  - 通过 OTLP/HTTP 上报 trace 到 Jaeger

为什么自己写而不是用现成镜像：
  现成的 demo 应用通常只有指标或只有链路，无法演示「指标 → 日志 → 链路」三级下钻。
  三级下钻要求同一个 trace_id 同时出现在【日志行】和【指标 exemplar】里，必须自己造。

运行：python3 mock_shop.py
依赖：opentelemetry-sdk / opentelemetry-exporter-otlp-proto-http / prometheus_client
"""
import json
import logging
import os
import random
import signal
import sys
import threading
import time
from http.server import BaseHTTPRequestHandler, HTTPServer

from opentelemetry import trace
from opentelemetry.exporter.otlp.proto.http.trace_exporter import OTLPSpanExporter
from opentelemetry.sdk.resources import Resource
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import BatchSpanProcessor
from opentelemetry.trace import format_trace_id
from prometheus_client import Counter, Gauge, Histogram, start_http_server

# 日志推送到 Loki（绕开 Promtail，原因见 loki_push.py 头部注释）
import loki_push  # noqa: E402

# ---------------------------------------------------------------- 配置
SERVICE_NAME = os.getenv("SERVICE_NAME", "shop-api")
OTLP_ENDPOINT = os.getenv("OTLP_ENDPOINT", "http://localhost:44318/v1/traces")
METRICS_PORT = int(os.getenv("METRICS_PORT", "9400"))
APP_PORT = int(os.getenv("APP_PORT", "9401"))
LOG_FILE = os.getenv("LOG_FILE", "/var/log/shop/app.log")
# 故障注入：设为 1 时让 /checkout 固定变慢且报错，用来触发告警
FAULT_MODE = os.getenv("FAULT_MODE", "0") == "1"

# ---------------------------------------------------------------- 链路
resource = Resource.create({"service.name": SERVICE_NAME})
provider = TracerProvider(resource=resource)
provider.add_span_processor(BatchSpanProcessor(OTLPSpanExporter(endpoint=OTLP_ENDPOINT)))
trace.set_tracer_provider(provider)
tracer = trace.get_tracer(__name__)

# ---------------------------------------------------------------- 指标
REQUESTS = Counter(
    "shop_requests_total",
    "请求总数",
    ["service", "route", "status"],
)
INFLIGHT = Gauge("shop_inflight_requests", "当前并发请求数", ["service"])
LATENCY = Histogram(
    "shop_request_duration_seconds",
    "请求耗时（秒）",
    ["service", "route"],
    buckets=(0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1.0, 2.5, 5.0),
)
ERRORS = Counter("shop_errors_total", "错误总数", ["service", "route", "error_type"])

# ---------------------------------------------------------------- 日志
os.makedirs(os.path.dirname(LOG_FILE), exist_ok=True)
# 关键点 1：日志必须同时写 stdout（容器日志）和文件（Promtail 采集）
logger = logging.getLogger("shop")
logger.setLevel(logging.INFO)
_fmt = logging.Formatter("%(message)s")
_fh = logging.FileHandler(LOG_FILE)
_fh.setFormatter(_fmt)
logger.addHandler(_fh)
_sh = logging.StreamHandler(sys.stdout)
_sh.setFormatter(_fmt)
logger.addHandler(_sh)


def log(level, msg, **kw):
    """写一条结构化日志。trace_id / span_id 是三级下钻的锚点。"""
    span = trace.get_current_span()
    ctx = span.get_span_context()
    rec = {
        "ts": time.strftime("%Y-%m-%dT%H:%M:%S", time.gmtime()) + "Z",
        "level": level,
        "service": SERVICE_NAME,
        "msg": msg,
        # 关键点 2：只有把 trace_id 写进日志，才能从日志跳回链路
        "trace_id": format_trace_id(ctx.trace_id) if ctx.is_valid else "",
        "span_id": format(ctx.span_id, "016x") if ctx.is_valid else "",
    }
    rec.update(kw)
    line = json.dumps(rec, ensure_ascii=False)
    logger.info(line)
    # 同时推给 Loki（异步，失败不影响主流程）
    loki_push.emit(line)


# ---------------------------------------------------------------- 业务
ROUTES = ["/home", "/product", "/cart", "/checkout", "/search"]
PAYMENT = ["alipay", "wechat", "card"]


def call_downstream(route, depth):
    """模拟调用下游服务（order / payment / inventory），产生子 span。"""
    name = random.choice(["order", "payment", "inventory"])
    with tracer.start_as_current_span(f"call-{name}") as span:
        span.set_attribute("downstream", name)
        span.set_attribute("route", route)
        # 正常耗时 10~80ms
        d = random.uniform(0.01, 0.08)
        # 故障注入：checkout 的下游调用变慢 10 倍
        if FAULT_MODE and route == "/checkout":
            d = random.uniform(0.8, 1.8)
        time.sleep(d)
        span.set_attribute("duration_ms", round(d * 1000, 1))
        # 偶发下游错误
        if FAULT_MODE and route == "/checkout" and random.random() < 0.35:
            span.set_status(trace.Status(trace.StatusCode.ERROR, "downstream timeout"))
            log("ERROR", f"下游 {name} 调用超时", route=route, downstream=name,
                duration_ms=round(d * 1000, 1), error_type="DownstreamTimeout")
            raise RuntimeError(f"{name} timeout")
        log("DEBUG", f"调用下游 {name} 成功", route=route, downstream=name,
            duration_ms=round(d * 1000, 1))
        return name


def handle_request():
    """处理一个请求：产生指标 + 日志 + 链路三件套。"""
    route = random.choices(ROUTES, weights=[30, 25, 20, 10, 15])[0]
    INFLIGHT.labels(service=SERVICE_NAME).inc()
    t0 = time.time()
    status = "200"
    with tracer.start_as_current_span(f"HTTP {route}") as span:
        span.set_attribute("route", route)
        span.set_attribute("service", SERVICE_NAME)
        try:
            # 90% 的请求会调一次下游，10% 调两次（演示多子 span）
            for _ in range(1 if random.random() < 0.9 else 2):
                call_downstream(route, 1)
            # 故障注入：checkout 自身也变慢
            if FAULT_MODE and route == "/checkout":
                time.sleep(random.uniform(0.5, 1.2))
                if random.random() < 0.3:
                    raise RuntimeError("checkout failed")
            log("INFO", f"处理 {route} 成功", route=route,
                pay=random.choice(PAYMENT) if route == "/checkout" else "")
        except Exception as e:  # noqa: BLE001
            status = "500"
            span.record_exception(e)
            span.set_status(trace.Status(trace.StatusCode.ERROR, str(e)))
            ERRORS.labels(service=SERVICE_NAME, route=route,
                          error_type=type(e).__name__).inc()
            log("ERROR", f"处理 {route} 失败: {e}", route=route, error_type=type(e).__name__)
        finally:
            dur = time.time() - t0
            # 关键点 3：exemplar 必须【显式传】，prometheus_client 不会自动挂。
            # 不传的话 Prometheus 里查 exemplars 返回空，图上就没有可点的圆点，
            # 「指标 → 链路」这一跳就断了。这是本项目踩到的第二个真坑。
            ctx = span.get_span_context()
            ex = ({"trace_id": format_trace_id(ctx.trace_id)}
                  if ctx.is_valid else None)
            if ex:
                LATENCY.labels(service=SERVICE_NAME, route=route).observe(dur, exemplar=ex)
            else:
                LATENCY.labels(service=SERVICE_NAME, route=route).observe(dur)
            REQUESTS.labels(service=SERVICE_NAME, route=route, status=status).inc()
            INFLIGHT.labels(service=SERVICE_NAME).dec()
            span.set_attribute("status", status)
            span.set_attribute("duration_ms", round(dur * 1000, 1))


class HealthHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.end_headers()
        self.wfile.write(json.dumps({"status": "ok", "service": SERVICE_NAME}).encode())

    def log_message(self, fmt, *args):  # 静音默认访问日志
        pass


def main():
    start_http_server(METRICS_PORT)  # Prometheus 指标端口
    loki_push.start()  # 启动日志推送线程
    httpd = HTTPServer(("0.0.0.0", APP_PORT), HealthHandler)
    threading.Thread(target=httpd.serve_forever, daemon=True).start()
    log("INFO", f"{SERVICE_NAME} 启动：指标 :{METRICS_PORT} 健康 :{APP_PORT} "
                f"OTLP={OTLP_ENDPOINT} 故障注入={'开' if FAULT_MODE else '关'}")

    def shutdown(signum, frame):
        log("INFO", "收到退出信号")
        sys.exit(0)

    signal.signal(signal.SIGTERM, shutdown)
    signal.signal(signal.SIGINT, shutdown)

    # 持续产生流量：每 0.2~0.6 秒一个请求
    while True:
        try:
            handle_request()
        except Exception as e:  # noqa: BLE001
            log("ERROR", f"主循环异常: {e}")
        time.sleep(random.uniform(0.2, 0.6))


if __name__ == "__main__":
    main()
