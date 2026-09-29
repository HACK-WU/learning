#!/usr/bin/env python3
"""第 15 课实验：把一次请求拆成可观察证据，再做排障决策。

实验只使用 Python 标准库，在 127.0.0.1 上启动短生命周期 HTTP 服务。
它不模拟 Chrome 的同源策略，也不需要安装 mitmproxy；15.1 的工具选择
与 15.2 的“慢 / 登录失效”推演在同一份输出里对齐。
"""

from __future__ import annotations

import argparse
import http.client
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlsplit


DEMO_TOKEN = "<DEMO_TOKEN>"


class DemoHandler(BaseHTTPRequestHandler):
    """提供重定向、延迟首字节和认证失败/成功三个可观测分支。"""

    protocol_version = "HTTP/1.0"

    def log_message(self, _format: str, *_args: object) -> None:
        # 关闭默认访问日志，让课堂输出只保留证据。
        return

    def send_bytes(
        self,
        status: int,
        body: bytes = b"",
        headers: dict[str, str] | None = None,
    ) -> None:
        self.send_response(status)
        for name, value in (headers or {}).items():
            self.send_header(name, value)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        if body:
            self.wfile.write(body)
            self.wfile.flush()

    def do_GET(self) -> None:  # noqa: N802 - 这是 BaseHTTPRequestHandler 的接口名
        path = urlsplit(self.path).path

        if path == "/redirect":
            self.send_bytes(302, headers={"Location": "/slow"})
            return

        if path == "/slow":
            # 先延迟首字节，再把正文拆成两段，分别制造 TTFB 和下载阶段证据。
            time.sleep(0.08)
            body_parts = (b"orders:", b"demo")
            body = b"".join(body_parts)
            self.send_response(200)
            self.send_header("Content-Type", "text/plain")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body_parts[0])
            self.wfile.flush()
            time.sleep(0.04)
            self.wfile.write(body_parts[1])
            self.wfile.flush()
            return

        if path == "/auth":
            if self.headers.get("Authorization") != f"Bearer {DEMO_TOKEN}":
                self.send_bytes(
                    401,
                    body=b"missing or invalid credential",
                    headers={"WWW-Authenticate": 'Bearer realm="demo-api"'},
                )
                return
            self.send_bytes(
                200,
                body=b"user=demo-user",
                headers={"Content-Type": "text/plain"},
            )
            return

        self.send_bytes(404, body=b"not found")


def request(
    host: str,
    port: int,
    path: str,
    headers: dict[str, str] | None = None,
) -> dict[str, object]:
    """测量本地请求的连接、首字节、读完正文和总耗时。"""

    started = time.perf_counter()
    connection = http.client.HTTPConnection(host, port, timeout=3)
    connect_started = time.perf_counter()
    connection.connect()
    connected = time.perf_counter()
    connection.request("GET", path, headers=headers or {})
    response = connection.getresponse()
    first_byte = time.perf_counter()
    body = response.read()
    finished = time.perf_counter()
    response_headers = {
        "location": response.getheader("Location", "<none>"),
        "www-authenticate": response.getheader("WWW-Authenticate", "<none>"),
    }
    connection.close()
    return {
        "status": response.status,
        "body": body,
        "headers": response_headers,
        "connect_ms": (connected - connect_started) * 1000,
        "ttfb_ms": (first_byte - started) * 1000,
        "body_ms": (finished - first_byte) * 1000,
        "total_ms": (finished - started) * 1000,
    }


def print_capture_lenses() -> None:
    print("[15.1] capture lenses")
    print("DevTools=浏览器真实链路|waterfall|Timing|initiator|HAR")
    print("curl=可重复客户端|请求响应头|连接与总耗时|trace")
    print("mitmproxy=客户端与服务端之间的代理观察|改写需显式授权")
    print("边界=本实验不安装或启动 mitmproxy；HTTPS 解密需要受信任的本地 CA")


def print_incident_reconstruction() -> None:
    server = ThreadingHTTPServer(("127.0.0.1", 0), DemoHandler)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    try:
        host, port = server.server_address
        print("[15.2] incident: slow")
        redirect = request(host, port, "/redirect")
        print(
            "redirect status={} location={}".format(
                redirect["status"], redirect["headers"]["location"]
            )
        )
        slow = request(host, port, "/slow")
        print(
            "slow status={} bytes={} connect-ms={:.2f} ttfb-ms={:.2f} "
            "body-drain-ms={:.2f} total-ms={:.2f}".format(
                slow["status"],
                len(slow["body"]),
                slow["connect_ms"],
                slow["ttfb_ms"],
                slow["body_ms"],
                slow["total_ms"],
            )
        )

        print("[15.2] incident: auth")
        missing = request(host, port, "/auth")
        print(
            "without-credential status={} www-authenticate={}".format(
                missing["status"], missing["headers"]["www-authenticate"]
            )
        )
        authenticated = request(
            host,
            port,
            "/auth",
            headers={"Authorization": f"Bearer {DEMO_TOKEN}"},
        )
        print(
            "with-bearer status={} body={}".format(
                authenticated["status"], authenticated["body"].decode("utf-8")
            )
        )
    finally:
        server.shutdown()
        server.server_close()
        thread.join(timeout=1)


def print_decision_checklist() -> None:
    print("[15.3] decision checklist")
    print("cache=evidence first|HTML revalidate|fingerprinted asset can immutable")
    print("protocol=measure negotiated version|compare h1.1/h2/h3|keep fallback")
    print("auth=identify credential carrier|cookie needs browser policy|token needs lifecycle")
    print("handoff=record request|response|timing|protocol|next action|rollback")


def main() -> None:
    parser = argparse.ArgumentParser(description="第 15 课抓包排障实验")
    parser.add_argument(
        "--section",
        choices=("15.1", "15.2", "15.3", "all"),
        default="all",
        help="选择课堂实验段落，默认运行全部段落",
    )
    args = parser.parse_args()

    if args.section in ("15.1", "all"):
        print_capture_lenses()
    if args.section in ("15.2", "all"):
        print_incident_reconstruction()
    if args.section in ("15.3", "all"):
        print_decision_checklist()


if __name__ == "__main__":
    main()
