#!/usr/bin/env python3
"""第 13 课实验：观察 Cookie、Session/Token 与认证头的最小闭环。

只使用 Python 标准库，在 127.0.0.1 的临时端口启动服务；不访问外网，
不生成真实凭证。它演示的是 HTTP 报文机制，不是生产认证实现。
"""

from __future__ import annotations

import argparse
import threading
from http.cookiejar import CookieJar
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.error import HTTPError
from urllib.request import HTTPCookieProcessor, Request, build_opener


SESSION_STORE = {
    "sid-demo-01": {"user": "demo-user", "scope": "orders:read"},
}
DEMO_BEARER = "demo-access-token"


class DemoHandler(BaseHTTPRequestHandler):
    """把三种观测压缩到几个不会产生副作用的 GET 端点。"""

    protocol_version = "HTTP/1.1"

    def log_message(self, *_args: object) -> None:
        # 实验输出保持稳定，避免把请求头误当成日志样例。
        return

    def reply(self, status: int, body: str, **headers: str) -> None:
        payload = body.encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "text/plain; charset=utf-8")
        self.send_header("Content-Length", str(len(payload)))
        for name, value in headers.items():
            self.send_header(name.replace("_", "-"), value)
        self.end_headers()
        self.wfile.write(payload)

    def do_GET(self) -> None:  # noqa: N802 - BaseHTTPRequestHandler 的固定接口名
        if self.path == "/login":
            self.reply(
                200,
                "logged-in",
                Set_Cookie="sid=sid-demo-01; Path=/; HttpOnly; SameSite=Lax",
            )
            return

        if self.path == "/me":
            cookie = self.headers.get("Cookie", "")
            authorization = self.headers.get("Authorization", "")
            cookie_ok = "sid=sid-demo-01" in cookie and "sid-demo-01" in SESSION_STORE
            bearer_ok = authorization == f"Bearer {DEMO_BEARER}"
            if cookie_ok or bearer_ok:
                self.reply(200, "user=demo-user")
            else:
                self.reply(401, "missing session", WWW_Authenticate='Bearer realm="demo-api"')
            return

        if self.path == "/token-me":
            authorization = self.headers.get("Authorization", "")
            if authorization == f"Bearer {DEMO_BEARER}":
                self.reply(200, "scope=orders:read")
            else:
                self.reply(401, "missing bearer", WWW_Authenticate='Bearer realm="demo-api"')
            return

        self.reply(404, "not found")


def status_and_body(opener, request: Request | str) -> tuple[int, str, dict[str, str]]:
    """返回状态、正文和少量响应头；把 4xx 也作为可观察结果保留。"""

    try:
        with opener.open(request) as response:
            return response.status, response.read().decode("utf-8"), {
                name.lower(): value for name, value in response.headers.items()
            }
    except HTTPError as error:
        return error.code, error.read().decode("utf-8"), {
            name.lower(): value for name, value in error.headers.items()
        }


def start_server() -> tuple[ThreadingHTTPServer, threading.Thread, str]:
    server = ThreadingHTTPServer(("127.0.0.1", 0), DemoHandler)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    return server, thread, f"http://127.0.0.1:{server.server_port}"


def run_cookie(base_url: str) -> None:
    print("[13.1] Cookie round trip")
    jar = CookieJar()
    opener = build_opener(HTTPCookieProcessor(jar))
    status, _body, headers = status_and_body(opener, f"{base_url}/login")
    print(f"login status={status}")
    print(f"set-cookie={headers.get('set-cookie', '<none>')}")
    status, body, _headers = status_and_body(opener, f"{base_url}/me")
    print(f"me with cookie status={status} body={body}")
    status, _body, _headers = status_and_body(build_opener(), f"{base_url}/me")
    print(f"me without cookie status={status}")
    print()


def run_state_model() -> None:
    print("[13.2] State ownership")
    session = SESSION_STORE["sid-demo-01"]
    print(f"session lookup: sid-demo-01 -> user={session['user']}")
    print("token verification model: claims=sub:user-001,scope:orders:read -> valid")
    print("logout session: delete sid-demo-01 -> next request invalid")
    print("logout token: revoke or wait for expiry -> extra policy/state required")
    print()


def run_authorization(base_url: str) -> None:
    print("[13.3] Authorization header")
    opener = build_opener()
    status, _body, headers = status_and_body(opener, f"{base_url}/token-me")
    print(f"no authorization status={status}")
    print(f"www-authenticate={headers.get('www-authenticate', '<none>')}")
    request = Request(
        f"{base_url}/token-me",
        headers={"Authorization": f"Bearer {DEMO_BEARER}"},
    )
    status, body, _headers = status_and_body(opener, request)
    print(f"bearer authorization status={status} body={body}")


def main() -> None:
    parser = argparse.ArgumentParser(description="第 13 课 Cookie / Session / Token 机制实验")
    parser.add_argument("--section", choices=("13.1", "13.2", "13.3", "all"), default="all")
    args = parser.parse_args()

    server, thread, base_url = start_server()
    try:
        if args.section in ("13.1", "all"):
            run_cookie(base_url)
        if args.section in ("13.2", "all"):
            run_state_model()
        if args.section in ("13.3", "all"):
            run_authorization(base_url)
    finally:
        server.shutdown()
        server.server_close()
        thread.join(timeout=2)


if __name__ == "__main__":
    main()
