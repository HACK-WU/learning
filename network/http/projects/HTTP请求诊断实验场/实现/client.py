#!/usr/bin/env python3
"""实验场客户端：把一次请求拆成连接、首字节、正文读取和总耗时。"""

from __future__ import annotations

import http.client
import time
from dataclasses import dataclass
from typing import Dict, Optional


@dataclass(frozen=True)
class RequestResult:
    method: str
    path: str
    status: int
    headers: dict[str, str]
    body: bytes
    connect_ms: float
    ttfb_ms: float
    body_ms: float
    total_ms: float


def request(
    host: str,
    port: int,
    path: str,
    *,
    method: str = "GET",
    headers: Optional[Dict[str, str]] = None,
    body: Optional[bytes] = None,
) -> RequestResult:
    """发送一次请求并记录证据；每次调用独立连接，避免隐藏连接复用状态。"""

    started = time.perf_counter()
    connection = http.client.HTTPConnection(host, port, timeout=3)
    connect_started = time.perf_counter()
    connection.connect()
    connected = time.perf_counter()
    connection.request(method, path, body=body, headers=headers or {})
    response = connection.getresponse()
    first_byte = time.perf_counter()
    response_body = response.read()
    finished = time.perf_counter()
    result = RequestResult(
        method=method,
        path=path,
        status=response.status,
        headers={name.lower(): value for name, value in response.getheaders()},
        body=response_body,
        connect_ms=(connected - connect_started) * 1000,
        ttfb_ms=(first_byte - started) * 1000,
        body_ms=(finished - first_byte) * 1000,
        total_ms=(finished - started) * 1000,
    )
    connection.close()
    return result


def evidence_line(result: RequestResult) -> str:
    """输出适合交接的单行证据，避免把正文秘密默认打印出来。"""

    return (
        f"{result.method} {result.path} -> {result.status} "
        f"connect={result.connect_ms:.2f}ms ttfb={result.ttfb_ms:.2f}ms "
        f"body={result.body_ms:.2f}ms total={result.total_ms:.2f}ms "
        f"bytes={len(result.body)}"
    )
