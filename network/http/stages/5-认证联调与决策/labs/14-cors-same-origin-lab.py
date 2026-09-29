#!/usr/bin/env python3
"""第 14 课实验：验证源比较、CORS 预检合同和错误定位模型。

本实验使用 Python 标准库，不模拟浏览器的同源策略；它验证的是服务端
返回的 CORS 头是否与请求条件匹配。真正的页面读取结果仍需浏览器验证。
"""

from __future__ import annotations

import argparse
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.error import HTTPError
from urllib.parse import urlsplit
from urllib.request import Request, urlopen


APP_ORIGIN = "https://app.example.com"
ALLOWED_ORIGINS = {APP_ORIGIN}
ALLOWED_METHODS = {"POST"}
ALLOWED_HEADERS = {"authorization", "content-type"}


def origin_tuple(url: str) -> tuple[str, str, int | None]:
    parsed = urlsplit(url)
    if parsed.port is not None:
        port = parsed.port
    elif parsed.scheme == "https":
        port = 443
    elif parsed.scheme == "http":
        port = 80
    else:
        port = None
    return parsed.scheme, parsed.hostname or "", port


def same_origin(left: str, right: str) -> bool:
    return origin_tuple(left) == origin_tuple(right)


class CorsHandler(BaseHTTPRequestHandler):
    """只实现本课需要的 OPTIONS / POST 合同。"""

    protocol_version = "HTTP/1.0"

    def log_message(self, _format: str, *_args: object) -> None:
        # 保持实验输出稳定，把 HTTPServer 默认访问日志收起来。
        return

    def send_bytes(self, status: int, body: bytes = b"", headers: dict[str, str] | None = None) -> None:
        self.send_response(status)
        for name, value in (headers or {}).items():
            self.send_header(name, value)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        if body:
            self.wfile.write(body)

    def cors_headers(self, origin: str) -> dict[str, str]:
        if origin not in ALLOWED_ORIGINS:
            return {}
        return {
            "Access-Control-Allow-Origin": origin,
            "Access-Control-Allow-Methods": "POST, OPTIONS",
            "Access-Control-Allow-Headers": "authorization, content-type",
            "Access-Control-Allow-Credentials": "true",
            "Access-Control-Expose-Headers": "X-Request-Id",
            "Access-Control-Max-Age": "60",
            "Vary": "Origin",
        }

    def do_OPTIONS(self) -> None:
        origin = self.headers.get("Origin", "")
        requested_method = self.headers.get("Access-Control-Request-Method", "").upper()
        requested_headers = {
            item.strip().lower()
            for item in self.headers.get("Access-Control-Request-Headers", "").split(",")
            if item.strip()
        }
        allowed = (
            origin in ALLOWED_ORIGINS
            and requested_method in ALLOWED_METHODS
            and requested_headers <= ALLOWED_HEADERS
        )
        if allowed:
            self.send_bytes(204, headers=self.cors_headers(origin))
        else:
            # 失败时不返回 Allow-Origin，模拟浏览器无法通过 CORS 检查的结果。
            self.send_bytes(403, body=b"preflight denied")

    def do_POST(self) -> None:
        if self.path != "/orders":
            self.send_bytes(404, body=b"not found")
            return
        body_length = int(self.headers.get("Content-Length", "0"))
        self.rfile.read(body_length)
        origin = self.headers.get("Origin", "")
        body = b'{"order_id":"demo-001"}'
        headers = self.cors_headers(origin)
        headers["Content-Type"] = "application/json"
        headers["X-Request-Id"] = "req-demo-001"
        self.send_bytes(200, body=body, headers=headers)


def request_response(request: Request) -> tuple[int, object]:
    try:
        with urlopen(request, timeout=3) as response:
            return response.status, response.headers
    except HTTPError as error:
        return error.code, error.headers


def header(headers: object, name: str) -> str:
    value = headers.get(name) if hasattr(headers, "get") else None
    return value if value is not None else "<none>"


def run_origin_section() -> None:
    print("[14.1] Origin tuple")
    page = "http://localhost:5173/index.html"
    same_host_path = "http://localhost:5173/orders"
    different_port = "http://localhost:8000/orders"
    different_scheme = "https://localhost:5173/orders"
    print(
        "same path-only change: "
        + ("same-origin" if same_origin(page, same_host_path) else "cross-origin")
    )
    print(
        "different port: "
        + ("same-origin" if same_origin(page, different_port) else "cross-origin")
    )
    print(
        "different scheme: "
        + ("same-origin" if same_origin(page, different_scheme) else "cross-origin")
    )


def run_contract_section() -> None:
    server = ThreadingHTTPServer(("127.0.0.1", 0), CorsHandler)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    base_url = f"http://127.0.0.1:{server.server_port}"
    try:
        print("[14.2] Preflight contract")
        preflight = Request(
            f"{base_url}/orders",
            method="OPTIONS",
            headers={
                "Origin": APP_ORIGIN,
                "Access-Control-Request-Method": "POST",
                "Access-Control-Request-Headers": "authorization, content-type",
            },
        )
        status, headers = request_response(preflight)
        print(f"allowed preflight status={status}")
        print(f"allow-origin={header(headers, 'Access-Control-Allow-Origin')}")
        print(f"allow-methods={header(headers, 'Access-Control-Allow-Methods')}")
        print(f"allow-headers={header(headers, 'Access-Control-Allow-Headers')}")

        actual = Request(
            f"{base_url}/orders",
            data=b"{\"item_id\":\"demo-001\"}",
            method="POST",
            headers={
                "Origin": APP_ORIGIN,
                "Authorization": "Bearer demo-token",
                "Content-Type": "application/json",
            },
        )
        actual_status, actual_headers = request_response(actual)
        print(
            "actual response "
            f"status={actual_status} "
            f"allow-origin={header(actual_headers, 'Access-Control-Allow-Origin')}"
        )

        denied = Request(
            f"{base_url}/orders",
            method="OPTIONS",
            headers={
                "Origin": "https://evil.example.com",
                "Access-Control-Request-Method": "POST",
                "Access-Control-Request-Headers": "authorization, content-type",
            },
        )
        denied_status, denied_headers = request_response(denied)
        print(
            "denied preflight "
            f"status={denied_status} "
            f"allow-origin={header(denied_headers, 'Access-Control-Allow-Origin')}"
        )
    finally:
        server.shutdown()
        server.server_close()
        thread.join(timeout=1)


def run_diagnosis_section() -> None:
    print("[14.3] Diagnosis model")
    print("missing allow-origin -> inspect actual response and error path")
    print("wildcard with credentials -> replace * with exact origin")
    print("method not allowed -> compare requested method with allow-methods")


def main() -> None:
    parser = argparse.ArgumentParser(description="第 14 课 CORS 机制实验")
    parser.add_argument(
        "--section",
        choices=("14.1", "14.2", "14.3", "all"),
        default="all",
        help="选择要运行的实验段落",
    )
    args = parser.parse_args()

    if args.section in {"14.1", "all"}:
        run_origin_section()
        if args.section == "all":
            print()
    if args.section in {"14.2", "all"}:
        run_contract_section()
        if args.section == "all":
            print()
    if args.section in {"14.3", "all"}:
        run_diagnosis_section()


if __name__ == "__main__":
    main()
