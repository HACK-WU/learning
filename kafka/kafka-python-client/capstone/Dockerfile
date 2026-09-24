# 课 13 结课实战镜像
#
# 与 assets/bench/Dockerfile 同源：python:3.12-slim + 官方 uv 二进制。
# 差异：这里的依赖是 fastapi / uvicorn / confluent-kafka，均已在国内镜像可用。

FROM python:3.12-slim

COPY --from=ghcr.io/astral-sh/uv:latest /uv /uvx /bin/

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        libsasl2-2 curl \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# 先复制依赖声明，最大化构建缓存
COPY pyproject.toml ./
RUN uv venv /app/.venv \
    && VIRTUAL_ENV=/app/.venv uv pip install -r pyproject.toml

COPY app/ /app/app/
COPY tests/ /app/tests/

ENV VIRTUAL_ENV=/app/.venv
ENV PATH="/app/.venv/bin:$PATH"
ENV PYTHONPATH=/app
ENV PYTHONUNBUFFERED=1

EXPOSE 8000

CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"]
