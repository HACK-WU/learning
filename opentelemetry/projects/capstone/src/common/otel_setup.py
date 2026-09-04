"""OTel 三信号初始化（trace / metric / log），被 4 个服务共用。

## 核心设计：不重复创建 Provider

用 `opentelemetry-instrument` 包装启动时，CLI 会**先**创建好三个 Provider，
再 import 应用代码。此时若代码里再调 `set_tracer_provider()`，会静默失败：

    Overriding of current TracerProvider is not allowed

它**不抛异常**，只是打印一行警告然后忽略。于是代码里配的 resource（
`deployment.environment.name` 等）全部丢失，而调用方毫无察觉 ——
这是本课实测到的第 1 个坑，也是最隐蔽的一个。

解决办法：先探测 Provider 是否已被创建，已存在则复用，不存在才自己建。
这样同一份代码既支持 CLI 包装运行，也支持 `python app.py` 直接运行。

## 其它按本机实测修正的导入路径（课 8 / 课 9 陷阱）
- 日志 SDK 是私有模块 `opentelemetry.sdk._logs`（公开的 `sdk.logs` 不存在）
- `OTLPLogExporter` 在 `proto.http._log_exporter`（**带下划线**，与 trace_exporter 不对称）
- Jaeger 不接受日志（`/v1/logs` 返回 404），故日志只能验证到 Collector 层
"""
import logging
import os

from opentelemetry import metrics, trace
from opentelemetry.sdk.resources import (
    DEPLOYMENT_ENVIRONMENT,
    SERVICE_NAME,
    SERVICE_VERSION,
    Resource,
)
from opentelemetry.sdk.trace import TracerProvider as SDKTracerProvider
from opentelemetry.sdk.metrics import MeterProvider as SDKMeterProvider
from opentelemetry.sdk._logs import (
    LoggerProvider as SDKLoggerProvider,
    LoggingHandler,
)
from opentelemetry.sdk.trace.export import BatchSpanProcessor
from opentelemetry.sdk.metrics.export import PeriodicExportingMetricReader
from opentelemetry.sdk._logs.export import BatchLogRecordProcessor
from opentelemetry.exporter.otlp.proto.http.trace_exporter import OTLPSpanExporter
from opentelemetry.exporter.otlp.proto.http.metric_exporter import OTLPMetricExporter
from opentelemetry.exporter.otlp.proto.http._log_exporter import OTLPLogExporter


def _http_endpoint():
    """Collector 的 OTLP/HTTP 端点。

    统一走 HTTP 而非 gRPC：Python SDK 自动插桩下 gRPC 与 HTTP 的端点写法
    不一致（gRPC 不带 scheme），混用极易踩坑（课 6 陷阱①）。
    """
    return os.getenv("OTEL_EXPORTER_OTLP_ENDPOINT", "http://127.0.0.1:46318")


def _own_providers(service_name, service_version):
    """自行创建三个 Provider（未被 CLI 包装时的分支）。"""
    res = Resource.create(
        {
            SERVICE_NAME: service_name,
            SERVICE_VERSION: service_version,
            DEPLOYMENT_ENVIRONMENT: os.getenv("DEPLOY_ENV", "capstone-lab"),
            "service.namespace": "capstone",
        }
    )
    ep = _http_endpoint()

    tp = SDKTracerProvider(resource=res)
    tp.add_span_processor(BatchSpanProcessor(OTLPSpanExporter(endpoint=ep)))

    mp = SDKMeterProvider(
        resource=res,
        metric_readers=[
            PeriodicExportingMetricReader(
                OTLPMetricExporter(endpoint=ep), export_interval_millis=5000
            )
        ],
    )

    lp = SDKLoggerProvider(resource=res)
    lp.add_log_record_processor(
        BatchLogRecordProcessor(OTLPLogExporter(endpoint=ep + "/v1/logs"))
    )
    return tp, mp, lp


def setup_otel(service_name, service_version="1.0.0"):
    """初始化三信号，返回 (tracer, meter, logger)。

    service_name 用于两处：
    1. 自建 Provider 时作为 resource 的 service.name
    2. 始终作为 instrumentation scope 名（tracer/meter 的逻辑名）
    """
    auto = isinstance(trace.get_tracer_provider(), SDKTracerProvider)

    if auto:
        # 已被 opentelemetry-instrument 配置好，直接复用，绝不重复 set
        tp = trace.get_tracer_provider()
        mp = metrics.get_meter_provider()
        lp = None  # 日志 Handler 仍需挂载，见下
        mode = "reuse(auto-instrument)"
    else:
        tp, mp, lp = _own_providers(service_name, service_version)
        trace.set_tracer_provider(tp)
        metrics.set_meter_provider(mp)
        mode = "own"

    # 日志：无论哪种模式都要挂 Handler，否则 logger.info 不会变成 OTLP log record。
    #
    # 坑：opentelemetry.sdk._logs 只有 LoggerProvider，没有 get_logger_provider()
    # （顶层 opentelemetry.logs 在本机 1.44.0 下根本不存在）。所以复用模式下
    # 拿不到 CLI 建的 LoggerProvider 句柄，只能自己建一个 —— 日志的 resource
    # 因此可能与 trace 略有差异，这是本机 SDK 版本的限制，已在注释中标明。
    if lp is None:
        lp = SDKLoggerProvider(
            resource=Resource.create(
                {SERVICE_NAME: service_name, SERVICE_VERSION: service_version}
            )
        )
        lp.add_log_record_processor(
            BatchLogRecordProcessor(
                OTLPLogExporter(endpoint=_http_endpoint() + "/v1/logs")
            )
        )
        mode += " +own-logger"

    if not getattr(lp, "_capstone_handler_added", False):
        handler = LoggingHandler(logger_provider=lp)
        logging.getLogger().addHandler(handler)
        logging.getLogger().setLevel(logging.INFO)
        lp._capstone_handler_added = True

    logging.getLogger(service_name).info(
        "service started mode=%s service=%s", mode, service_name
    )

    return (
        trace.get_tracer(service_name, service_version),
        metrics.get_meter(service_name, service_version),
        logging.getLogger(service_name),
    )
