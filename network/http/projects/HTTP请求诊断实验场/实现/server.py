#!/usr/bin/env python3
"""HTTP 请求诊断实验场的本地服务。

只绑定 127.0.0.1，不依赖第三方包，不访问外部网络。每个路由故意制造一个
可观察的 HTTP 现象，供客户端、curl 和 DevTools 对照排障。
"""

from __future__ import annotations

import argparse
import json
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from typing import Dict, Optional, Tuple
from urllib.parse import parse_qs, urlsplit


DEMO_TOKEN = "<DEMO_TOKEN>"
ALLOWED_ORIGIN = "http://localhost:5173"
ORDERS_ETAG = '"orders-demo-v1"'


def json_bytes(payload: object) -> bytes:
    return (json.dumps(payload, ensure_ascii=False, separators=(",", ":")) + "\n").encode(
        "utf-8"
    )


class DiagnosticHandler(BaseHTTPRequestHandler):
    """提供慢请求、重定向、认证、CORS 和缓存分支。"""

    protocol_version = "HTTP/1.1"

    def log_message(self, _format: str, *_args: object) -> None:
        # 默认访问日志会干扰证据输出；真实服务应交给结构化日志系统。
        return

    def send_bytes(
        self,
        status: int,
        body: bytes = b"",
        headers: Optional[Dict[str, str]] = None,
    ) -> None:
        self.send_response(status)
        for name, value in (headers or {}).items():
            self.send_header(name, value)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        if body:
            self.wfile.write(body)
            self.wfile.flush()

    def cors_headers(self) -> dict[str, str]:
        """只对明确允许的来源回显来源，避免把凭证接口写成通配符。"""

        origin = self.headers.get("Origin")
        if origin != ALLOWED_ORIGIN:
            return {}
        return {
            "Access-Control-Allow-Origin": origin,
            "Access-Control-Allow-Credentials": "true",
            "Vary": "Origin",
        }

    def do_OPTIONS(self) -> None:  # noqa: N802 - BaseHTTPRequestHandler 接口名
        path = urlsplit(self.path).path
        if path != "/api/orders":
            self.send_bytes(404, b"not found\n")
            return

        origin = self.headers.get("Origin", "")
        requested_method = self.headers.get("Access-Control-Request-Method", "").upper()
        requested_headers = {
            item.strip().lower()
            for item in self.headers.get("Access-Control-Request-Headers", "").split(",")
            if item.strip()
        }
        allowed_headers = {"authorization", "content-type"}
        if (
            origin != ALLOWED_ORIGIN
            or requested_method not in {"GET", "POST"}
            or not requested_headers <= allowed_headers
        ):
            self.send_bytes(403, b"preflight denied\n")
            return

        headers = {
            **self.cors_headers(),
            "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
            "Access-Control-Allow-Headers": "Authorization, Content-Type",
            "Access-Control-Max-Age": "60",
        }
        self.send_bytes(204, headers=headers)

    def do_GET(self) -> None:  # noqa: N802 - BaseHTTPRequestHandler 接口名
        split = urlsplit(self.path)
        path = split.path
        query = parse_qs(split.query)

        if path == "/":
            body = b"<html><body>HTTP diagnostic lab</body></html>\n"
            self.send_bytes(
                200,
                body,
                headers={"Content-Type": "text/html; charset=utf-8", "Cache-Control": "no-cache"},
            )
            return

        if path == "/api/redirect":
            self.send_bytes(
                302,
                headers={
                    "Location": "/api/orders?source=redirect",
                    "Cache-Control": "no-store",
                },
            )
            return

        if path == "/api/slow":
            # 80ms 让首字节变慢，40ms 把正文分成两段，分别制造 TTFB / 下载证据。
            header_delay_ms = int(query.get("header_delay_ms", ["80"])[0])
            body_delay_ms = int(query.get("body_delay_ms", ["40"])[0])
            time.sleep(header_delay_ms / 1000)
            first = b'{"ok":true,"part":"first"}'
            second = b'{"part":"second"}\n'
            body = first + second
            self.send_response(200)
            self.send_header("Content-Type", "application/json; charset=utf-8")
            self.send_header("Cache-Control", "no-store")
            self.send_header(
                "Server-Timing",
                f"app;dur={header_delay_ms}, body;dur={body_delay_ms}",
            )
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(first)
            self.wfile.flush()
            time.sleep(body_delay_ms / 1000)
            self.wfile.write(second)
            self.wfile.flush()
            return

        if path == "/api/auth":
            authorization = self.headers.get("Authorization", "")
            if not authorization:
                self.send_bytes(
                    401,
                    b"missing credential\n",
                    headers={"WWW-Authenticate": 'Bearer realm="diagnostic-lab"'},
                )
                return
            if authorization != f"Bearer {DEMO_TOKEN}":
                self.send_bytes(403, b"credential rejected\n")
                return
            self.send_bytes(
                200,
                json_bytes({"user": "demo-user", "scope": ["orders:read"]}),
                headers={"Content-Type": "application/json; charset=utf-8"},
            )
            return

        if path == "/api/orders":
            if self.headers.get("If-None-Match") == ORDERS_ETAG:
                self.send_bytes(
                    304,
                    headers={**self.cors_headers(), "ETag": ORDERS_ETAG, "Cache-Control": "no-cache"},
                )
                return
            body = json_bytes({"items": [{"id": "demo-001", "status": "ready"}]})
            self.send_bytes(
                200,
                body,
                headers={
                    **self.cors_headers(),
                    "Content-Type": "application/json; charset=utf-8",
                    "Cache-Control": "no-cache",
                    "ETag": ORDERS_ETAG,
                },
            )
            return

        if path == "/static/app.abc123.js":
            self.send_bytes(
                200,
                b"console.log('fingerprinted asset');\n",
                headers={
                    "Content-Type": "text/javascript; charset=utf-8",
                    "Cache-Control": "public, max-age=31536000, immutable",
                },
            )
            return

        self.send_bytes(404, b"not found\n")

    def do_POST(self) -> None:  # noqa: N802 - BaseHTTPRequestHandler 接口名
        """预检通过后的真实订单请求：把 CORS 与认证结果放回同一条链路。"""

        path = urlsplit(self.path).path
        if path != "/api/orders":
            self.send_bytes(404, b"not found\n")
            return

        content_length = int(self.headers.get("Content-Length", "0"))
        self.rfile.read(content_length)
        authorization = self.headers.get("Authorization", "")
        if authorization != f"Bearer {DEMO_TOKEN}":
            self.send_bytes(
                401,
                b"missing or invalid credential\n",
                headers={
                    **self.cors_headers(),
                    "WWW-Authenticate": 'Bearer realm="diagnostic-lab"',
                },
            )
            return

        self.send_bytes(
            201,
            json_bytes({"created": True, "order_id": "demo-002"}),
            headers={
                **self.cors_headers(),
                "Content-Type": "application/json; charset=utf-8",
                "Cache-Control": "no-store",
            },
        )


def start_server(port: int = 0) -> Tuple[ThreadingHTTPServer, threading.Thread]:
    """启动短生命周期本地服务，返回服务和后台线程。"""

    server = ThreadingHTTPServer(("127.0.0.1", port), DiagnosticHandler)
    thread = threading.Thread(target=server.serve_forever, name="http-diagnostic-server")
    thread.start()
    return server, thread


def main() -> None:
    parser = argparse.ArgumentParser(description="启动 HTTP 请求诊断实验场")
    parser.add_argument("--port", type=int, default=8765, help="监听端口，0 表示随机端口")
    args = parser.parse_args()

    server, thread = start_server(args.port)
    host, port = server.server_address
    print(f"listening=http://{host}:{port}", flush=True)
    try:
        while True:
            time.sleep(1)
    except KeyboardInterrupt:
        print("stopping=ok")
    finally:
        server.shutdown()
        server.server_close()
        thread.join(timeout=1)


if __name__ == "__main__":
    main()
