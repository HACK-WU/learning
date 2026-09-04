"""带 OTel 上下文传播的下游 HTTP 客户端。

关键点：trace 上下文靠 HTTP header（traceparent）跨服务传递，
这是课 2 的「trace_id 这把钥匙」。没有它，各服务就是三段孤岛。
"""
import os

import requests

from opentelemetry.propagate import inject


def call_downstream(url, payload, timeout=30):
    """调用下游服务并注入 trace 上下文。"""
    headers = {"Content-Type": "application/json"}
    inject(headers)  # 写入 traceparent
    resp = requests.post(url, json=payload, headers=headers, timeout=timeout)
    resp.raise_for_status()
    return resp.json()


def downstream_url(service, path):
    """从环境变量解析下游地址，默认走本机 4 服务端口。"""
    default = {
        "payment": "http://127.0.0.1:5061",
        "risk-control": "http://127.0.0.1:5062",
        "user-profile": "http://127.0.0.1:5063",
    }[service]
    return os.getenv("CAP_URL_" + service.upper().replace("-", "_"), default) + path
