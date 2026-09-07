#!/usr/bin/env python3
"""order-service —— 结课项目里的应用服务。

这个应用被刻意做得极小，因为结课项目的重点**不在这里**，
而在它周围的工程化：镜像怎么构建、数据怎么存、服务怎么互相找到、
上线后怎么管、出问题怎么回滚。

代码里每一处注释都标了它对应本课程的哪一课。
"""

import os
import signal
import sys
import time

from flask import Flask, jsonify

app = Flask(__name__)

# 课 5：配置一律从环境变量读，不写死在镜像里。
#       同一份镜像才能同时跑在 开发 / 测试 / 生产。
DB_HOST = os.environ.get("DB_HOST", "localhost")
REDIS_HOST = os.environ.get("REDIS_HOST", "localhost")
PORT = int(os.environ.get("PORT", "8000"))

_started_at = time.time()


@app.get("/")
def index():
    return jsonify(service="order-service", db=DB_HOST, redis=REDIS_HOST)


@app.get("/healthz")
def healthz():
    """课 9 / 课 11：健康检查端点。

    编排系统靠它判断「服务能不能用」，而不只是「进程在不在」。
    没有它，`docker ps` 只会一直显示 Up —— 哪怕服务早就不可用了。
    """
    return jsonify(status="ok", uptime=round(time.time() - _started_at, 1))


def _handle_term(signum, _frame):
    """课 10：优雅停止。

    收到 SIGTERM 后做清理再主动退出；否则 `docker stop` 会干等 10 秒然后 SIGKILL，
    正在处理的请求会被打断。

    ⚠️ 前提有两个（缺一不可）：
      1. Dockerfile 用 **exec 形式** 的 ENTRYPOINT（课 5），这样应用自己是 PID 1；
      2. 应用**自己注册**信号处理器 —— 因为 Linux 会让 PID 1 忽略「默认动作」的信号，
         不注册就收不到。
      3. 容器**不加 `--init`** 时尤其需要；加了 tini 它会帮忙转发，但本课程的建议是
         能自己处理就自己处理。
    """
    app.logger.info("收到信号 %s，开始清理并退出", signum)
    sys.exit(0)


if __name__ == "__main__":
    signal.signal(signal.SIGTERM, _handle_term)
    signal.signal(signal.SIGINT, _handle_term)
    # host=0.0.0.0 是必须的：只监听 127.0.0.1 的话，容器外永远访问不到（课 8）
    app.run(host="0.0.0.0", port=PORT)
