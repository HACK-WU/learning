#!/usr/bin/env python3
"""运行结课综合项目的四个故障病例。"""

from __future__ import annotations

import argparse
import sys

from client import evidence_line, request
from server import ALLOWED_ORIGIN, DEMO_TOKEN, start_server


def run_slow_case(host: str, port: int) -> None:
    print("[case slow] symptom=页面慢，先拆分请求阶段")
    redirect = request(host, port, "/api/redirect")
    assert redirect.status == 302
    assert redirect.headers["location"] == "/api/orders?source=redirect"
    print(" ", evidence_line(redirect), "location=", redirect.headers["location"])

    slow = request(host, port, "/api/slow")
    assert slow.status == 200
    assert slow.headers["server-timing"].startswith("app;")
    assert slow.body
    print(" ", evidence_line(slow), "server-timing=", slow.headers["server-timing"])
    print("  decision=先查重定向与 TTFB，再决定是否动压缩或协议")


def run_auth_case(host: str, port: int) -> None:
    print("[case auth] symptom=登录失效，先区分认证与授权")
    missing = request(host, port, "/api/auth")
    assert missing.status == 401
    assert missing.headers["www-authenticate"] == 'Bearer realm="diagnostic-lab"'
    print(" ", evidence_line(missing), "challenge=", missing.headers["www-authenticate"])

    wrong = request(host, port, "/api/auth", headers={"Authorization": "Bearer wrong"})
    assert wrong.status == 403
    print(" ", evidence_line(wrong), "decision=凭证已到达，但不具备权限或已失效")

    valid = request(
        host,
        port,
        "/api/auth",
        headers={"Authorization": f"Bearer {DEMO_TOKEN}"},
    )
    assert valid.status == 200
    print(" ", evidence_line(valid), "body=已隐藏，仅验证状态与长度")


def run_cors_cache_case(host: str, port: int) -> None:
    print("[case cors-cache] symptom=跨源失败或重复下载，先看预检与缓存证据")
    allowed = request(
        host,
        port,
        "/api/orders",
        method="OPTIONS",
        headers={
            "Origin": ALLOWED_ORIGIN,
            "Access-Control-Request-Method": "POST",
            "Access-Control-Request-Headers": "authorization, content-type",
        },
    )
    assert allowed.status == 204
    assert allowed.headers["access-control-allow-origin"] == ALLOWED_ORIGIN
    print(" ", evidence_line(allowed), "preflight=allowed")

    created = request(
        host,
        port,
        "/api/orders",
        method="POST",
        headers={
            "Origin": ALLOWED_ORIGIN,
            "Authorization": f"Bearer {DEMO_TOKEN}",
            "Content-Type": "application/json",
        },
        body=b'{"item_id":"demo-001"}',
    )
    assert created.status == 201
    assert created.headers["access-control-allow-origin"] == ALLOWED_ORIGIN
    print(" ", evidence_line(created), "actual=authenticated cross-origin POST")

    denied = request(
        host,
        port,
        "/api/orders",
        method="OPTIONS",
        headers={
            "Origin": "http://evil.example",
            "Access-Control-Request-Method": "POST",
            "Access-Control-Request-Headers": "authorization",
        },
    )
    assert denied.status == 403
    print(" ", evidence_line(denied), "preflight=denied")

    fresh = request(host, port, "/api/orders", headers={"Origin": ALLOWED_ORIGIN})
    assert fresh.status == 200
    assert fresh.headers["etag"]
    assert fresh.headers["access-control-allow-origin"] == ALLOWED_ORIGIN
    print(" ", evidence_line(fresh), "etag=", fresh.headers["etag"])

    validated = request(
        host,
        port,
        "/api/orders",
        headers={"Origin": ALLOWED_ORIGIN, "If-None-Match": fresh.headers["etag"]},
    )
    assert validated.status == 304
    assert not validated.body
    print(" ", evidence_line(validated), "cache=conditional hit")

    asset = request(host, port, "/static/app.abc123.js")
    assert "immutable" in asset.headers["cache-control"]
    print(" ", evidence_line(asset), "cache=versioned asset immutable")


def run_protocol_decision(host: str, port: int) -> None:
    baseline = request(host, port, "/api/orders")
    assert baseline.status == 200
    print("[case protocol] negotiated=local HTTP/1.1 baseline")
    print(" ", evidence_line(baseline))
    print("  decision=先保留可回退基线；HTTP/2/3 需在真实链路测协商、代理兼容和收益")


def main() -> None:
    parser = argparse.ArgumentParser(description="运行 HTTP 综合实战病例")
    parser.add_argument(
        "--case",
        choices=("slow", "auth", "cors-cache", "protocol", "all"),
        default="all",
    )
    args = parser.parse_args()

    server, thread = start_server()
    host, port = server.server_address
    try:
        if args.case in {"slow", "all"}:
            run_slow_case(host, port)
        if args.case in {"auth", "all"}:
            run_auth_case(host, port)
        if args.case in {"cors-cache", "all"}:
            run_cors_cache_case(host, port)
        if args.case in {"protocol", "all"}:
            run_protocol_decision(host, port)
        print("result=PASS")
    except (AssertionError, KeyError) as exc:
        print(f"result=FAIL detail={exc}", file=sys.stderr)
        raise SystemExit(1) from exc
    finally:
        server.shutdown()
        server.server_close()
        thread.join(timeout=1)


if __name__ == "__main__":
    main()
