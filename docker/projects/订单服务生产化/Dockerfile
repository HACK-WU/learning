# syntax=docker/dockerfile:1

# ============================ 阶段 1：构建 ============================
# 课 6：多阶段构建 —— 构建期的东西（编译器、pip 缓存、临时文件）统统不进最终镜像
FROM python:3.12-slim AS builder

WORKDIR /build

# 课 4：先只拷依赖清单。requirements.txt 不变时，下面这层直接命中缓存，
#       改代码不会触发重装依赖。
COPY app/requirements.txt .

RUN python -m venv /opt/venv \
 && /opt/venv/bin/pip install --no-cache-dir -r requirements.txt

# ============================ 阶段 2：运行时 ============================
FROM python:3.12-slim AS runtime

# 课 12：建一个专用用户。
#       官方原话：防止提权攻击的 "best way" 就是让应用以非 root 用户运行。
RUN groupadd --system app \
 && useradd --system --gid app --create-home --home-dir /home/app app

# 只把「构建产物」搬过来 —— 这就是多阶段构建省体积的原理（课 6）
COPY --from=builder /opt/venv /opt/venv
ENV PATH="/opt/venv/bin:${PATH}"

WORKDIR /app
# 课 4：代码放在最后拷 —— 变化最频繁的层放最下面，上面的缓存才不会白费
COPY app/app.py .

# 课 12：降权。放在 **最后**（在所有需要 root 的 RUN 之后），避免前面的指令因权限失败。
USER app

# 课 8：EXPOSE 只是写给人的文档，它 **不会** 发布端口；
#       真正开门的是 compose 里的 `ports`，或 `docker run -p`。
EXPOSE 8000

# 课 9 / 课 11：健康检查。
#       用标准库 urllib，镜像里就不必额外装 curl（也是课 6 「瘦身」的一部分）。
#       start-period 给应用留启动时间，避免刚起来就被判 unhealthy。
HEALTHCHECK --interval=5s --timeout=3s --start-period=10s --retries=3 \
  CMD python -c "import sys,urllib.request; \
      sys.exit(0 if urllib.request.urlopen('http://127.0.0.1:8000/healthz').status == 200 else 1)"

# 课 5：用 **exec 形式**（JSON 数组）。
#       写成 `ENTRYPOINT python app.py` 的话，/bin/sh 会成为 PID 1 且 **不转发信号**，
#       应用就收不到 SIGTERM，`docker stop` 每次都要等满 10 秒（课 5 + 课 10）。
ENTRYPOINT ["python", "app.py"]
