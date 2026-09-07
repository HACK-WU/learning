# 实战项目「从告警到定位」的被监控应用
# 同时产出：Prometheus 指标（含 exemplar）+ JSON 日志 + OTLP 链路
# 基础镜像沿用本机已有的 python:3.12-slim（不新拉镜像）
FROM python:3.12-slim

WORKDIR /app

# 依赖钉版本，保证可复现
RUN pip install --no-cache-dir \
    prometheus_client==0.21.1 \
    opentelemetry-sdk==1.29.0 \
    opentelemetry-api==1.29.0 \
    opentelemetry-exporter-otlp-proto-http==1.29.0

COPY mock_shop.py /app/mock_shop.py
COPY loki_push.py /app/loki_push.py

# 日志目录（宿主机可挂载，供 Promtail 采集）
RUN mkdir -p /var/log/shop

ENV METRICS_PORT=9400 \
    APP_PORT=9401 \
    LOG_FILE=/var/log/shop/app.log \
    OTLP_ENDPOINT=http://grafana-jaeger:4318/v1/traces \
    SERVICE_NAME=shop-api \
    FAULT_MODE=0

EXPOSE 9400 9401

# 用 -u 让日志无缓冲，保证 Promtail 能及时读到
CMD ["python", "-u", "/app/mock_shop.py"]
