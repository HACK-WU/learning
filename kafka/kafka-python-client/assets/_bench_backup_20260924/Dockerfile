# Kafka Python 客户端子教程 —— 基准环境镜像
#
# 设计要点：
#   1. 必须跑在 stage6-observability_kafka-net 网络里
#      原因：broker 的 advertised.listeners 是容器名 kafka-1:9092，
#            宿主机直连 19192 会拿到不可达地址（课 15 实测过的坑）
#   2. 用官方 slim 镜像 + 官方 uv 镜像中的 uv 二进制
#   3. 预装 librdkafka 编译/运行依赖（confluent-kafka wheel 需要 libsasl2）

FROM python:3.12-slim

COPY --from=ghcr.io/astral-sh/uv:latest /uv /uvx /bin/

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        libsasl2-2 \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# 先只复制依赖声明，最大化构建缓存命中
COPY pyproject.toml ./
RUN uv venv /app/.venv \
    && VIRTUAL_ENV=/app/.venv uv pip install -r pyproject.toml

ENV VIRTUAL_ENV=/app/.venv
ENV PATH="/app/.venv/bin:$PATH"

CMD ["sleep", "infinity"]
